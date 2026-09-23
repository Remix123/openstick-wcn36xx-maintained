#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src=${1:?usage: apply-patches.sh KERNEL_SOURCE_DIR}
while IFS= read -r patch; do
	case "$patch" in ''|\#*) continue ;; esac
	printf 'Applying %s\n' "$patch"
	git -C "$src" apply --check "$root/$patch"
	git -C "$src" apply "$root/$patch"
done < "$root/patches/series"
git -C "$src" diff --check
printf 'WCN36xx fix series applied cleanly to %s\n' "$src"
