# ZBT-Z8803BE OpenWrt r34167

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎大家提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **构建版本:** `r34167+2-cfb4b100d1`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本次更新

- **新增：运营商静默丢掉 PDP 上下文时蜂窝链路会自动自愈。** 固件出厂为每个 modem-device 小节预置 `qmodem_monitor` 看门狗：每 15 秒向 `http://www.gstatic.com/generate_204` 发起一次 curl 探测（这是 Android 自身做 captive-portal 检测时用的同一探针，Smart / Globe PH 运营商过滤永远放行），失败阈值 4 次（约 60–80 秒检测窗口），`monitor_action=run_scripts` 派发到新增的 `/usr/sbin/zbt-modem-reboot-guard`。该守门程序只有同时满足两个条件才会下发 `AT+CFUN=1,1`（3GPP 软重启，约 30 秒重新附着）：(a) 路由器 uptime ≥ 5 分钟，确保冷启动拨号序列已经走完；(b) 距上一次重启 ≥ 5 分钟，避免运营商抖动期间连续重启叠加。两个 grace 窗口都可通过 `/etc/config/qmodem` 主小节的 `zbt_reboot_boot_grace`、`zbt_reboot_lockout` 选项覆盖。为什么用 curl 而不是 ping：Smart / Globe PH 会黑洞屏蔽蜂窝 IP 发往大部分公网（包括运营商网关本身、`1.1.1.1` / `8.8.8.8`）的 ICMP，只有 `9.9.9.9` 比较可靠但稳定性不够下放给看门狗。HTTP/204 to gstatic 会跑通 USB → 调制解调器固件 → RAN → GGSN → 互联网 → DNS → TCP → HTTP 整条链路，一旦失败说明数据面真的坏了。为什么不在内核驱动层修：运营商侧黑洞会让调制解调器停留在 `已注册 + L1 + L2 起来 + 拿到 IP + L3 死掉` 的状态，`qmi_wwan` 和 netifd 都看不到 — 只有端到端探针能发现。新增文件：`etc/uci-defaults/45-zbt-qmodem-monitor-enable`、`usr/sbin/zbt-modem-reboot-guard`。
- **修复：多上行链路构建上 qmodem_monitor 的 curl / ping 探测会走错 WAN。** 上游 FUjr/QModem feed 的 `update_netcfg()` 在 `NET_DEV` 解析路径上有三个独立 bug：(1) 把字面量横线 `-`（qmodem 的「无 alias」占位符）当成真实 alias，去查 `network.-.ifname` —— 永远查不到；(2) 只读 legacy 的 `option ifname`，遗漏现代 netifd（21.02+）为新建 wwan 接口写的标准 `option device`；(3) 缺少从 alias-name（人类可读的显示名，比如 `modem1`）回退到 modem-id（比如 `4_1`，qmodem 实际维护的 UCI 小节名）的兜底分支。三处叠加之后，每个全新部署形态下 `NET_DEV` 都是空字符串 —— `curl` 没有 `--interface` 参数，探测就会走系统默认路由，多上行场景下经常落到「另一条」WAN（比如 tether 故障切换部署里 `wwan0` 被监控时却走 `br-wan`）。另一条路径上的任何抖动都会触发对一台健康调制解调器每隔约 6 分钟一次的连环误重启。打过补丁的 `modem_monitor.sh` 以 base-files overlay 形式安装在 `/usr/lib/zbt/qmodem-modem_monitor.sh`，由新增的 `46-zbt-qmodem-monitor-patch` uci-default 在每次启动时与 `/usr/share/qmodem/modem_monitor.sh` 比较（用 `cmp` 做幂等判定），不一致时复制覆盖。可跨包升级、可跨 sysupgrade 复跑。多带一条保险：`30-zbt-z8803be-wan-failover` 现在也会在 `network.4_1` 上写入 `device → ifname` 镜像，兼容尚未跟上 patched monitor 的 r34167 之前的固件。
- **修复：DPI 绕过服务 youtubeUnblock 启用后会直接干掉蜂窝 WWAN 流量。** 用户态守护进程会把 TLS ClientHello 分片，这种包走蜂窝 5G 路径会被运营商中间盒静默丢弃（流被 RST，表现为 TCP 似乎在本地被重置）；S23 USB Tether 这边走 `br-wan` 的路径会在 baseband 内重新 NAT，所以 DPI 绕过在该路径上反而是可用的。重写了 `99a-zbt-youtubeunblock-disable`：(a) 钉住 `all_domains=0`，预填 `sni_domains` 为 `binance.com`、`bnbstatic.com`、`binance.org`（这是 Smart / Globe PH 上唯一观察到的 DPI 劫持；YouTube / Google / Cloudflare 都不受干扰）；(b) 用 `br-wan` 作用域的 nft 模板替掉包自带的薄模板（`oifname != "br-wan" return` 让非 tether 外出路径提前跳出该 chain，`wwan0` 永远不会进队列）。服务本身仍然默认关闭，不主动开启的全新刷机行为一点不变。要启用 DPI 绕过的部署现在可以只在 tether 路径上生效，不会再拖坏蜂窝拨号。
- **修复：蜂窝 WWAN 出厂状态被双重 NAT，导致端口转发与 PMTUD 失效。** qmodem 默认 `donot_nat=0` 会让 Quectel 固件在每次拨号时执行 `AT+QCFG="nat",1`，调制解调器在内部把 `wwan0` 流量隐藏到 `192.168.225.x/24` 假地址后面再做一次 NAT；fw4 wan zone 的伪装规则又会再 NAT 一次，结果是：(a) 在 OpenWrt 上打开的端口转发到不了真正的 WAN，因为调制解调器内部 NAT 表里没有这条记录；(b) 上游回来的 `ICMP frag-needed` 进了调制解调器自己的 NAT 而不是 fw4，PMTUD 直接断掉；(c) `quectel-CM-M` 的 IP 派发把假的 `192.168.225.x` 当作 WAN 地址上报给 netifd。`35-zbt-qmodem-dns-suppress` 现在会对所有 `modem-device` 小节以及 4_1 预创建分支同时写入 `donot_nat=1`，让 `modem_dial.sh` 改发 `AT+QCFG="nat",0`，调制解调器停止内部 NAT，运营商分配的 (CGNAT) IP 直接出现在 `wwan0` 上。已对照 `feeds/qmodem` 源码核实（`modem_dial.sh:153`/`:776`、`network_config.js:342`）。
- **文档化：固件现在向蜂窝 qmodem 小节明确声明了一份 auto-APN 合同。** `35-zbt-qmodem-dns-suppress` 的头部注释被重写，明确列出我们设置的字段（do_not_add_dns=1、donot_nat=1）以及刻意保留 qmodem 默认的字段（apn 不写、force_set_apn=0、pdp_type=ipv4v6、pre_dial_at_cmds 不写）。在菲律宾运营商（Smart、Globe）上，让 `quectel-CM-M` 自动检测运营商认可的 APN 是 QMI-WDS PDN 设置唯一能跑通的配置；任何客户端强制写 APN 都会触发 Quectel RM551E 固件上的 `QMUXError=0xe`（`PDN_REQUEST_REJECTED`）拨号循环。setup 脚本仍然可以在运行期覆盖（如有部署需要），但固件出厂默认现在是「auto-everything」。
- **修复：全新 `sysupgrade -n` 后 DNS 不可用，但原始 IP 路由仍然正常。** r34158 的 DNS 中立默认让 `wan` 上的 `udhcpc` 在 uci-defaults 生效之前就把运营商推送的 DNS 写进 `/tmp/resolv.conf.d/resolv.conf.auto`。dnsmasq 随后会在运营商 DNS 与任何预置后备之间轮询。在菲律宾 Globe / Smart / Smart Bro 网络上，运营商 DNS 瞬间的 NXDOMAIN 就会导致路由器启动后名字解析间歇性失效：`ping 1.0.0.1` 能通，`ping cloudflare.com` 和 `apk update` 都会失败。本次重构了固件的 DNS 合同，保证全新刷机后任意上行链路都能立即解析名字：
  - `90-zbt-z8803be-dns-cache` 设置 `noresolv=1`（dnsmasq 完全忽略 `resolv.conf.auto`）并钉住 `option server` 为 `1.1.1.1` / `1.0.0.1` / `8.8.8.8` / `8.8.4.4`。无论哪个上行链路先起来，都是确定性公共 DNS。
  - 新增 `35-zbt-qmodem-dns-suppress`，预设 `qmodem.4_1.do_not_add_dns=1`。qmodem 拨号路径会给 `quectel-CM-M` 加上 `-D`，阻止它在每次重拨时覆写 `/etc/resolv.conf`。与 qmodem 首次检测路径幂等兼容（使用 `modem-device` 小节类型，进入 qmodem `modem_scan.sh:473` IF 分支后完整保留我们的 flag）。
  - `30-zbt-z8803be-wan-failover` 继续在 `wan` / `4_1` 上保持 `peerdns=0`，同时预设 `system.zbt_wwan_dns.enabled='0'`，让运营商 DNS 捕获 hotplug 默认禁用。
  - 需要运营商 DNS、AdGuardHome、Pi-hole 或其他解析链的部署，可以在 setup 脚本中覆盖预设的 server 列表（后写优先）——详见 `90-zbt-z8803be-dns-cache` 中的 `DOWNSTREAM OVERRIDE` 注释块。
