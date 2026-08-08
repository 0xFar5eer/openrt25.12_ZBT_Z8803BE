# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

发行版 `v25.12.018` 是面向 ZBTLink ZBT-Z8803BE 的社区固件构建。

## 主要变更
- 基于 OpenWrt `25.12.2`（`r32858-16347e93b6`）和 Linux `6.12.74`。
- 修复首次启动 Wi-Fi：在 UCI 默认配置写入后重新加载无线配置，干净刷机后无需手动执行 `wifi up`。
- 新增 Quectel USB/RNDIS 支持：RNDIS 模式使用独立的 DHCP 蜂窝上行，metric 为 `200`，并加入 WAN 防火墙区域。
- RNDIS 与 QModem 的 QMI/MBIM 生命周期分离，避免正常工作的 `usb0` DHCP 调制解调器被当作不受支持的 QMI 设备。
- SFP WAN（metric `9`）和 RJ45 WAN（metric `10`）仍优先于蜂窝回退。
- 5G1 默认上电；QMI/MBIM 调制解调器继续由 QModem 管理。

## 验证
- `make defconfig` 和完整 Docker 固件构建均已成功完成。
- 修改过的 shell 脚本已通过 `sh -n`；源码变更已通过 `git diff --check`。
- 生成镜像已通过 `sha256sum -c sha256sums --ignore-missing` 校验。
- 镜像 manifest 包含 `kmod-usb-net-rndis`、`qmodem`、`qmodem_monitor` 和 `wpad-openssl`。
- 安装后的首次启动 Wi-Fi 和 RNDIS 行为仍需要硬件实机验证。

## 构建产物
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `64e791598268bbf5b29141bc0a7bac17479b7b189a2d6dc565992f6a0db2d0de`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `070e89ab5415ae67c319c8b245b2c9f69d2894615f1e3e0fce67201e77725c31`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `6875eae6712978d9487f8dfcfc6b978854d1e618e7eebc4412ea554f6fc8e63c`
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
