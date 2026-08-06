# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

发行版 `v25.12.017` 是为 ZBTLink ZBT-Z8803BE 验证过的社区固件。

## 主要变更
- 基于 OpenWrt `25.12.2`（`r32858-16347e93b6`）和 Linux `6.12.74`。
- 配置 SFP WAN（metric `9`）、RJ45 WAN（metric `10`）和就绪 SIM 卡的蜂窝回退（metric `200`）。
- 开机为 5G1 插槽供电，自动启动 QModem 发现和拨号，并持久启用 ZBT QModem 看门狗以修复调制解调器的延迟状态重写。
- 包含 Argon、QModem Next、Modem Events、短信工具，以及本地 ZBT About、Health、Temperature 和 Modem Events LuCI 应用。
- 使用确定性 DNS，不包含 USB/iPhone 网络共享默认配置。

## 验证
- `make defconfig` 和完整 Docker 固件构建均已成功完成。
- 首次启动和看门狗脚本已通过 `sh -n`；源码变更已通过 `git diff --check`。
- 已在 ZBT-Z8803BE 上执行干净的 `sysupgrade -n`，无需任何手动修正命令。
- 首次启动后，5G1 已上电，QModem `4_1` 插槽已启用，看门狗已启用并运行；WWAN 获得 IPv4 地址，`ping -I wwan0 1.1.1.1` 为 0% 丢包。

## 构建产物
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`、`config.buildinfo`、`feeds.buildinfo` 和 `version.buildinfo`

## 刷机
保留配置：

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

清零刷机：

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

## 捐赠
可选捐赠将用于支持维护和测试：

- **ERC20 / BEP20 — USDT、USDC、ETH、BNB：** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX、USDT：** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC：** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC：** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
