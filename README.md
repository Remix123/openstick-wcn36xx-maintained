# OpenStick WCN36xx 维护分支

这是基于 OpenStick/Linux `f17addf14f0ab2ef17e314249e0cfeb3fd7bcc9a`
维护的独立分支，加入了针对 MSM8916/WCNSS 的 WCN36xx 修复和运行时控制。
它不是上游 PR。分支中已经包含修复代码；不要在该分支上重复应用补丁。

## 修复内容

- WCNSS TX 完成事件与 DXE 中断竞态处理及 TX 状态队列保护。
- BMPS 进入条件检查；固件拒绝后停止重复尝试。
- RX DXE DMA 描述符的 `dma_rmb()` / `dma_wmb()` 顺序屏障。
- 已关联时可选择拒绝固件硬件扫描，规避异常候选漫游。
- 三个可写模块参数：`disable_assoc_scan`、`tx_ack_race_fix`、`bmps_guard`。

DMA 屏障是设备/CPU 内存顺序正确性要求，不提供运行时关闭选项。其余策略项可以在目标机运行时切换并持久化。

## 按 Wiki 构建

Wiki 原步骤推荐 Ubuntu 20.04，并列出 `binfmt-support`、`qemu-user-static`、
`gcc-10-aarch64-linux-gnu`、`kernel-package`、`fakeroot`、`simg2img`、
`img2simg`、`mkbootimg`、`bison` 等依赖。不同发行版的包名可能不同；
Debian 11/13 上若 `kernel-package` 不可用，可用受支持的内核 Debian
打包流程替代，不要因此跳过内核配置或 rootfs/initrd 步骤。

Ubuntu 20.04 上可按 Wiki 安装这些工具（另加常用编译工具）：

```sh
sudo apt update
sudo apt install -y git build-essential binfmt-support qemu-user-static \
  gcc-10-aarch64-linux-gnu kernel-package fakeroot simg2img img2simg \
  mkbootimg bison bc flex libssl-dev
```

克隆本仓库的维护分支：

```sh
git clone --depth 1 --branch codex/wcn36xx-maintained \
  https://github.com/Remix123/openstick-wcn36xx-maintained.git linux-openstick
cd linux-openstick
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
```

### 配置与编译

仓库的 `wcn36xx-maintained/config/target-kernel.config` 是本项目保存的
目标配置，包含 `CONFIG_USB_SERIAL=m`、`CONFIG_USB_SERIAL_OPTION=m` 及当前
OpenStick 内核配置。推荐用它保持与目标系统 ABI 一致：

```sh
cp wcn36xx-maintained/config/target-kernel.config .config
make olddefconfig
make menuconfig       # 可选；修改后保存 .config
make -j16
```

如需从干净的上游基线重放完整修复，而不是使用已打好补丁的维护分支：

```sh
git clone --depth 1 https://github.com/OpenStick/linux.git linux-upstream
git -C linux-upstream checkout f17addf14f0ab2ef17e314249e0cfeb3fd7bcc9a
cp -a wcn36xx-maintained linux-upstream/
./linux-upstream/wcn36xx-maintained/apply-patches.sh linux-upstream
```

补丁顺序见 `wcn36xx-maintained/patches/series`。维护分支本身已经含有同一组修复，不要再运行这一步。

按 Wiki 使用 `kernel-package` 生成内核 Debian 包时：

```sh
fakeroot make-kpkg --initrd --cross-compile aarch64-linux-gnu- \
  --arch arm64 kernel_image kernel_headers
```

生成的 `.deb` 在源码目录上层；同时保留 `arch/arm64/boot/Image.gz`、
相应设备树和 `initrd.img`。001b/001c 设备树分别为：

```text
arch/arm64/boot/dts/qcom/msm8916-handsome-openstick-ufi001b.dtb
arch/arm64/boot/dts/qcom/msm8916-handsome-openstick-ufi001c.dtb
```

### 将修复模块和控制工具装入 rootfs

Wiki 的 `rootfs.img` 通常是 Android sparse image。先转换并挂载，再将其目录作为参数：

```sh
simg2img rootfs.img root.img
mkdir -p /mnt/openstick-rootfs
sudo mount -o loop root.img /mnt/openstick-rootfs
sudo ./wcn36xx-maintained/build-and-stage-rootfs.sh \
  "$PWD" /mnt/openstick-rootfs
```

先按 Wiki 将生成的内核 `.deb` 放入 rootfs，并在 chroot 中安装，使它生成
匹配的 `/boot/initrd.img`：

