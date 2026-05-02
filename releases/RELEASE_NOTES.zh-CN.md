# ZBT-Z8803BE OpenWrt 25.12.2 稳定版移植

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-1-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **ZBT 源码提交:** `af51d54e00`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本次更新

- **切换到官方 OpenWrt `v25.12.2`。** 当前分支以稳定标签为干净基线，再叠加 ZBT-Z8803BE 板级支持和固件定制；内核使用 OpenWrt 25.12.2 自带的稳定 `6.12.74`。
- **移植 ZBT-Z8803BE 板级支持。** 包含 DTS/镜像 profile、LED/网络/GPIO switch 配置、NAND 升级支持、base-files overlay、调制解调器 LED 服务、QModem 默认值、WAN/WWAN metric 默认值、APK 软件源、LuCI 默认值以及 shell/banner 默认项。
- **内置 ZBT 温度监控和风扇策略。** 固件自带 `luci-app-zbt-temperature`、`/usr/sbin/zbt-temperature-log`、cron/tmpfs 历史记录、CPU/WiFi/调制解调器/风扇采样，以及之前优化过的用户态风扇调速逻辑。
- **内置 ZBT 调制解调器事件历史。** 固件自带 `luci-app-zbt-modem-events`、`/usr/sbin/zbt-modem-events`、cron/tmpfs 事件历史、USB/netifd/看门狗/QModem 事件 hook、明确的 `wwan0` 互联网探测状态，以及 LuCI **服务 → Modem Events** 页面；页面显示 7 天事件卡片、恢复计数，并且只基于 down/recovered 成对事件估算停机时间。
- **温度图表新增避让温度线。** 不同传感器族使用不同阈值：SDR/mmWave 调制解调器传感器 75°C，调制解调器系统传感器 80°C，调制解调器 CPU/DSP/PHY 传感器 85°C，WiFi 传感器 85°C，系统 CPU/SoC 传感器 90°C。悬浮提示和汇总表会显示每个传感器的 limit/headroom。
- **修复 QModem 软重启。** LuCI 手动软重启、QModem 关机软重启和 ZBT 调制解调器看门狗现在统一调用 `/usr/sbin/zbt-modem-soft-reboot`；该 helper 会依次尝试 `sms_tool`、`sms_tool_q`、`tom_modem` 和 QModem AT helper，并返回真实成功/失败状态。板级 uci-default 会在首次启动/sysupgrade 后覆盖安装打过补丁的 QModem 脚本。
- **增强无 SIM 卡场景的调制解调器监控。** QModem monitor 和 ZBT 调制解调器重启守卫现在会查询 `AT+CPIN?`，当调制解调器报告未插入 SIM 卡时跳过重启动作，避免无 SIM 部署中反复 USB/调制解调器复位。
- **新增 QModem monitor 动作冷却时间。** 打补丁后的 monitor 会在路由器启动后的前 5 分钟跳过重启动作，并在每次 monitor 触发调制解调器动作后再次等待 5 分钟，避免开机后立即重启调制解调器，也避免运营商附着期间反复重启。
- **增强 QModem 联网检测。** 固件默认值现在使用直连 IP 的 HTTP/204 探测 `http://142.250.23.94/generate_204`，监控间隔为 30 秒，连续失败阈值为 10 次；monitor 的 curl 路径也加入 `--max-time 15`，降低短暂 DNS/运营商链路抖动误触发调制解调器动作的概率。
- **调整默认 WiFi 信道规划以便合规隔离。** 默认信道现在为 2.4 GHz ch11/EHT20、5 GHz ch149/EHT80、6 GHz ch37/EHT160。在 PH lower-6 GHz 范围内，多 AP 部署可用 EHT160 获得 ch5、ch37、ch69 这类相互分离的 PSC 区块。
- **移除固件侧 WiFi 功率/信道额外限制。** 首次启动保持 `country=PH`，设置 `cell_density=0`，并清理 `txpower`、`min_tx_power`、`channels`、`scan_list`，让 `wireless-regdb` 和驱动暴露 PH 允许的完整信道集合，并自动使用法规允许的最大发射功率。
- **优化风扇调速策略。** PWM 风扇从 3 档扩展为 7 档 `<0 80 112 144 176 216 255>`；温度记录服务按系统/WiFi/调制解调器最高温度进行分级调速，100% 只保留给更高温场景。旧 3 档固件上的运行期脚本也会在 55-60°C 附近从 100% 降回中档，避免低于 60°C 时长时间满速。
- **Feeds 更新到最新兼容版本。** OpenWrt packages/LuCI/routing/video feeds 固定到当前兼容 head，telephony 保持 25.12 稳定 pin；ImmortalWrt overlay 和 FUjr/QModem 也已刷新。build harness 会在安装 feed 后移除未使用且会触发递归 Kconfig 的 overlay LuCI app。
- **移植 vendored `autocore` 和 `cpufreq`。** 保持已选择的 LuCI 监控/CPU governor 包可在官方 25.12.2 基线上构建，不再依赖旧的 setup-script 目录。

