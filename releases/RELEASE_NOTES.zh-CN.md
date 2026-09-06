# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

`v25.12.021` 是面向 ZBTLink ZBT-Z8803BE 的社区固件版本。

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

可选的 TTL 插件（`luci-app-qmodem-ttlfw4`，**Modem → QModem → TTL**）在出方向改写 TTL，`ttl=65` 用于补偿 modem 自身的 NAT。测试提示：匹配 `iifname "br-lan"` 的规则不影响在路由器本机执行的 ping，所以"改完规则在路由器上 ping"证明不了任何事——请用**局域网客户端**测试。

本版本开始固件会自动判断正确值：

- 新增 `/usr/sbin/zbt-modem-nat-probe`（由新增的 `iface` 热插拔在每次蜂窝 `ifup` 时触发）检查拨号器拿到的地址：`192.0.0.x` / `192.168.225.x` → modem 在 NAT → 自动把 `qmodem_ttl.main.ttl` 提到 **65**；运营商分配的地址 → 保持 **64**。
- 它不会替你启用插件，不会在插件未启用时重启它；如果你手动改过 `ttl`，它会永久停用自己的自动写入（`zbt_auto_ttl=0`）。
- 手动查看权威答案：`sms_tool_q -d /dev/ttyUSB3 at 'AT+QCFG="nat"'`（`1` = modem NAT 开 → 65；`0` = 透明 → 64）。也可以用 `AT+QCFG="nat",0` 彻底关掉 modem NAT，那样 64 就是正确值——但部分模块断电重启后该设置会复位。

### 3. 其他

- 消除了 `zbt-modem-led` 的 "LED sysfs node /sys/class/leds/5g1 missing — stale DTS?" 日志刷屏（删除了遗留的重复处理器；真实节点是 `blue:mobile-1`/`blue:mobile-2`）。
- 清单：280 个软件包，镜像保持约 20.7 MB。唯一新增的包是 `luci-app-qmodem-ttlfw4` 及其中文翻译。

## 验证

- Docker 完整构建成功。
- `sha256sum -c sha256sums --ignore-missing` 全部通过。
- 直接检查了构建出的 rootfs：新探针/热插拔存在且可执行，六个遗留重复文件均不存在，`proto='dhcp'` 已按新值播种，出厂 watchdog init 中无 `procd_add_reload_trigger`。
- NAT 探针的各写入路径用带桩的 `uci`/`ip` 状态做了演练（modem NAT → 65；运营商 `10.x` 地址 → 保持 64；手工改过的 ttl → 自动写入永久关闭；去抖；缺插件包 → 跳过）。
- `tests/check-zbt-firmware.sh` 与 `git diff --check` 通过。
- **尚未做硬件验证**：以上修复都还没有在插着 T-Mobile SIM 的 Z8803BE 上确认。issue #9 的报告者：不刷机、在 **v25.12.020** 上最快的验证方法就是上面提到的两步手动修复（`enable=1`、`ttl=65`、重启 `qmodem_ttl`）。

## 附件

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `0b4c093807e7ab6fb34c23f0b766689c12d7f2ca212655643681468b66dab9cd`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `6254dffe2a51a7d86efde993528466142187598645ecf660f9463b7d89c85b64`
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

## 捐赠
捐赠是对维护和测试工作的支持：

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
