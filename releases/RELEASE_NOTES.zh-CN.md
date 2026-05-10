# ZBT-Z8803BE OpenWrt v25.12.2-5-zbt8803be 维护版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-5-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 `v25.12.2-4-zbt8803be` 的变化

### 固件 / DTS

- **直接使用 DTSI 基础。** ZBT-Z8803BE 现在直接包含 `mt7988a.dtsi`，不再继承 MT7988A reference-board DTS。
- **移除 RFB DTS include 后补回必要板级节点。** 本地 DTS 现在显式包含板级 `chosen` bootargs、`memory@40000000`、Ethernet/MDIO 设置、switch/LAN LED pinctrl、PCIe0/PCIe1/PCIe3、SPI-NAND/Factory NVMEM 分区、USB PHY/controller、SFP over `i2c2`、PWM fan 和 watchdog 等之前从 RFB DTS 继承的节点。
- **CPUFreq regulator 修复。** 恢复 RT5190A PMIC/regulator、`i2c0` pinctrl，以及 CPU/CCI `proc-supply = <&rt5190_buck3>`，使 MT7988A OPP/CPUFreq 正常工作；实机验证现在可见 CPU 频率 `800000 1100000 1500000 1800000`，不再出现 `failed to get proc regulator`。
- **兼容性元数据清理。** 旧的 `zbtlink,zbt-z8803be,mt7988a-nand` 字符串已从 DTS `compatible` 删除，但继续保留在 `SUPPORTED_DEVICES`；同时移除早先的 `DEVICE_COMPAT_VERSION` / `DEVICE_COMPAT_MESSAGE` bump。
- **Label MAC 修复。** `label-mac-device` 现在指向 `&gmac0`，匹配机身/基础 LAN MAC，并已在实机 device-tree alias 中验证。
- **有线 MAC 处理保持稳定。** 经过验证的 DTS 继续为 `gmac0`、`gmac1`、`gmac2` 使用显式 NVMEM cell index `0`；实机验证显示有线 MAC 稳定且没有 random MAC fallback。
- **风扇节点清理。** 从 `pwm-fan` 节点移除未使用的 `#thermal-sensor-cells` 属性。
- **WiFi reset 原因说明。** `wifi-reset-gpios` 保留在 `&pcie3`，并补充说明 MediaTek Gen3 PCIe probe 顺序，以及为什么必须在 `pcie0` 上的 MT7996 endpoint 枚举前先触发 reset。
- **Modem 槽位 GPIO 原因说明。** DTS 已说明为什么主 modem 槽位 `5g1` 默认上电、第二槽位 `5g2` 默认关闭。

### WiFi / sysupgrade 行为

- **保留配置升级时 WiFi 不再被重置。** 板级 WiFi uci-defaults 脚本在检测到已保留的自定义 SSID 后跳过出厂 SSID 重写，因此保留配置的 `sysupgrade` 会保留现有 MLO / IoT / Guest WiFi 配置。
- **保留配置实机验证。** 测试中 `AlegriaWifi`、`AlegriaWifi_IOT1`、`AlegriaWifi_IOT2` 和 `AlegriaWifi_Guest` 配置在保留配置升级后仍然存在。

### Modem 监控

- **无 SIM 卡时监控降噪。** 当 `AT+CPIN?` 返回无 SIM 卡时，QModem monitor 现在会暂停 curl/ping 探测，只记录一次信息级 `Monitor suspended because SIM is missing` 事件；检测到 SIM 卡恢复后再继续正常监控。这样空卡槽不会持续产生 warning/critical 事件，也不会反复尝试触发重启动作。

### 发布元数据 / 文档

- **About/banner 使用静态版本文案。** LuCI About 和 SSH banner 现在使用稳定的 build-channel/base 文案，不再嵌入每个发布版本的 `-N` 后缀，避免以后小版本发布时忘记同步修改 UI/banner。
- **校验值刷新。** README、release notes 和 staged release metadata 现在都指向已实机测试的 sysupgrade 镜像 `36cd47c0579876a24343aaea6bc4f8851007bcb5a57c06632b86bd079cbb0d82`。
- **验证 runbook 刷新。** `docs/TESTING.md` 已更新为修正后的刷机/测试流程、CPUFreq 验证预期、PR review 可追溯链接，以及 v25.12.2-5 最终测试状态。
- **PR comment 可追溯链接。** Release notes 现在将 OpenWrt PR #23053 的每条相关 review comment 映射到本地修复或验证结果。

