# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

发行版 `v25.12.020` 是面向 ZBTLink ZBT-Z8803BE 的社区固件构建。

## 主要变更
- 基于 OpenWrt `25.12.2`（`r32858-16347e93b6`）和 Linux `6.12.74`。
- 按 issue #12 的要求新增内核模块，均以内可加载 kmod 构建：
  - `kmod-tcp-bbr` — BBR 拥塞控制
  - `kmod-bonding` — 链路聚合
  - `kmod-tls` — 内核 TLS，作为 bonding 的依赖一并引入
- 相比 `v25.12.019`，调制解调器、无线与 LuCI 行为均未变更。
- 随镜像一同发布 `packages-aarch64_cortex-a53.tar.gz`：由本次完全相同的构建配置生成的完整软件包源，可在设备上以匹配的本地产源安装软件包，避免与在线 snapshot 源版本不一致。

## 验证
- `make defconfig` 保留了 `kmod-tcp-bbr`、`kmod-bonding` 和 `kmod-tls`。
- 完整 Docker 固件构建成功完成。
- 镜像 manifest 中三个模块版本均为 `6.12.74-r1`。
- 生成镜像通过 `sha256sum -c sha256sums --ignore-missing` 校验。
- `tests/check-zbt-firmware.sh` 与 `git diff --check` 通过。
- 发布的 `sha256sums` 仅覆盖固件产物；软件包源包的摘要单独列于本说明。
- 维护者**尚未**在实机上加载验证这三个模块。构建和静态验证不代表硬件已验证。

## 构建产物
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `b79322f99dc47c41432523ce89bf875d3a482f39831c4965ffa4e5d5dfe4dfbd`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `2095f444768ef7e3da12275d2bd9292ce1c2c58e56ece5d3e2a3b5cbf0067e6d`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `072b12265a71173feaf1e5f8d2003973f77c4dfa6ecfb508c84674ff75aea843`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `69e1a0cb8d3b76819820682485a9570dda65e96862271c329b12793bd1ed2784`
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
