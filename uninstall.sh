#!/bin/bash
# scripts/uninstall.sh
set -uo pipefail

[ "$(id -u)" = 0 ] || { echo "Loi: can chay bang root (sudo)" >&2; exit 1; }

echo "Dang go xupanel..."
systemctl disable --now xupanel xupanel-helper >/dev/null 2>&1
rm -f /etc/systemd/system/xupanel.service /etc/systemd/system/xupanel-helper.service
systemctl daemon-reload
rm -f /usr/local/bin/xupanel /usr/local/sbin/xupanel-helper
rm -rf /var/lib/xupanel /var/lib/xupanel-acme /run/xupanel /var/log/xupanel-install.log /var/log/xupanel-update.log
id xupanel >/dev/null 2>&1 && userdel xupanel

echo "Da go xupanel."
echo "Website, du an, Nginx, user www va chung chi trong /etc/xupanel duoc giu lai de website van chay."
