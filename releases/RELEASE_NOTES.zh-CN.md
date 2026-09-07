# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

`v25.12.021` 是面向 ZBTLink ZBT-Z8803BE 的社区固件版本。

**附件已原位刷新（2026-09-06）。** 本 tag 下的两个固件二进制已被同一版本的重建镜像替换：第一轮包含下文第 3–5 节的补充修复，第二轮修正了第 3 节所述升级迁移中的 section 匹配守卫（此前该守卫是无效的空操作），第三轮新增了第 7–8 节的修复。如果你在此日期下载过 `v25.12.021`，请重新核对附件列表中的 SHA-256。软件包清单与软件源 tar 包与原始版本字节一致——软件包集合没有任何变化。

## 亮点

本版本修复了 **issue #9**（T-Mobile 美国，Quectel RM551E-GL）报告的"蜂窝网络连接后几秒内断开"的问题。根源是两个相互独立的固件缺陷，外加一个放大器。

### 1. 每个热插拔事件都在重启拨号器

一个改号后遗留的热插拔脚本（`30-zbt-qmodem-autoenable`）与它的替代品 `40-zbt-qmodem-autoenable` **同时**被装进了固件。modem 暴露的每个 USB 设备和每个网络接口都会触发一次 USB `add` 事件，旧脚本无条件重启 `qmodem_network`：每次重启都会停拨、挂断 PDP 上下文再重新拨号。日志中的表现就是 `Stop Dial and Hang` → `Start Dial Now` 循环，`udhcpc` 拿到租约几秒后又主动释放。

- 两个脚本合并为一个幂等处理器：只有 profile 确实处于 disabled 状态时才会重启拨号器。
- 看门狗（`zbt_qmodem_watchdog`）存在自触发死循环：procd reload 触发器监视的 `qmodem`/`network`/`firewall` 正是循环自身提交的配置，导致它不断重启自己、无限重置开机快速轮询阶段。触发器已移除；重新断言按 section 限速，链路健康时直接跳过。
- 挂起的 WWAN 桩配置之前断言 `proto='none'`，而 QModem 对拨 QMI 的 Quectel 自己推导出 `proto='dhcp'`，只要与存储值不一致就会改写并重新 `ifup`（把 udhcpc 从活租约上踢下线）。桩配置现在直接断言 QModem 会写的值。蜂窝 metric 改为固定在 `qmodem.<sec>.metric`——QModem 拨号时真正复制进网络配置的那个输入值。
- 另外删除了五个改号遗留的重复文件（`00-`/`10-zbt-qmi-rawip`、LED 名字仍为旧值 `5g1` 的 `10-zbt-modem-led`、`30-zbt-status-led`、`30-zbt-wwan-dns`、`29-zbt-modem-factory-reset`）；`tests/check-zbt-firmware.sh` 新增断言防止它们再次被打包。

### 2. T-Mobile 掐断会话的原因：modem 仍在做 NAT（TTL 63）

这是"上线约 2 秒后全部断网"症状的直接原因。

固件通过 `donot_nat=1` 要求 modem 做透明 IP 管道。但 **QMI 模式下这个请求从未发出**：AT 命令 `AT+QCFG="nat",0` 只在 NCM/ECM 拨号路径上发送。QMI 拨号器（`quectel-CM-M`）完全不碰 modem 侧 NAT，于是以 QMI 拨号的 RM551E-GL 继续在模块内部路由，并把自身内建 DHCP 服务器分配的地址交给路由器——`192.0.0.2/27`（网关 `192.0.0.1`），而不是 T-Mobile 的地址。

这多消耗一次 TTL 递减：转发流量以 64 离开路由器（不修 TTL 则为 63），到达 T-Mobile 时是 **63**。美国后付费套餐的共享热点检测把"不是 64"视为热点共享，会在附着成功几秒后拆除数据会话。短信和初始附着不受影响——与报告完全吻合。在**路由器上**执行的 `ping` 也会随会话一起死，因为掐断发生在运营商侧，而不是路由器的 NAT/防火墙。

