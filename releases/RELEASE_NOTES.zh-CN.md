# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

`v25.12.022` 是面向 ZBTLink ZBT-Z8803BE 的社区固件版本。这是新发布的版本，不是对 `v25.12.021` 的原位刷新：021 中已验证的内容全部保留，本页只描述自该 tag 以来的变化。OpenWrt 基线与内核不变。

## 亮点

本版本吸收了上游 QModem PR #14 的安全子集（拨号器修复与 MLO 共享接口修复），加固了两个只有在插入第二块 modem 后才真正起作用的热插拔处理器，并把补丁触及的软件包收编进源码树，让修复随镜像发布而不再等 feed。

### 1. QModem 拨号器：五项修复，收编（vendor）

整个 `qmodem` 应用（3.0.2）现在以 `package/qmodem/` 的形式进入源码树，与 `autocore` fork 同一模式。feed 的 Makefile 直接从其 `files/` 目录安装、无法携带补丁，要发布修复过的 `modem_dial.sh` 就必须收编；收编副本取代 feed 包（清单中为 `qmodem - 3.0.2-r1`）。自 PR #14 改编：

- `modem_dial.sh` 的两个 shell 语法错误：`unlock_sim` 里"该 PIN 本次开机已试过"守卫的 `]` 前缺空格，比较总是报错并走假分支，导致每次拨号都向已被拒绝的 PIN 重新发送 `AT+CPIN=`（modem 会计数失败次数并最终转入 PUK）。`update_config` 内 `suggest_pdp_index` 回退的同类 `]` 缺空格错误，使选项未设置时平台建议的 PDP index 永远不会被填上。
- SIM 槽位 2 分支现在在 `pincode2` 未设置时回退到 modem 级 `pincode`；此前它把公共 PIN 取进了未使用的变量，导致槽位 2 上只设置了 `pincode` 的锁卡 SIM 永远不会解锁。
- metric 保留：`set_if()` 每次重拨都会把 qmodem profile 的 `metric` 复制进 `network.<iface>.metric`，覆盖路由器级的路由约定（SFP `9`、RJ45 WAN `10`、蜂窝 `200`）。现在数值型的 `network.<iface>.metric` 优先于 profile 值，蜂窝 metric 不会再偏离 WAN 故障切换的播种值。
- 重拨保留：挂断/清理流程不再删除主 `network.<iface>` section，只清除运行时的 `ifname`/`device` 绑定，保留 `modem_config`、`defaultroute=1` 与 metric，并且不动 `dns`/`peerdns`，用户的 DNS 修改与路由 metric 在重拨后得以保留。IPv6 伴随 section 仍按现行 PDP 模式删除重建。

### 2. RNDIS 热插拔不再重启整个拨号器栈

`15-zbt-rndis-auto` 在识别出 Quectel RNDIS 组合并禁用对应 QModem profile 后，原本全局重启 `qmodem_network`，把所有已配置 modem 的拨号循环全部打断。现在只挂断该 profile 对应的 procd 实例（`modem_4_1`/`modem_4_2`），按 USB 路径推导。单 modem 时可见行为完全一致；装了第二块 modem 后，无关的拨号器不再被打断。

### 3. 前面板 modem LED 按精确 USB 槽位绑定

`20-zbt-modem-led` 此前按 USB 路径后缀匹配推导槽位，WWAN netif 若出现在 `2-1`、`1-1` 这类 MT7988A 根集线器端口（后面没有 modem 槽位）上，就会被绑到 5G1/5G2 前面板 LED。热插拔现在按精确槽位从 `qmodem.@modem-slot[N].led` 解析 LED（由 `20-zbt-qmodem-slots` 播种 `blue:mobile-1`/`blue:mobile-2`），保留 `4-1`/`4-2` 硬编码回退以兼容旧配置，未映射路径则打日志且不做绑定。

### 4. MLO 页面现在写出 netifd 真正消费的形态——附带一次性修复

`luci-app-mlo` 已收编并重写页面（自 PR #14 改编）：保存 MLD 时写出一个 `wifi-iface`，其 `device` 是参与 radio 的列表并带 `mlo='1'`、`ieee80211w='2'`，而不是每个频段一个标量 device section。旧表示每条记录只带一条链路，hostapd 永远不会组成多链路组。从已有 MLD 中移除的频段会改写为独立 section，并保留各频段的 PMF 规则。

