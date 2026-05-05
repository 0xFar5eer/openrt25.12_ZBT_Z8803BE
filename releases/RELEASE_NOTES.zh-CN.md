# ZBT-Z8803BE OpenWrt 25.12.2 稳定版移植

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-2-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`
- **固件内摘要:** **About** (`/cgi-bin/luci/admin/about`) 是功能/软件包/修复说明的固件内主摘要；本发布说明沿用同一组分类，并补充验证、校验值和刷机步骤。

## 本次更新

- **切换到官方 OpenWrt `v25.12.2`。** 当前分支以稳定标签为干净基线，再叠加 ZBT-Z8803BE 板级支持和固件定制；内核使用 OpenWrt 25.12.2 自带的稳定 `6.12.74`。
- **移植 ZBT-Z8803BE 板级支持。** 包含 DTS/镜像 profile、LED/网络/GPIO switch 配置、NAND 升级支持、base-files overlay、调制解调器 LED 服务、QModem 默认值、WAN/WWAN metric 默认值、APK 软件源、LuCI 默认值以及 shell/banner 默认项。
- **内置 ZBT 温度监控和风扇策略。** 固件自带 `luci-app-zbt-temperature`、`/usr/sbin/zbt-temperature-log`、cron/tmpfs 历史记录、CPU/WiFi/调制解调器/风扇采样，以及之前优化过的用户态风扇调速逻辑。
- **新增内置 ZBT Health 页面。** 固件自带 `luci-app-zbt-health`、`/usr/sbin/zbt-health-json`、只读 LuCI **服务 → Health** 页面，以及后加载的 Services 菜单排序覆盖，用于快速查看路由器健康状态、overlay/存储、RAM、conntrack、uptime 和写入热点。
- **重新整理 LuCI Services/服务菜单。** 服务菜单优先显示 Health、WiFi Clients、WiFi Client History、Traffic Statistics、System Statistics、Temperature、Modem Events、youtubeUnblock 和 AdGuard Home。WiFi Client History 与 System Statistics 现在是 Services 下的直接视图，不再通过 alias 跳回 Status/Statistics。
- **调整 QoSmate 在 Services 菜单中的位置。** QoSmate 现在位于 Modem Events 之后，让观测与调制解调器恢复相关页面排在调优/流量整形工具之前。
- **扩展顶层 About 页面。** 固件现在会在 LuCI 内展示发布标识、OpenWrt 基线、功能分组、相对 stock/vendor 固件的修复、已包含的软件包族、支持链接和致谢。
- **统一自定义 LuCI 应用样式。** About、Health、Temperature、Modem Events、WiFi Clients、Traffic Statistics 和 MLO 现在共用 ZBT 主题 CSS，卡片、表格、按钮、筛选控件和 About 致谢间距更加一致。
- **改进 Traffic Statistics 界面细节。** 日期筛选和表格操作按钮现在使用共享 ZBT 主题，不再沿用旧的蓝色/紫色按钮样式；表格行高和操作按钮对齐也已统一。
- **增强 BusyBox 部署兼容性。** 固件包含小型 `/usr/bin/install` 兼容 shim，setup 脚本通过 `cp`/`chmod` 避免依赖 GNU `install`，并选中 `git`/`git-http` 方便运行期和开发调试。
- **移除重复的 System About alias。** About 现在只保留顶层 **About** 页面 `/admin/about`。
- **内置 ZBT 调制解调器事件历史。** 固件自带 `luci-app-zbt-modem-events`、`/usr/sbin/zbt-modem-events`、cron/tmpfs 事件历史、USB/netifd/看门狗/QModem 事件 hook、明确的 `wwan0` 互联网探测状态，以及 LuCI **服务 → Modem Events** 页面；页面显示 7 天事件卡片、恢复计数，并且只基于 down/recovered 成对事件估算停机时间。
- **减少 Modem Events 开机噪声。** Modem Events 现在会把路由器重启记录为停机边界，在启动宽限期内抑制低层 health 噪声，并让 UI 聚焦互联网 down/recovered/OK、monitor 动作、路由器重启和调制解调器重启事件。
- **温度图表新增避让温度线。** 不同传感器族使用不同阈值：SDR/mmWave 调制解调器传感器 75°C，调制解调器系统传感器 80°C，调制解调器 CPU/DSP/PHY 传感器 85°C，WiFi 传感器 85°C，系统 CPU/SoC 传感器 90°C。悬浮提示和汇总表会显示每个传感器的 limit/headroom。
- **修复 QModem 软重启。** LuCI 手动软重启、QModem 关机软重启和 ZBT 调制解调器看门狗现在统一调用 `/usr/sbin/zbt-modem-soft-reboot`；该 helper 会依次尝试 `sms_tool`、`sms_tool_q`、`tom_modem` 和 QModem AT helper，并返回真实成功/失败状态。板级 uci-default 会在首次启动/sysupgrade 后覆盖安装打过补丁的 QModem 脚本。
- **增强无 SIM 卡场景的调制解调器监控。** QModem monitor 和 ZBT 调制解调器重启守卫现在会查询 `AT+CPIN?`，当调制解调器报告未插入 SIM 卡时跳过重启动作，避免无 SIM 部署中反复 USB/调制解调器复位。
- **新增 QModem monitor 动作冷却时间。** 打补丁后的 monitor 会在路由器启动后的前 5 分钟跳过重启动作，并在每次 monitor 触发调制解调器动作后再次等待 5 分钟，避免开机后立即重启调制解调器，也避免运营商附着期间反复重启。
- **增强 QModem 联网检测。** 固件默认值现在使用直连 IP 的 HTTP/204 探测 `http://142.250.23.94/generate_204`，监控间隔为 30 秒，连续失败阈值为 10 次；monitor 的 curl 路径也加入 `--max-time 15`，降低短暂 DNS/运营商链路抖动误触发调制解调器动作的概率。
- **调整默认 WiFi 信道规划以便合规隔离。** 默认信道现在为 2.4 GHz ch11/EHT20、5 GHz ch149/EHT80、6 GHz ch37/EHT160。在 PH lower-6 GHz 范围内，多 AP 部署可用 EHT160 获得 ch5、ch37、ch69 这类相互分离的 PSC 区块。
- **移除固件侧 WiFi 功率/信道额外限制。** 首次启动保持 `country=PH`，设置 `cell_density=0`，并清理 `txpower`、`min_tx_power`、`channels`、`scan_list`，让 `wireless-regdb` 和驱动暴露 PH 允许的完整信道集合，并自动使用法规允许的最大发射功率。
- **改进 Traffic Statistics 默认值和空状态提示。** Setup 中 Domain tracking 默认启用，同时预设数据库路径、90 天保留、每日清理、90 天 inactive 设备清理、604800 秒 domain cache TTL、Auto DNS backend 和 Info log level。设备/域名视图会在监控或域名跟踪关闭、表未初始化或暂无数据时给出明确提示。
- **修复域名表可见性。** Top Domains 与 Device Domains 不再隐藏小于 1 KiB 的记录，因此任何已记录的域名流量都可以查看。
- **修复 WiFi Clients 递归 iframe。** LuCI app 现在直接渲染生成的 WiFi Clients HTML，并用隔离样式和轮询刷新替代 iframe 嵌套。
- **优化风扇调速策略。** PWM 风扇从 3 档扩展为 7 档 `<0 80 112 144 176 216 255>`；温度记录服务按系统/WiFi/调制解调器最高温度进行分级调速，100% 只保留给更高温场景。旧 3 档固件上的运行期脚本也会在 55-60°C 附近从 100% 降回中档，避免低于 60°C 时长时间满速。
- **Feeds 更新到最新兼容版本。** OpenWrt packages/LuCI/routing/video feeds 固定到当前兼容 head，telephony 保持 25.12 稳定 pin；ImmortalWrt overlay 和 FUjr/QModem 也已刷新。build harness 会在安装 feed 后移除未使用且会触发递归 Kconfig 的 overlay LuCI app。
- **移植 vendored `autocore` 和 `cpufreq`。** 保持已选择的 LuCI 监控/CPU governor 包可在官方 25.12.2 基线上构建，不再依赖旧的 setup-script 目录。

