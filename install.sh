#!/bin/bash
# scripts/install.sh
set -euo pipefail

REPO="${XUPANEL_REPO:-quangvlog/xupanel-release}"
RELEASE="${XUPANEL_VERSION:-latest}"
BIN_DIR="${XUPANEL_BIN_DIR:-}"
DATA=/var/lib/xupanel
STAGING=""
[ "${XUPANEL_ACME_STAGING:-0}" = 1 ] && STAGING=" -acme-staging"

die() { echo "Lỗi: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "cần chạy bằng root: sudo bash install.sh"
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "xupanel hiện chỉ hỗ trợ Ubuntu"
[ "${VERSION_ID%%.*}" -ge 20 ] || die "cần Ubuntu 20.04 trở lên, máy đang chạy $VERSION_ID"
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "kiến trúc $(uname -m) chưa hỗ trợ" ;;
esac
systemctl is-active --quiet xupanel 2>/dev/null && die "xupanel đã cài trên máy này. Xem thông tin đăng nhập: sudo xupanel info"

echo "==> Cài Nginx"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx curl ca-certificates >/dev/null

if [ -z "$BIN_DIR" ]; then
  BIN_DIR="$(mktemp -d)"
  trap 'rm -rf "$BIN_DIR"' EXIT
  if [ "$RELEASE" = latest ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
  else
    BASE="https://github.com/$REPO/releases/download/$RELEASE"
  fi
  PKG="xupanel-linux-$ARCH.tar.gz"
  echo "==> Tải $PKG ($RELEASE)"
  curl -fsSL --retry 3 -o "$BIN_DIR/$PKG" "$BASE/$PKG" || die "không tải được $BASE/$PKG"
  curl -fsSL --retry 3 -o "$BIN_DIR/SHA256SUMS" "$BASE/SHA256SUMS" || die "không tải được SHA256SUMS"
  (cd "$BIN_DIR" && grep " $PKG\$" SHA256SUMS | sha256sum -c --quiet -) || die "checksum không khớp, tệp tải về bị hỏng hoặc bị sửa"
  tar -xzf "$BIN_DIR/$PKG" -C "$BIN_DIR"
fi
for f in xupanel xupanel-helper; do
  [ -x "$BIN_DIR/$f" ] || die "không thấy $BIN_DIR/$f"
done

echo "==> Tạo user hệ thống xupanel và www"
id xupanel >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir "$DATA" --shell /usr/sbin/nologin xupanel
id www >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /var/www --shell /usr/sbin/nologin www

echo "==> Chép chương trình"
install -m 0755 "$BIN_DIR/xupanel" /usr/local/bin/xupanel
install -m 0755 "$BIN_DIR/xupanel-helper" /usr/local/sbin/xupanel-helper
install -d -m 0700 -o xupanel -g xupanel "$DATA"
install -d -m 0755 -o xupanel -g xupanel /var/lib/xupanel-acme
install -d -m 0755 /var/www /etc/xupanel

cat > /etc/systemd/system/xupanel-helper.service <<'UNIT'
[Unit]
Description=xupanel root helper
After=network.target

[Service]
ExecStart=/usr/local/sbin/xupanel-helper -socket /run/xupanel/helper.sock -user xupanel
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/xupanel.service <<UNIT
[Unit]
Description=xupanel
After=network.target xupanel-helper.service
Wants=xupanel-helper.service

[Service]
User=xupanel
Group=xupanel
ExecStart=/usr/local/bin/xupanel -data $DATA$STAGING serve
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$DATA -/var/lib/xupanel-acme

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Lấy IPv4 public"
PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org || curl -4 -fsS --max-time 5 https://ifconfig.me || true)"

echo "==> Khởi tạo panel"
INFO="$(runuser -u xupanel -- /usr/local/bin/xupanel -data "$DATA" setup -public-ip "$PUBLIC_IP")"
PORT="$(sed -n 's/.*"port": *\([0-9]*\).*/\1/p' "$DATA/panel.json")"

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  echo "==> Mở port $PORT, 80, 443 trên ufw"
  ufw allow "$PORT/tcp" >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
fi

systemctl daemon-reload
systemctl enable --now xupanel-helper >/dev/null
systemctl enable --now xupanel >/dev/null
sleep 1
systemctl is-active --quiet xupanel || die "panel không chạy được, xem log: journalctl -u xupanel -n 50"

echo
echo "$INFO"
echo
echo "Lưu lại thông tin trên. Xem lại địa chỉ: sudo xupanel info"
