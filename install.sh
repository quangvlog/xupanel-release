#!/bin/bash
# scripts/install.sh
set -euo pipefail

REPO="${XUPANEL_REPO:-quangvlog/xupanel-release}"
RELEASE="${XUPANEL_VERSION:-latest}"
BIN_DIR="${XUPANEL_BIN_DIR:-}"
DATA=/var/lib/xupanel
LOG=/var/log/xupanel-install.log
STAGING=""
[ "${XUPANEL_ACME_STAGING:-0}" = 1 ] && STAGING=" -acme-staging"

die() { echo; echo "Loi: $*" >&2; echo "Chi tiet: $LOG" >&2; exit 1; }
run() { "$@" >>"$LOG" 2>&1; }

[ "$(id -u)" = 0 ] || { echo "Loi: can chay bang root (sudo)" >&2; exit 1; }
: >"$LOG"
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "xupanel hien chi ho tro Ubuntu"
[ "${VERSION_ID%%.*}" -ge 20 ] || die "can Ubuntu 20.04 tro len, may dang chay $VERSION_ID"
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "kien truc $(uname -m) chua ho tro" ;;
esac
systemctl is-active --quiet xupanel 2>/dev/null && { echo "xupanel da cai tren may nay. Xem thong tin dang nhap: sudo xupanel info"; exit 0; }

ADMIN_USER=""
ADMIN_PASS=""
if { exec 3</dev/tty; } 2>/dev/null; then
  while :; do
    printf "Nhap ten dang nhap (bo trong se tao ngau nhien): " >/dev/tty
    read -r ADMIN_USER <&3 || ADMIN_USER=""
    ADMIN_USER="$(printf '%s' "$ADMIN_USER" | tr 'A-Z' 'a-z')"
    if [ -z "$ADMIN_USER" ] || [[ "$ADMIN_USER" =~ ^[a-z0-9_.-]{1,32}$ ]]; then break; fi
    echo "  Chi dung chu a-z, so 0-9, dau _ . - , toi da 32 ky tu." >/dev/tty
  done
  while :; do
    printf "Nhap mat khau (bo trong se tao ngau nhien): " >/dev/tty
    read -rs ADMIN_PASS <&3 || ADMIN_PASS=""
    echo >/dev/tty
    [ -z "$ADMIN_PASS" ] && break
    if [ "${#ADMIN_PASS}" -lt 8 ]; then
      echo "  Mat khau can it nhat 8 ky tu." >/dev/tty
      continue
    fi
    printf "Nhap lai mat khau: " >/dev/tty
    read -rs AGAIN <&3 || AGAIN=""
    echo >/dev/tty
    [ "$AGAIN" = "$ADMIN_PASS" ] && break
    echo "  Hai lan nhap khong khop, nhap lai." >/dev/tty
  done
  exec 3<&-
fi

echo "Dang cai dat xupanel, vui long doi 1-2 phut..."

export DEBIAN_FRONTEND=noninteractive
CDROM='^[[:space:]]*deb(-src)?[[:space:]]+(\[[^]]*\][[:space:]]+)?(cdrom:|file:/+(media/)?cdrom)'
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] && grep -Eq "$CDROM" "$f" || continue
  echo "tat nguon CD trong $f, sao luu: $f.xupanel-bak" >>"$LOG"
  cp "$f" "$f.xupanel-bak"
  sed -Ei "s@($CDROM)@# \\1@" "$f"
done
if ! command -v curl >/dev/null; then
  run apt-get update || die "apt-get update loi, kiem tra nguon tai goi trong /etc/apt/sources.list"
  run apt-get install -y curl ca-certificates || die "khong cai duoc curl"
fi

if [ -z "$BIN_DIR" ]; then
  BIN_DIR="$(mktemp -d)"
  trap 'rm -rf "$BIN_DIR"' EXIT
  if [ "$RELEASE" = latest ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
  else
    BASE="https://github.com/$REPO/releases/download/$RELEASE"
  fi
  PKG="xupanel-linux-$ARCH.tar.gz"
  run curl -fsSL --retry 3 -o "$BIN_DIR/$PKG" "$BASE/$PKG" || die "khong tai duoc $BASE/$PKG"
  run curl -fsSL --retry 3 -o "$BIN_DIR/SHA256SUMS" "$BASE/SHA256SUMS" || die "khong tai duoc SHA256SUMS"
  (cd "$BIN_DIR" && grep " $PKG\$" SHA256SUMS | sha256sum -c --quiet -) >>"$LOG" 2>&1 || die "checksum khong khop, tep tai ve bi hong hoac bi sua"
  run tar -xzf "$BIN_DIR/$PKG" -C "$BIN_DIR"
fi
for f in xupanel xupanel-helper; do
  [ -x "$BIN_DIR/$f" ] || die "khong thay $BIN_DIR/$f"
done

id xupanel >/dev/null 2>&1 || run useradd --system --user-group --no-create-home --home-dir "$DATA" --shell /usr/sbin/nologin xupanel
id www >/dev/null 2>&1 || run useradd --system --user-group --no-create-home --home-dir /var/www --shell /usr/sbin/nologin www

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

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>>"$LOG" || curl -4 -fsS --max-time 5 https://ifconfig.me 2>>"$LOG" || true)"
INFO="$(printf '%s\n' "$ADMIN_PASS" | runuser -u xupanel -- /usr/local/bin/xupanel -data "$DATA" setup -public-ip "$PUBLIC_IP" -user "$ADMIN_USER" -password-stdin 2>>"$LOG")" || die "khong khoi tao duoc panel"
PORT="$(sed -n 's/.*"port": *\([0-9]*\).*/\1/p' "$DATA/panel.json")"

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  run ufw allow "$PORT/tcp"
  run ufw allow 80/tcp
  run ufw allow 443/tcp
fi

run systemctl daemon-reload
run systemctl enable --now xupanel-helper
run systemctl enable --now xupanel
sleep 1
systemctl is-active --quiet xupanel || die "panel khong chay duoc, xem: journalctl -u xupanel -n 50"

echo
echo "$INFO"