可选的 TTL 插件（`luci-app-qmodem-ttlfw4`，**Modem → QModem → TTL**）在出方向改写 TTL，`ttl=65` 用于补偿 modem 自身的 NAT。只要 modem 是透明 IP 管道——这是通常情况——播种的默认值 `64` 就是正确值：`wwan0` 上拿到运营商分配的地址（包括 CGNAT `10.x`）时，运营商看到的就是 `64`。只有模块仍在做 NAT 时才需要 `65`，其特征是模块自己分配的地址（`192.0.0.x`、`192.168.225.x`、`10.168.x`）。测试提示：插件的规则匹配 `iifname "br-lan"`，固件常驻规则匹配 `oifname "wwan0"`，两者都不影响在路由器本机执行的 ping，所以"改完规则在路由器上 ping"证明不了任何事——请用**局域网客户端**测试。

本版本开始固件会自动判断正确值：

- 新增 `/usr/sbin/zbt-modem-nat-probe`（由新增的 `iface` 热插拔在每次蜂窝 `ifup` 时触发）检查拨号器拿到的地址：`192.0.0.x` / `192.168.225.x` / `10.168.x` → modem 在 NAT → 自动把 `qmodem_ttl.main.ttl` 提到 **65**；运营商分配的地址 → 保持 **64**。
- 它不会替你启用插件，不会在插件未启用时重启它；如果你手动改过 `ttl`，它会永久停用自己的自动写入（`zbt_auto_ttl=0`）。
- 常驻的 TTL-64 nft 规则（`/etc/nftables.d/99-tether-ttl.nft`，由 `36-zbt-z8803be-wan-speed-mode` 播种）现在只在文件缺失时写入，手动改过的值（比如刻意的 65）在重刷后仍然保留，不会被每次开机重置回 64。
- 手动查看权威答案：`sms_tool_q -d /dev/ttyUSB3 at 'AT+QCFG="nat"'`（`1` = modem NAT 开 → 65；`0` = 透明 → 64）。也可以用 `AT+QCFG="nat",0` 彻底关掉 modem NAT，那样 64 就是正确值——但部分模块断电重启后该设置会复位。

### 3. 第一个 modem 槽位在每次开机几秒后断电（本次刷新新增）

设备树在冷启动时给 5G1 M.2 槽位上电（`gpio-export,output = <1>`），但固件的 board 配置给对应的 `gpio_switch` 用户态开关播种了默认值 `0`。内核在探测时把引脚拉高、modem 完成枚举——然后每次开机几秒后，`gpio_switch`（启动顺序 94）把那个 `0` 写回引脚，在枚举之后切断模块供电。这就是反复出现的"重启后 modem 消失"报告。两条恢复路径都帮不上忙：自动启用热插拔只在 USB 事件时触发，看门狗只处理 USB 设备路径仍然存在的槽位——而刚被断电的槽位已经没有这个路径了。

- `board.d/03_gpio_switches` 现在播种 `5g1=1`、`5g2=0`、`sim1=1`（SIM1 接通 mux），与 DTS 及真实的开机硬件状态一致。
- 升级会保留旧的 `value=0` 配置，因此 `99-zbt-z8803be-qmodem-autostart` 在首次开机（先于 `S94gpio_switch`）执行一次性迁移：把持久化的 `0` 提回 `1` 并记录 `zbt_gpio_default` 标记。此后固件绝不再碰这个开关——主动关闭 5G1 的用户的选择会一直保留。
- 第二轮刷新修复：迁移的第一版用人类可读的标签（`name`，"Power 5G1 modem slot"）去匹配 section 而不是用 section ID，比较永远不成立，升级后的系统上迁移静默失效——这正是第一次刷新刷机后暴露的症状（升级后 modem 断电）。现在改为按 section ID 或 `gpio_pin` 匹配，且写入不再内嵌 shell 引号（uci 会原样存储 `=` 之后的文本）。

### 4. WAN 故障切换默认值不再覆盖用户配置（本次刷新新增）

更早的版本每次开机都删除并重建 `network.wan` / `wan6` / `wan_sfp` / `wan_sfp6`，并把所有上行强制追加进出厂 `wan` 防火墙区域，破坏用户的自定义配置（静态 WAN 地址、被禁用的 `wan6`、自定义端口-区域布局）。