新增 `74-zbt-mlo-shared-iface-repair` 在首次开机迁移旧页面写下的分组：同一 SSID 的 `mlo=1` AP section 组若含两块及以上 radio，会被改写为共享多 device 表示，冗余的成员 section 与每条记录的 `mld_ap`/`mld_id` 选项被删除，并显式加入 LAN。普通 AP 与单链路分组不动；脚本带板级守卫，仅在有改动时提交。

### 5. 软件源 tar 包重新生成

`packages-aarch64_cortex-a53.tar.gz` 按本次构建的软件源树重新生成，保持原有 156 包布局（157 个 tar 条目）。它现在携带修复后的收编 `qmodem-3.0.2-r1` apk 与当前构建的 `luci-app-zbt-about`；`v25.12.021` 的 tar 包是在拨号器修复存在之前组装的（021 固件镜像本身不受影响——修复过的拨号器在镜像内，滞后的只是 feed tar 包）。重新生成时还清除了 021 遗留在 feed 树中的过时 apk（被取代的 `luci-app-zbt-about-26.218.24774~bd3a8ec`），tar 包恢复为每个软件包恰好一个 apk。

### 6. 其他

- 清单：280 个软件包，镜像保持约 20.7 MB。`qmodem` 与 `luci-app-mlo` 现在来自收编副本（`qmodem - 3.0.2-r1`、`luci-app-mlo - 26.221.38405~a36ca24`）；QModem 伴随应用（`luci-app-qmodem-monitor`/`-next`/`-ttlfw4`、`qmodem_monitor`）同样显示收编版本号。

## 验证

- Docker 完整重建成功；全部附件 `sha256sum -c sha256sums --ignore-missing` 通过。
- 在构建卷内检查了暂存的 rootfs：五项拨号器修复全部出现在安装后的 `modem_dial.sh` 中；feed 的 `qmi|mbim|mhi) proto="none"` 接管代码不存在；RNDIS 按实例挂断、精确槽位 LED 解析、播种的 `led` 选项、MLO 修复脚本与重写后的 MLO 页面均在。
- `tests/check-zbt-firmware.sh`——本轮扩充了按实例挂断守卫（RNDIS 热插拔中出现全局 `qmodem_network restart` 将导致检查失败）、精确路径 LED 映射、播种 `led` 选项、五项收编拨号器修复与 MLO 修复——加上 MLO 页面的 `node --check` 与 `git diff --check` 全部通过。检查器同时禁止刻意未采纳的 PR 部分（`dual-modem.sh`、`zbt_netcard`、`proto="none"` 的 QMI 接管）。
- 重新生成的 feed tar 包与全新软件源树逐成员核对：157 个条目，其中 `qmodem-3.0.2-r1.apk` 与镜像构建所用的 apk 字节一致。
- **未做硬件验证：** MLO 客户端关联（本轮没有可用的 MLO 客户端）、SIM 槽位 2 的 PIN 路径（本机单 SIM 接线），以及一切依赖第二块 modem 的场景——5G2 槽位未插卡，PR #14 其余双 modem 工作推迟到硬件到手。本机的蜂窝单元（RM551E-GL、QMI、槽位 4-1）及其已验证的 issue #9 行为不受本版本影响。

## 附件

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `37d2364c3219afb26b9c9b2e6ccdea8a73fe7941de2a0d39b2bb0a9368991ea9`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `ff1e023ee2aa1170778552db9e58e334226d3c60d5ef0f3c4daa6250cb2a02cf`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `b7773d432b257ac851b2c973e0397bcbb6eb6f588aa32c0740806c1c8715fc7a`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `fc7b71089f4e1ab3f280294d4bdb64b7acff1018a207b73f99de16e0b771a9ae`
- `sha256sums`、`config.buildinfo`、`feeds.buildinfo`、`version.buildinfo`

## 升级
保留配置：

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

全新配置：

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

从 v25.12.021 保留配置升级时：

- 一次性 `74-zbt-mlo-shared-iface-repair` 会在首次开机把旧 MLO 页面创建的分组改写为共享表示；此后在页面保存的 MLD 直接使用新表示。从未配置过 MLO 组则什么都不发生。
- 现有 `network.<蜂窝>.metric`、`dns` 与 `peerdns` 现在能在重拨后保留；升级后无需重新填写。

## 捐赠
捐赠是对维护和测试工作的支持：

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
