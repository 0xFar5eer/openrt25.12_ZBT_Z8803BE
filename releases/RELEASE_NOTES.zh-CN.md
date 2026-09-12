# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

`v25.12.023` 是基于 `v25.12.022` 的维护版本。OpenWrt 基线（`r32858-16347e93b6`）、内核（`6.12.74`）与软件包集合均不变；本镜像包含两处来自排查维护者设备上蜂窝连接卡死事件的修复。

## 亮点

### 1. Modem 监控 worker：三项修复

QModem 监控的 worker 脚本在源码树副本（`usr/lib/zbt/qmodem-modem_monitor.sh`）中加固，与之前一样由 `52-zbt-qmodem-monitor-overlay` 在首次开机覆盖 feed 的 `/usr/share/qmodem/modem_monitor.sh`：

- **探针结果严格校验。** 此前 HTTP 探针把任何 `curl` 退出码为 0 的调用都视为成功。墙中园/portal 应答（302 跳转或 200 落地页）因此会重置失败计数，卡死的连接在监控运行数小时后也永远达不到动作阈值。匹配 `*generate_204*` 的探针 URL 现在必须精确返回 `204`；其他 URL 接受任意 2xx/3xx。
- **恢复连击。** 失败计数只有在 `zbt_monitor_recovery_streak`（默认 `3`）次连续良好探针后才清零，单次偶然成功不再清除失败连击。默认值为仅运行时生效（`qmodem.main.zbt_monitor_recovery_streak`），刻意不写入 UCI。
- **动作冷却在派发之后记录。** 守卫脚本会再次检查同一冷却并在其活跃时拒绝执行，因此先记录冷却再 `run_actions` 使每次派发都成为自我阻塞的空操作。

监控默认值不变，仍然**关闭**（`monitor_enabled=0`）。若你启用了监控，保留配置升级时会在首次开机替换 worker 并重启服务；从未启用则什么都不发生。

### 2. WiFi 客户端名称显示规范化（luci-app-wifi-clients）

DHCP 主机名经常由设备自己全小写上报（`robot-2fl`），与手工命名的条目放在一起很不好看。采集器现在渲染显示名：楼层标签（`1FL`/`2FL`/`3FL`）与缩写（`LG`、`TV`、`AP`）保持大写，其余按「连字符分隔的 Title Case」渲染，混合大小写 token（iPhone、OpenWrt、G5Pro）与十六进制 id 形态的 token（69D1、1B28）原样保留，结尾的 `.lan` 后缀保持小写，`unknown-<mac>` 回退名不做处理。静态名称与租约上报名称均会规范化。

注意：精简镜像中不预装 `luci-app-wifi-clients` —— 该修复面向按需选择此软件包的用户。

### 3. 其他

- 清单：280 个软件包，镜像保持约 20.7 MB。`qmodem - 3.0.2-r1`、`qmodem_monitor - 3.0.2-r1`、`luci-app-mlo - 26.254.33408~0ac766c`（版本戳跟随构建树 commit）。
- `packages-aarch64_cortex-a53.tar.gz` 与 `v25.12.022` 的 tar 包字节一致（SHA-256 相同）：本版本没有任何 feed 侧可见的变化。

## 验证

- Docker 完整重建成功；全部附件 `sha256sum -c sha256sums --ignore-missing` 通过。
- `tests/check-zbt-firmware.sh`——本轮扩充了 strict-204 探针、恢复连击、先派发后记录冷却的顺序守卫，以及采集器显示名规范化的守卫——加上 `git diff --check` 全部通过。
- 加固后的监控脚本与维护者 RM551E-GL（QMI、槽位 4-1）设备上在引发本次修复的事件期间实机验证过的内容相同：严格探针把 portal 应答判为失败，完整恢复链路（探针 → 阈值 → 动作 → 冷却 → 恢复连击）已在该设备上通过一次刻意故障测试端到端验证。实机验证副本与树内副本唯一的差异是一条泛化了的注释。
- **未做硬件验证：** `v25.12.023` 镜像本身尚未刷入开发板——本 tag 没有走 sysupgrade 路径。显示名规范化仅有单元检查覆盖；维护者设备并未运行 `luci-app-wifi-clients`。`v25.12.022` 中列为未硬件验证的项目（MLO 客户端关联、SIM 槽位 2 的 PIN 路径、以及一切依赖第二块 modem 的场景）仍然未验证。

## 附件

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `1a7ba593cb00d84c2920a977cd95d1666270314a3f808da60c721b7c3a833fd2`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `789bc85751c8cafb0da68c9ac876590968728078d52ab3ddb30d8b4e5df7ba3b`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `2f9c1628d40ad17c43779c54bfd3f0c847718f9565b7580eb85e5653c3d15162`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `fc7b71089f4e1ab3f280294d4bdb64b7acff1018a207b73f99de16e0b771a9ae`
- `sha256sums`、`config.buildinfo`、`feeds.buildinfo`、`version.buildinfo`

## 升级
保留配置：

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

全新配置：

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

从 `v25.12.022` 保留配置升级时：

- 不运行任何迁移，存储的值不变。若监控已启用，首次开机安装加固后的 worker 并重启监控服务；否则什么都不发生。
- `v25.12.022` 的全部行为（收编拨号器修复、RNDIS 按实例挂断、精确路径 modem LED、MLO 共享接口表示及其一次性修复）原样保留。

## 捐赠
捐赠是对维护和测试工作的支持：

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