`32-zbt-z8803be-wan-failover` 现在是"缺失才创建"：

- 只有完全匹配出厂形态（一个横跨 `eth1 eth2` 的 `wan` section）时才拆分为按端口独立的 section，让每个口有自己的路由 metric（SFP `9`、RJ45 WAN `10`、蜂窝 `200`）。
- 缺失的 section 按约定默认值创建；已存在的 section 只在 `metric` / `peerdns` / `defaultroute` 未设置时才补齐。
- 防火墙区域成员只对脚本自己创建的 section 追加；WWAN 桩（`4_1` / `4_1v6`）只有在没有任何区域认领时才追加。
- 确定性 DNS 策略不变：有线上行 `peerdns=0`，运营商 DNS 捕获热插拔仍然默认禁用（`system.zbt_wwan_dns.enabled=0`）。

### 5. 删除二十个过时的 uci-default 脚本（本次刷新新增）

对 `etc/uci-defaults/` 的审计发现二十个脚本：或是改号后的重复品，或是配置本构建已不再打包的软件包，或是启用本构建刻意默认关闭的功能。全部删除，并且 `tests/check-zbt-firmware.sh` 对每个都加了 `absent` 断言防止再次被打包：`10-zbt-apk-feeds`、`15-zbt-modem-factory-reset-flag`、`30-zbt-z8803be-wan-failover`、`32-zbt-z8803be-wan-speed-mode`、`35-zbt-qmodem-dns-suppress`、`38-zbt-throughput-tuning`、`40-zbt-qmodem-watchdog-enable`、`44-zbt-qmodem-watchdog-disable`、`45-zbt-qmodem-monitor-enable`、`46-zbt-qmodem-monitor-patch`、`47-zbt-persistent-app-stats`、`47-zbt-qmodem-soft-reboot-patch`、`50-zbt-sms-tool-compat`、`60-zbt-leds-cleanup`、`70-zbt-z8803be-wifi`、`76-zbt-z8803be-admin-password`、`80-zbt-z8803be-dns-cache`、`84-zbt-luci-js-compat`、`99-zbt-z8803be-services`、`99a-zbt-youtubeunblock-disable`。

### 6. 其他

- 消除了 `zbt-modem-led` 的 "LED sysfs node /sys/class/leds/5g1 missing — stale DTS?" 日志刷屏（删除了遗留的重复处理器；真实节点是 `blue:mobile-1`/`blue:mobile-2`）。
- 清单：280 个软件包，镜像保持约 20.7 MB。唯一新增的包是 `luci-app-qmodem-ttlfw4` 及其中文翻译。

### 7. 常驻 TTL 规则现在跟随探针自动调整（第三轮刷新新增）

`zbt-modem-nat-probe` 此前已经能识别出真正要紧的那一种情况——以 QMI 拨号、仍在自己内建 NAT 后面路由的 Quectel——但它只调整 `qmodem_ttl.main.ttl`，也就是**可选**插件的值。插件默认关闭，常驻的 `99-tether-ttl.nft` 规则仍是 64，于是 module-NAT 用户开箱即被运营商掐断：转发流量以 63 到达运营商，客户端一连上会话就死，而没有任何局域网设备时链路看起来完全正常——正是"没设备连接时能撑更久，一连上设备约 10 秒后断线"的特征。

现在每次蜂窝 ifup 时，探针会把常驻规则的 `ip ttl set` / `ip6 hoplimit set` 值在两个固件托管状态之间改写（64 = 透明 modem，65 = module NAT），并且只在值真正变化时重载防火墙。文件中出现其他任何值都视为用户手工修改，固件绝不改写；整个行为也受同一个 `zbt_auto_ttl=0` 退避开关控制（手动改过插件值即触发）。

与此特征吻合的现场报告（RM551E-GL，"能撑几分钟 / 330 Mbps 测速后掉线"）可能就是运营商掐 TTL 的 module-NAT 场景；本次刷新让正确值自动生效，而不再要求用户手动启用插件并改值。25 Mbps 与 330 Mbps 的差异属于小区/射频波动，不是固件路径。

### 8. LAN 不再通告 ULA（第三轮刷新新增）