## 验证

- 自定义 LuCI JavaScript 视图通过 `node --check`。
- ZBT base-files 脚本、init 脚本、hotplug 脚本、uci-defaults 和 package 脚本通过 shell 语法检查。
- LuCI menu/ACL JSON 文件通过 `python3 -m json.tool`。
- `./.buildenv/build.sh feeds` 和 `./.buildenv/build.sh config` 完成，ZBT 相关包均被选中。
- 完整 `./.buildenv/build.sh build` 构建成功。
- 已从 squashfs 流式读取重建后的 sysupgrade rootfs，并确认其中包含 QModem monitor 冷却逻辑、直连 IP 的 `30s/10×` monitor 默认值、curl `--max-time 15`、`qmodem.main.zbt_monitor_cooldown=300`、更新后的 EHT160 WiFi 信道默认值、PH WiFi no-clamp 默认值，以及内置的 `luci-app-zbt-modem-events` 包文件和服务启动链接。
- 发布 manifest、校验文件和 buildinfo 中没有遗留测试内核包引用。
- 已在在线路由器上验证 Modem Events UI、温度 UI 和 QModem 软重启路径的运行期补丁；AT 口/工具验证只发送了无害的 `AT` 命令，没有触发真实调制解调器重启。

## 校验值

```text
7920ca111cd83f09b84613ff204237887dd6e801175f8ea37421b9783ea1760b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
8574017bbdfd41ab4f52eec40645dab95e3dc9502056e7dd1197f85a242b9e83  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f41ebb5fa5de5e6b2d890b482f2c9e0cf8e65dbe1423521eb265f319c806c0d0  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
ee41d729ac47cc419880e2347792eb5c42fbb201485431a9d7e284d69bc83f80  sha256sums
```

## 已包含

- 主线 OpenWrt 25.12.2 基线，不依赖 MediaTek vendor feed。
- WiFi 7 三频，支持 MLO 和 EHT320 能力；默认 6 GHz 使用 EHT160，便于多 AP 场景下更安全地隔离。
- LuCI HTTPS、Argon 深色主题/配置、软件包管理器、**系统 → 关于此构建**、MLO app、ZBT 温度监控和 ZBT 调制解调器事件历史。
- QModem Next JS 界面，包含 SMS、Monitor、AT Debug、SIM Switch、看门狗默认值和可靠软重启。
- QMI/MBIM/NCM/MHI/USB 调制解调器栈，包含 `sms_tool_q`、`tom_modem` 和 `quectel-CM-5G-M`。
- 固件默认启用调制解调器 LED 服务和状态轮询。
- 首次启动 WAN 故障切换默认值：WAN metric `10`，WWAN/QModem metric `20`。
- youtubeUnblock + LuCI 应用用于 SNI 分片式 DPI 绕过，默认关闭，并由固件默认值限定作用范围。
- WireGuard、SQM/CAKE、DDNS、Samba、Diskman、statistics、autocore、cpufreq、WiFi history 和诊断 CLI 工具。

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
