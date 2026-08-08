# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

发行版 `v25.12.018` 是面向 ZBTLink ZBT-Z8803BE 的社区固件构建。

## 主要变更
- 基于 OpenWrt `25.12.2`（`r32858-16347e93b6`）和 Linux `6.12.74`。
- 修复首次启动 Wi-Fi：在 UCI 默认配置写入后重新加载无线配置，干净刷机后无需手动执行 `wifi up`。
- 修正 Quectel USB/RNDIS 管理：在 `usb0` 等实际网卡创建后的 net hotplug 事件中配置 DHCP 蜂窝上行，而不再依赖更早发生的 USB 事件。
- 仅在检测到 Quectel `rndis_host` 设备时抑制 QModem 的 `wwan0`/QMI 恢复流程，避免反复重启不存在的 `wwan0` 配置。
- RNDIS 与 QModem 的 QMI/MBIM 生命周期保持分离，蜂窝 metric 保持 `200`；SFP WAN（metric `9`）和 RJ45 WAN（metric `10`）仍优先。
- 5G1 默认上电；QMI/MBIM 调制解调器继续由 QModem 管理。

## 验证
- `make defconfig` 和完整 Docker 固件构建均已成功完成。
- 修改过的 shell 脚本已通过 `sh -n`；源码变更已通过 `git diff --check`。
- 生成镜像已通过 `sha256sum -c sha256sums --ignore-missing` 校验。
- 镜像 manifest 包含 `kmod-usb-net-rndis`、`qmodem`、`qmodem_monitor` 和 `wpad-openssl`。
- 安装后的首次启动 Wi-Fi 和 Quectel RNDIS/QModem 抑制行为仍需要实机验证；此修正构建尚未在维护者自己的路由器上测试。

## 构建产物
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `49b5e74fb7e46d23641dcf7386bc8b2a134b591a3e07d2b58edd04d051e0726b`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `1d53ebdcbca8e8cacdaee518277d1a9ce1d45632c06c8bfc2c65393427be4c19`
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