```sh
sudo cp ../linux-image-*.deb ../linux-headers-*.deb /mnt/openstick-rootfs/tmp/
sudo mount --bind /proc /mnt/openstick-rootfs/proc
sudo mount --bind /dev /mnt/openstick-rootfs/dev
sudo mount --bind /dev/pts /mnt/openstick-rootfs/dev/pts
sudo mount --bind /sys /mnt/openstick-rootfs/sys
sudo chroot /mnt/openstick-rootfs /bin/sh -c \
  'dpkg -i /tmp/linux-image-*.deb /tmp/linux-headers-*.deb'
sudo umount /mnt/openstick-rootfs/dev/pts /mnt/openstick-rootfs/dev \
  /mnt/openstick-rootfs/proc /mnt/openstick-rootfs/sys
```

在安装内核包之后再运行 `build-and-stage-rootfs.sh`，避免 `.deb` 安装把
修复模块覆盖回去。该脚本会将 `wcn36xx.ko` 放入 rootfs 对应内核版本目录，
并安装模块参数默认值、NetworkManager 后台扫描策略和
`/usr/local/sbin/wcn36xx-fixes`。如果 rootfs 中已有同名驱动，会保留
`.pre-maintained` 备份。脚本在缺少 `Module.symvers` 时会先构建完整内核，
避免产生缺少符号版本信息的模块。

如果 initramfs 里包含旧的 `wcn36xx.ko`，在替换模块后更新 initramfs，然后
把生成的 initrd 拷出，最后解除 loop mount 并重新打包 rootfs：

```sh
sudo mount --bind /proc /mnt/openstick-rootfs/proc
sudo mount --bind /dev /mnt/openstick-rootfs/dev
sudo mount --bind /dev/pts /mnt/openstick-rootfs/dev/pts
sudo mount --bind /sys /mnt/openstick-rootfs/sys
sudo chroot /mnt/openstick-rootfs update-initramfs -u -k 5.15.0-handsomekernel+
sudo umount /mnt/openstick-rootfs/dev/pts /mnt/openstick-rootfs/dev \
  /mnt/openstick-rootfs/proc /mnt/openstick-rootfs/sys
cp /mnt/openstick-rootfs/boot/initrd.img-5.15.0-handsomekernel+ ./initrd.img
sudo umount /mnt/openstick-rootfs
img2simg root.img rootfs.img
```

### 生成 `boot.img`

选择与硬件对应的 001b 或 001c DTB，将 DTB 拼接到压缩内核后，再按 Wiki 参数生成镜像：

```sh
cat arch/arm64/boot/Image.gz \
  arch/arm64/boot/dts/qcom/msm8916-handsome-openstick-ufi001c.dtb > kernel-dtb

mkbootimg \
  --base 0x80000000 \
  --kernel_offset 0x00080000 \
  --ramdisk_offset 0x02000000 \
  --tags_offset 0x01e00000 \
  --pagesize 2048 \
  --second_offset 0x00f00000 \
  --ramdisk ./initrd.img \
  --cmdline "earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e console=ttyMSM0,115200 no_framebuffer=true rw" \
  --kernel kernel-dtb -o boot.img
```

将最终的 `boot.img` 和 `rootfs.img` 分别写入对应分区前，先确认设备型号、
分区映射及 `PARTUUID` 与目标机相符，并保留原镜像备份。不要直接照搬示例
PARTUUID 到不同设备。

## 目标机运行时启用/停用

部署并启动包含本维护分支驱动及 rootfs 控制文件的系统后，以 root 执行：

```sh
wcn36xx-fixes status
wcn36xx-fixes scan off       # 默认：禁止关联态硬件扫描，并关闭 wpa_supplicant bgscan
wcn36xx-fixes scan on        # 允许扫描，设置 simple:30:-65:300 bgscan
wcn36xx-fixes tx-ack off     # 关闭 TX 完成竞态修复（须先断开 Wi-Fi）
wcn36xx-fixes tx-ack on
wcn36xx-fixes bmps-guard off # 关闭 BMPS 保护
wcn36xx-fixes bmps-guard on
```

这些开关会立即写入可写模块参数，并保存到 modprobe 配置供下次加载使用。
`scan` 同时更新后台扫描策略。修改 TX 完成策略前必须先断开 WLAN；DMA 屏障始终启用。
这些是兼容性缓解/回退控制，不等同于修复或更新 WCNSS 固件本身。

## 参考

- [OpenStick Wiki：编译内核（Debian）](https://www.kancloud.cn/handsomehacker/openstick/2637565)
- [OpenStick/Linux 基线提交](https://github.com/OpenStick/linux/commit/f17addf14f0ab2ef17e314249e0cfeb3fd7bcc9a)