## 验证

- 自定义 LuCI JavaScript 视图通过 `node --check`。
- 重建前已针对本次触及的 LuCI/theme/文档/setup 文件运行 3 轮工程代码审查。
- ZBT base-files 脚本、init 脚本、hotplug 脚本、uci-defaults 和 package 脚本通过 shell 语法检查。
- LuCI menu/ACL JSON 文件通过 `python3 -m json.tool`。
- `./.buildenv/build.sh feeds` 和 `./.buildenv/build.sh config` 完成，ZBT 相关包均被选中。
- 完整 `./.buildenv/build.sh build` 构建成功。
- 已从 squashfs 流式读取重建后的 sysupgrade rootfs，并确认其中包含 QModem monitor 冷却逻辑、直连 IP 的 `30s/10×` monitor 默认值、curl `--max-time 15`、`qmodem.main.zbt_monitor_cooldown=300`、更新后的 EHT160 WiFi 信道默认值、PH WiFi no-clamp 默认值，以及内置的 `luci-app-zbt-health` 和 `luci-app-zbt-modem-events` 包文件。
- 发布 manifest、校验文件和 buildinfo 中没有遗留测试内核包引用。
- 已在在线路由器上验证 Modem Events UI、温度 UI 和 QModem 软重启路径的运行期补丁；AT 口/工具验证只发送了无害的 `AT` 命令，没有触发真实调制解调器重启。