## PR review 可追溯链接

- **`@hauke`: 直接包含 DTSI。** 已从 `mt7988a-rfb.dts` 改为 `mt7988a.dtsi`，并补回必要板级节点。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213293080>。
- **`@hauke`: 旧 compatible 处理。** 已从 DT `compatible` 移除 `zbtlink,zbt-z8803be,mt7988a-nand`，但继续保留在 `SUPPORTED_DEVICES`。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213257972>。
- **`@hauke`: 风扇 thermal cell。** 已从 `pwm-fan` 节点移除未使用的 `#thermal-sensor-cells`。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213303728>。
- **`@hauke`: label MAC 目标。** 已设置 `label-mac-device = &gmac0`。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213304880>。
- **`@hauke`: WiFi reset 放置位置。** 已说明 MediaTek Gen3 PCIe driver 处理 `wifi-reset-gpios`，且必须保留在先于 `pcie0` probe 的 `&pcie3`。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213261930>、<https://github.com/openwrt/openwrt/pull/23053#discussion_r3213309837>。
- **`@joelinux60`: 有线 MAC cell 和 label MAC。** 继续为 `gmac0` / `gmac1` / `gmac2` 使用显式 NVMEM cell index `0`，并验证没有 random MAC fallback；label MAC 指向 `gmac0`。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3206902888>、<https://github.com/openwrt/openwrt/pull/23053#discussion_r3206909949>、<https://github.com/openwrt/openwrt/pull/23053#discussion_r3206915357>、<https://github.com/openwrt/openwrt/pull/23053#discussion_r3210123646>。
- **`@openwrt-ai`: review 确认和 WiFi reset 说明。** 已确认 DTS cleanup 解决前序反馈，并恢复 `&pcie3` reset 放置的实测原因说明。链接：<https://github.com/openwrt/openwrt/pull/23053#pullrequestreview-4258463777>、<https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206703>。
- **`@openwrt-ai`: modem 槽位供电不对称说明。** DTS 已说明 `5g1` 默认上电、`5g2` 默认关闭的原因。链接：<https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206797>。
- **`@pttuan`: RT5190A / CPUFreq 确认。** 本地 CPUFreq 修复采用恢复后的 RT5190A CPU/CCI `proc-supply` 路径，并与 `@pttuan` 报告的可用频率一致。链接：<https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414098516>、<https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414354486>。
- **本地修复：保留配置 sysupgrade 后 WiFi 被重置。** 根因是本固件的 `70-zbt-z8803be-wifi` uci-defaults 脚本会重写 `/etc/config/wireless`；已改为检测到自定义非 `OpenWrt` SSID 时提前退出。

## 验证

- DTS 清理通过 `git diff --check` 和继承节点静态 review。
- LuCI About JavaScript 通过 `node --check`。
- 固件已从当前发布分支重新构建并提取到 `output/mediatek/filogic`。
- 初版 v25.12.2-5 sysupgrade 固件已以保留配置方式刷入实机路由器；本次 hotfix 镜像在无 SIM 卡 monitor 实机验证后重新构建并刷新发布文件。
- 实机 CPUFreq 验证通过，可用频率为 `800000 1100000 1500000 1800000`。
- 保留配置升级后，`AlegriaWifi`、`AlegriaWifi_IOT1`、`AlegriaWifi_IOT2` 和 `AlegriaWifi_Guest` 配置仍然存在。
- 无 SIM 卡实机验证通过：monitor 现在只记录一次 `Monitor suspended because SIM is missing`，并在无 SIM 卡期间停止重复产生 probe-failure/threshold 事件。

## 校验值

```text
36cd47c0579876a24343aaea6bc4f8851007bcb5a57c06632b86bd079cbb0d82  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
e18e2f4dc7986646939a44dff1cb422dfc0b10420873b45b073e2dd41835c9d8  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
8d340453b2aad72dfd6f2b0d424d90d09b97168c0c70ec6a90722b3c388420b4  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
c345615d0de8341d7e2d9a86ca1ce05213a9d50bf23eaa1f90439b532861b44e  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## 发布文件

上传以下文件：

```text
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
sha256sums
config.buildinfo
feeds.buildinfo
version.buildinfo
RELEASE_NOTES.md
RELEASE_NOTES.zh-CN.md
```

## 刷机

从现有 OpenWrt 升级：

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

清空配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
