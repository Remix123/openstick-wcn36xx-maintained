#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src=${1:?usage: build-module.sh KERNEL_SOURCE_DIR}
if [ "$#" -ne 1 ]; then echo 'usage: build-module.sh KERNEL_SOURCE_DIR' >&2; exit 2; fi
base=f17addf14f0ab2ef17e314249e0cfeb3fd7bcc9a
reference=${KERNEL_BUILD_REFERENCE:-/root/openstick/build-20260923-rebuild-001bc-0715/src/linux}
[ -d "$reference" ] || reference=

test -d "$src/.git" || git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || {
	echo "not a Git kernel source tree: $src" >&2; exit 1;
}
head=$(git -C "$src" rev-parse HEAD)
has_patch_markers() {
	grep -q 'module_param_named(disable_assoc_scan' "$src/drivers/net/wireless/ath/wcn36xx/main.c" &&
	grep -q 'module_param_named(tx_ack_race_fix' "$src/drivers/net/wireless/ath/wcn36xx/main.c" &&
	grep -q 'module_param_named(bmps_guard' "$src/drivers/net/wireless/ath/wcn36xx/main.c" &&
	grep -q 'if (wcn36xx_disable_assoc_scan && vif_priv->sta_assoc)' "$src/drivers/net/wireless/ath/wcn36xx/main.c" &&
	grep -q 'dma_rmb();' "$src/drivers/net/wireless/ath/wcn36xx/dxe.c" &&
	grep -q 'dma_wmb();' "$src/drivers/net/wireless/ath/wcn36xx/dxe.c" &&
	grep -q 'wcn36xx_dxe_tx_status_queued' "$src/drivers/net/wireless/ath/wcn36xx/dxe.c" &&
	grep -q 'wcn36xx_bmps_guard' "$src/drivers/net/wireless/ath/wcn36xx/pmc.c"
}

if [ "$head" = "$base" ] && ! has_patch_markers; then
	if [ -n "$(git -C "$src" status --porcelain)" ]; then
		echo 'refusing to patch a dirty, partially patched base tree' >&2
		exit 1
	fi
	"$root/apply-patches.sh" "$src"
elif ! has_patch_markers; then
	echo "source is neither base $base nor a tree containing the complete fix series" >&2
	exit 1
fi
git -C "$src" diff --check

if [ ! -r "$src/.config" ]; then
	if [ -n "$reference" ] && [ -r "$reference/.config" ]; then
		cp "$reference/.config" "$src/.config"
	elif [ -r "$root/config/target-kernel.config" ]; then
		cp "$root/config/target-kernel.config" "$src/.config"
	else
		echo 'no kernel config found; provide .config or config/target-kernel.config' >&2
		exit 1
	fi
fi
if [ ! -r "$src/Module.symvers" ] && [ -n "$reference" ] && [ -r "$reference/Module.symvers" ]; then
	cp "$reference/Module.symvers" "$src/Module.symvers"
fi
make -C "$src" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make -C "$src" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
if [ -r "$src/Module.symvers" ]; then
	make -C "$src" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
		M="$src/drivers/net/wireless/ath/wcn36xx" modules
else
	jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
	echo "Module.symvers absent; building the full kernel first with JOBS=$jobs"
	make -j"$jobs" -C "$src" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz dtbs modules
fi

module="$src/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko"
test -s "$module"
modinfo "$module" | grep -q '^parm:.*disable_assoc_scan:'
modinfo "$module" | grep -q '^parm:.*tx_ack_race_fix:'
modinfo "$module" | grep -q '^parm:.*bmps_guard:'
printf 'Built module: %s\n' "$module"
modinfo "$module" | grep -E '^(srcversion|vermagic|parm):'
sha256sum "$module"
