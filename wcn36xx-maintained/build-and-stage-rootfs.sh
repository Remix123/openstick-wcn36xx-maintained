#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src=${1:?usage: build-and-stage-rootfs.sh KERNEL_SOURCE_DIR ROOTFS_DIR}
rootfs=${2:?usage: build-and-stage-rootfs.sh KERNEL_SOURCE_DIR ROOTFS_DIR}
test -d "$rootfs/etc" || { echo "not a rootfs directory: $rootfs" >&2; exit 1; }

"$root/build-module.sh" "$src"
release=$(make -s -C "$src" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
module="$src/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko"
dest="$rootfs/lib/modules/$release/kernel/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko"
install -d -m 0755 "$(dirname "$dest")"
if [ -e "$dest" ] && [ ! -e "$dest.pre-maintained" ]; then
	cp -p "$dest" "$dest.pre-maintained"
fi
install -m 0644 "$module" "$dest"
"$root/install-rootfs-overlay.sh" "$rootfs"
if command -v depmod >/dev/null 2>&1; then
	depmod -b "$rootfs" "$release" || \
		echo 'depmod reported incomplete rootfs module metadata; inspect its output before deployment' >&2
else
	echo 'depmod not found on build host; regenerate modules.dep on target before loading this module' >&2
fi
echo "Staged $module into $rootfs for kernel $release"
