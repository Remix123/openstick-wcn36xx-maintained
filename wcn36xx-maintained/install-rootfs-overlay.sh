#!/bin/sh
set -eu
src=${1:?usage: install-rootfs-overlay.sh ROOTFS_DIR}
test -d "$src/etc" || { echo "not a rootfs directory: $src" >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install -D -m 0755 "$root/wcn36xx-fixes" "$src/usr/local/sbin/wcn36xx-fixes"
install -D -m 0755 "$root/90-wcn36xx-disable-bgscan" "$src/etc/NetworkManager/dispatcher.d/90-wcn36xx-disable-bgscan"
install -D -m 0644 /dev/null "$src/etc/modprobe.d/wcn36xx-fixes.conf"
printf '%s\n' '# Managed by wcn36xx-fixes.' 'options wcn36xx disable_assoc_scan=1 tx_ack_race_fix=1 bmps_guard=1' > "$src/etc/modprobe.d/wcn36xx-fixes.conf"
install -D -m 0644 /dev/null "$src/etc/default/wcn36xx-fixes"
printf '%s\n' '# Managed by wcn36xx-fixes.' 'DISABLE_BGSCAN=1' > "$src/etc/default/wcn36xx-fixes"
echo "Installed WCN36xx runtime controls into $src"