## 校验值

```text
45dfdda0204eb549a1dc127c3ef3ef2ef4c0be1ea3a048fca6925937641e5281  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
ccc242c1a7fb3ab4b2864f7b87654a7d1576aeec90791f5c72ed9b5b95ed7970  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f2f4454deafb186712bf11a153dbb43694f0d6bd3d5c215313d670acff300df1  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
c4898a1a2760b72c6eab640c5bfba9b08c5cf239571212b2011e815be4fa1db0  sha256sums
```

## 已包含

- **平台/板级支持:** 主线 OpenWrt 25.12.2 基线、ZBT-Z8803BE 板级支持、NAND sysupgrade profile、WiFi 7 三频/MLO 默认值、调制解调器 LED 服务，以及 WAN/WWAN 故障切换默认值。
- **LuCI/可观测性:** HTTPS LuCI、Argon 深色主题/配置、软件包管理器、共享 ZBT 自定义应用主题、顶层 About、MLO app、ZBT Health、ZBT 温度监控、ZBT 调制解调器事件历史、WiFi Clients、WiFi history、System Statistics，以及整理后的 Services 菜单顺序。
- **流量、DNS 与 QoS:** wrtbwmon Traffic Statistics 设备/域名跟踪、AdGuard Home 集成、受限 query/statistics 默认值、youtubeUnblock，以及作为主要 QoS/调优界面的 QoSmate。
- **调制解调器与 WAN 韧性:** QModem Next JS 界面、QMI/MBIM/NCM/MHI/USB 调制解调器栈、`sms_tool_q`、`tom_modem`、`quectel-CM-5G-M`、无 SIM 守卫、直连 IP monitor 探测、冷却时间和可靠软重启。
- **存储与 LAN 服务:** WireGuard、DDNS、Samba、Diskman、statistics、autocore、cpufreq、诊断工具、`git`、`git-http`、BusyBox 兼容 `install` 和 CLI 工具。

## 致谢

- [@pttuan](https://github.com/pttuan) —— OpenWrt 主线板级支持 [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053)：DT 原生风扇、GPIO 看门狗、热管理冷却映射、现代 LED 绑定。
- [@sjanulonoks](https://github.com/sjanulonoks) —— 建议加入风扇控制优化，并参与本版本的整体测试，帮助调校和验证这版 ZBT-Z8803BE 固件。
- [FUjr/QModem](https://github.com/FUjr/QModem) —— 本固件采用的 QModem Next 现代 JS 界面；此精确 Z8803BE-T 版本中 SIM1/SIM2 分别接到两个 M.2 调制解调器，因此已禁用 SIM 切换。
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) —— 对原厂 21.02-SNAPSHOT 固件的研究，揭示了失效的 opkg 软件源以及内置的回传通道。
- [OpenWrt mainline](https://openwrt.org) —— 本固件的基础发行版，不依赖联发科 vendor feed。
- [ImmortalWrt](https://github.com/immortalwrt) —— 构建过程中使用的补充软件包与 LuCI 资源。

## 刷机

从现有 OpenWrt 升级：

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

清空配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

恢复模式刷机：

1. 按住 **Reset** 后上电。
2. 打开 `http://192.168.1.1`。
3. 上传 `squashfs-sysupgrade.bin` 镜像。
4. 等待重启，然后使用 `root` / `admin` 登录。