- **新增：首次刷机后自动出厂重置调制解调器以清理遗留的 PDP / APN 状态。** 新增 `15-zbt-modem-factory-reset-flag` 在全新 sysupgrade 后写入一次性标记文件；`hotplug.d/usb/29-zbt-modem-factory-reset` 在首次 USB 检测时触发，等待 AT 口最多 20 秒，将 PDP 上下文重置为 auto-APN，持久化设置后用 `AT+CFUN=1,1` 重启调制解调器。可以缓解调制解调器在运营商临时故障期间被刷机后一直卡在半附着 PDP 上下文的棘手问题。
- **加固：qmodem 看门狗 ifup 恢复。** 重构 `usr/sbin/zbt-qmodem-watchdog-loop` 为独立的 procd 托管循环：按名查找防火墙 zone（之前是 @zone[1]，LuCI 插入其他 zone 后会漂移）、在 netifd 状态不同步时重新插入 `network.4_1` proto=none 桩、在 `ifup 4_1` 失败后运行 `network reload` 重试。看门狗现在可以从刷机后的 `wwan0 carrier=1 但拿不到 IP` 状态自愈，无需人工干预。
- **修复：全新刷机后蜂窝故障切换完全不工作。** FUjr/QModem 首次检测到 USB 调制解调器时创建的 `qmodem.4_1` UCI 小节默认 `state='disabled'`，导致 `qmodem_network` 不会启动 `quectel-CM-M`，`wwan0` 拿不到 IP。`hotplug.d/usb/30-zbt-qmodem-autoenable` 检测到 Quectel 调制解调器（idVendor=2c7c）后等待 qmodem 小节创建、翻位为 `state=enabled`、重新创建 `network.4_1` / `4_1v6` proto=none 桩（fw4 需要它们才能把 `wwan0` 绑到 wan 防火墙区域并启用伪装）、重启 `qmodem_network`。WWAN 在首次启动中即可拨号。（与上述出厂重置 hotplug 通过标记文件协调以避免竞态。）

