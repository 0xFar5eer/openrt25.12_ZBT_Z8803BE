# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

发行版 `v25.12.019` 是面向 ZBTLink ZBT-Z8803BE 的社区固件构建。

## 主要变更
- 基于 OpenWrt `25.12.2`（`r32858-16347e93b6`）和 Linux `6.12.74`。
- 新增 LuCI **网络 → WiFi 7 MLO** 页面。MLO 保持按需启用；出厂无线默认配置仍是独立的各频段 SSID。
- 包含 GNU `timeout` 命令，路径为 `/usr/bin/timeout`。
- QModem 恢复逻辑现已识别物理插槽：USB `4-1` 对应 5G1 / `4_1`，USB `4-2` 对应 5G2 / `4_2`。固件维护对应的 QModem、网络和 WAN 防火墙配置，不会修改另一个插槽。
- 5G1 保持默认供电；5G2 仍需要通过 GPIO 开关手动启用。有线 WAN 与 SFP 的 metric 更低，优先于蜂窝网络。
- 保留此前的 Quectel RNDIS 分离行为：只有属于该 RNDIS 调制解调器的 QModem 配置会被禁用。

## 验证
- `make defconfig` 保留了 `luci-app-mlo`、`wpad-openssl` 和 `coreutils-timeout`。
- 完整 Docker 固件构建成功完成。
- 修改的 shell 脚本通过 `sh -n`；`tests/check-zbt-firmware.sh` 与 `git diff --check` 通过。
- 生成镜像通过 `sha256sum -c sha256sums --ignore-missing` 校验。
- 镜像 manifest 包含 `luci-app-mlo`、`wpad-openssl` 和 `coreutils-timeout`。
- 解开的 SquashFS 包含 `/usr/bin/timeout`、MLO LuCI 菜单、ACL 与 `mlo/main.js` 视图。
- 维护者**尚未**实机测试 MLO 关联/多链路流量，以及 5G2/modem 2/SIM2 的连接行为。构建和静态验证不代表硬件已验证。

## 构建产物
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `296339130bcfd945567e38018f9ea7557595e4b04a705dc0a760865ba8f2ce43`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `3f9bc4acfdb50e2f1a2b4695ab1710e7df5756040830decbc1707b3b8993a242`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `e8001906fb4fa60cc71636e2bd6d3c1f01a29bec0e5afa5773cd1b18b7c616a7`
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
