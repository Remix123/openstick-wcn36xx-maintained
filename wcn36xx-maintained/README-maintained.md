# WCN36xx 修复构建工具

完整的中文编译、rootfs 暂存、boot.img 生成和目标机开关说明见仓库根目录
[`README.md`](../README.md)。本目录包含补丁序列、构建/暂存脚本及目标机控制工具。

- `patches/series`：在 OpenStick/Linux 基线 `f17addf14f0ab2ef17e314249e0cfeb3fd7bcc9a` 上重放补丁。
- `apply-patches.sh KERNEL_SOURCE_DIR`：将补丁应用到干净源码。
- `build-module.sh KERNEL_SOURCE_DIR`：自动校验/应用补丁并编译驱动；缺少 `Module.symvers` 时先构建完整内核。
- `build-and-stage-rootfs.sh KERNEL_SOURCE_DIR ROOTFS_DIR`：构建模块并安装模块与运行时控制到 rootfs。
- `wcn36xx-fixes status|scan|tx-ack|bmps-guard`：目标机 root 下切换可运行时关闭的兼容性策略。

DMA 内存屏障始终保留，不提供关闭开关；切换 TX 完成策略前必须断开 WLAN。