## 校验值

```text
c1f49dbeca4a6e171aaeadae1b4a3978fb6453efed4e7942651be9cd41ab96f6  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
c10faa3a101b24f81ab81ec1d59121918568771fdb1a42b47bb18f9747feffd2  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
bdd8a1214f2f410d7212f9ffe975db6bde0c4cd35984b4171306698c51bc6a20  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## 已包含

- 主线 OpenWrt，不依赖 MediaTek vendor feed。
- WiFi 7 三频，支持 EHT320 和 MLO。
- PH WiFi 频率区域补丁，用于本地完整 6 GHz 测试。
- LuCI HTTPS、Argon 深色主题、中文翻译，**系统 → 关于此构建** 页面包含 releases 地址与联系信息。
- QModem Next JS 界面，内置短信、监控、AT 调试、SIM 切换。
- QMI/MBIM/NCM/MHI/USB 调制解调器栈，包含 `sms_tool_q`。
- 固件默认启用调制解调器 LED 服务和状态轮询。
- 槽位 1 默认上电，槽位 2 默认断电。
- 首次启动即写入 WAN 故障切换默认值：WAN metric `10`，WWAN/QModem metric `20`。
- youtubeUnblock + LuCI 应用用于 SNI 分片式 DPI 绕过（默认关闭；预设启用后对 **所有** SNI 生效）。
- WireGuard、SQM/CAKE、DDNS、Samba、Diskman、statistics、autocore。
- DNS 缓存提升、APK 软件源、shell banner/彩色提示符/常用工具。
- 内置诊断 CLI 工具集：`nohup`、`timeout`、`stdbuf`、`dig`、`host`、`lsof`、`strace`、`watch`、`screen`、`socat`、`arping`，外加 `htop`、`nano`、`mtr`、`tcpdump`、`ethtool`、`iperf3`、`curl`、`ip-full`。

## 已验证

已验证：

- WAN 互联网正常
- WAN 链路断开时 WWAN 备线路由可正常接管
- 重启后故障切换 metric 持久化正常
- WiFi/MLO 正常
- QModem Next 与 SIM 切换功能正常
- 调制解调器 LED 服务正常

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

## 说明

- SFP+ 已包含，但此处未做实体硬件验证。
- 未启用硬件 NAT/offload。
- PH 频率区域补丁仅用于私有/本地测试，请自行确认合规性。
- **本固件特意未包含 Attended Sysupgrade（在线升级）。** 本构建从 GitHub Releases 分发，而非 `downloads.openwrt.org`，所以基于 buildbot 的 Attended Sysupgrade 流程要么无法匹配镜像、要么会推送一个不含本固件包列表的主线 SNAPSHOT 镜像。请从本 Releases 页下载新的 `squashfs-sysupgrade.bin` 后，通过 **LuCI -> 系统 -> 备份/刷写固件** 或 SSH 上的 `sysupgrade <文件>` 升级。

## 反馈与联系

- **Issue / PR:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Telegram:** https://t.me/Far5eer

同样的信息会显示在路由器每次 SSH 登录的 banner 中，以及 LuCI 的 **系统 -> 关于此固件** 页面。

## 致谢

- [@pttuan](https://github.com/pttuan) —— OpenWrt 主线板级支持 [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053)。
- [FUjr/QModem](https://github.com/FUjr/QModem) —— QModem Next UI 与内置 SIM 切换。
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) —— 原厂固件研究。
- [OpenWrt mainline](https://openwrt.org) 与 [ImmortalWrt](https://github.com/immortalwrt) —— 基础发行版与软件源 overlay。