蜂窝 QMI 数据呼叫不携带 DHCPv6 前缀委派，纯蜂窝上联时路由器没有可委派的全局 IPv6 前缀——但出厂随机 ULA 前缀仍在 LAN 上通告，dnsmasq 也继续应答 AAAA 查询。双栈客户端随后用 DNS 返回的全局目的地址配上走不通的 ULA 源路径，页面资源加载停滞直到客户端回退定时器触发："页面加载不完整"。新增的 `37-zbt-z8803be-no-ula` 默认脚本按每次刷机一次（带标记守卫；刻意重新添加 ULA 的用户设置会保留）删除 `network.globals.ula_prefix`。有线 WAN 拿到委派前缀时仍正常通告，委派存在时 IPv6 自动恢复。

## 验证

- Docker 完整重建成功；刷新后的全部附件 `sha256sum -c sha256sums --ignore-missing` 通过。
- 在构建卷内直接检查了暂存的 rootfs：二十个被删脚本全部不存在，改号后的替代版本齐全（`32-`/`36-`/`40-`/`48-`/`54-`/`56-`/`64-`/`68-`/`72-`/`80-`/`82-`/`86-`/`90-`/`99-`），`board.d/03_gpio_switches` 播种 `5g1` 默认值 `1`，`99-zbt-z8803be-qmodem-autostart` 内含 gpio 迁移逻辑。
- `tests/check-zbt-firmware.sh`——本轮扩充了过时文件断言以及 GPIO/故障切换/nft 不变量——与 `git diff --check` 通过。
- NAT 探针的各写入路径用带桩的 `uci`/`ip` 状态做了演练（modem NAT → 65；运营商 `10.x` 地址 → 保持 64；手工改过的 ttl → 自动写入永久关闭；去抖；缺插件包 → 跳过）。探针与看门狗脚本本次刷新只有注释改动，行为不变。
- **已在实体 Z8803BE 上完成硬件验证（2026-09-06）**：第一轮刷新在保留配置的情况下刷入实体机；升级保留了持久化的 `gpio_switch` `5g1` `value=0`，复现了 modem 断电症状，正是它暴露了上文的迁移空操作。随后在板子上直接运行修正后的迁移脚本：按 section ID 匹配、把 `value=0` 迁移为 `1` 并写入干净的 `zbt_gpio_default=1` 标记（`sh -x` 全程跟踪）。modem 重新枚举；经一次射频重附着（`AT+CFUN=0/1`——运营商 MME 仍持有断电前的会话，用 `call_end_reason_verbose 210` 拒绝数据呼叫）后，蜂窝上行、DNS 与 LAN 转发端到端恢复，重写后的 WAN 故障切换区域布局完好。
- 原 v25.12.021 构建已验证的 issue #9 修复不受影响、原样保留；旧版本的 issue #9 报告者仍可按上文的两步手动修复（`enable=1`、`ttl=65`、重启 `qmodem_ttl`）在不刷机的情况下验证。

## 附件

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `71ac7859719944fd95e2902d0b0256d247b918520d107e29f8fa83bbe6e8cafc`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `830dda1a409ecfc807c517836e9b451944c696acb00f88dc5edf668b001e3fe9`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `4a4cf6dbc0688f858a092ea0a0d7a79e3d27ce5cb840888df927bbea37e52a5f`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `ad0a299a4249c5ed426979b0b0d070be0ef7f7bb738067895c60893e37938172`
- `sha256sums`、`config.buildinfo`、`feeds.buildinfo`、`version.buildinfo`

## 升级
保留配置：

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

全新配置：

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

升级后，如果你之前手动启用过 TTL 插件并设了 `ttl=64`，请保持该值不动——只有当它仍是播种值 64 或探针自己写入的最后一个值时，探针才会把它提到 65。

保留配置升级时：升级后的首次开机，一次性迁移会把持久化的 `gpio_switch` `5g1` 值 `0` 提为 `1`（硬件本应一直保持的默认值）。如果你是主动在 LuCI 里关掉第一个 modem 槽位的，请在这次开机后重新关一次——此后固件绝不再碰这个开关。

## 捐赠
捐赠是对维护和测试工作的支持：

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
