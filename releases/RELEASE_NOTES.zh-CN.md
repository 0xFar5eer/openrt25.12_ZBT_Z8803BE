# ZBT-Z8803BE OpenWrt v25.12.2-6-zbt8803be 风扇 / 温度维护版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-6-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 `v25.12.2-5-zbt8803be` 的变化

### 风扇与温控策略

- **更安静的风扇曲线。** 用户态风扇控制从原来的 raw cubic PWM 写入改为离散 `pwm-fan` cooling state，并与 DTS 中的 `cooling-levels = <0 80 112 144 176 216 255>` 对齐。
- **加入迟滞避免来回跳档。** 风扇在 55/65/70/75/80/85 C 升档，只在低于 48/58/66/72/76/80 C 时降档，避免温度贴近阈值时频繁变速。
- **内核级温控兜底。** 新增 85 C 的 CPU thermal `active-max` trip，并映射到风扇 cooling level 6；即使用户态采样或 cron 没有运行，内核仍可强制风扇满速。
- **CPU thermal trip 调整。** CPU 温控阈值已与更安静的策略对齐：silent 45 C、low 55 C、high 75 C、max 85 C；critical 100 C 保持不变。
- **修复 stale PWM。** 当 `cur_state` 已经等于目标档位但 `pwm1` 暴露值仍然陈旧时，logger 会重新应用 thermal cooling state，而不是直接写 raw PWM。

### 温度记录 / LuCI

- **只写 tmpfs。** 温度历史现在写入 `/var/log/zbt-temperature/readings.csv`，不再写入 `/etc/zbt-temperature/readings.csv`，避免持续写入 flash。
- **破坏性清理。** 已按计划移除旧 `/etc/zbt-temperature` 迁移 / fallback，以及旧 4 列 CSV 兼容逻辑。
- **LuCI 数据路径修复。** Temperature 页面和 rpcd ACL 现在读取 `/var/log/zbt-temperature/readings.csv`；前端按当前 5 列 CSV 格式解析：epoch、group、name、value、unit。

## 验证

- 固件从 commit `f58ee50c35` 重新构建，并提取到 `output/mediatek/filogic`。
- staged release assets 已通过 `sha256sum -c sha256sums --ignore-missing`。
- `zbt-temperature-log` 通过 `sh -n`。
- Temperature LuCI JavaScript 通过 `node --check`。
- Temperature rpcd ACL 通过 JSON 校验。
- 发布文档更新前源码树通过 `git diff --check`。
- 重构建前已通过 embedded firmware review 和最终 code review。
- 重构建前实机验证显示风扇稳定在 cooling state 2 / PWM 112 附近，没有来回跳档；LuCI/ubus 可读取 tmpfs 温度记录。

## 校验值

```text
373420c401352f4890c4480de24d333174f8decdae5d3631d58e91fc0ffeed0b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
77cb8e7a2c7840170d35bfbdf9669d2e6caa7397ea43295899bd57f6d294ff8f  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
2d9410ca9a1d15617fe715256e67a0d5e2a365a2ff1f132f9bfcbc6d0c7dbdb8  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
b9847815647e18df517aea99f33681a179f1110077ea44acf8569856e5a14066  sha256sums
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

从现有 OpenWrt 升级并保留设置：

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

清空配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
