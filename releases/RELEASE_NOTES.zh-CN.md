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

- **tmpfs 工作文件 + 持久化快照。** 温度采样仍写入 `/var/log/zbt-temperature/readings.csv`（tmpfs），并按固定间隔通过原子操作快照到 `/etc/zbt-temperature/readings.csv`（overlay/flash）。开机后从快照恢复回 tmpfs，因此意外重启后历史数据不再丢失。
- **低 flash 写入量。** 快照默认间隔 `ZBT_TEMPERATURE_PERSIST_INTERVAL=900` 秒（约 96 次/天），使用 `cp` + `sync` + `mv` 保证原子性。
- **正常关机刷盘。** `zbt_temperature` init 脚本在 `stop` 时刷盘，正常重启不丢样本；只有异常崩溃可能丢失最多一个间隔的数据。
- **破坏性清理保留。** 旧 4 列 CSV 兼容仍按计划移除；前端继续按当前 5 列 CSV 格式解析：epoch、group、name、value、unit。
- **LuCI 数据路径不变。** Temperature 页面和 rpcd ACL 仍读取 `/var/log/zbt-temperature/readings.csv`。

### 崩溃与重启取证

- **持久化崩溃日志目录。** 新增 `zbt-crash-forensics`，诊断数据写入 `/etc/zbt-crash-logs/`，可跨重启和重刷保留。
- **Kernel pstore 归档。** 开机时将 `/sys/fs/pstore/*` 复制到按时间命名的 `/etc/zbt-crash-logs/pstore-<epoch>/` 目录，并保留最新 10 份归档。
- **重启分类。** `boot-events.log` 通过 clean-shutdown marker 和 kernel `boot_id` 记录 first、clean、unclean boot，避免服务重启产生假的 boot event。
- **滚动健康快照。** 每分钟 cron 覆盖写入 `last-snapshot.txt`，并保留 `prev-snapshot.txt`，包含 uptime、load、memory、top processes、thermal/hwmon/fan、网卡计数器、dmesg tail 和 logread tail。
- **备份集成。** app-history backup/restore 现在会保留 `/etc/zbt-crash-logs/`，与其他应用历史一起跨重刷恢复。

## 验证

- 固件从 commit `b1d85c6f12` 重新构建，并提取到 `output/mediatek/filogic`。
- staged release assets 已通过 `sha256sum -c sha256sums --ignore-missing`。
- `zbt-temperature-log` 通过 `sh -n`。
- `zbt-crash-forensics`、`zbt_crash_forensics` 和 `49-zbt-crash-forensics` 通过 `sh -n`。
- Temperature LuCI JavaScript 通过 `node --check`。
- Temperature rpcd ACL 通过 JSON 校验。
- 重构建前已执行 engineering code review workflow，未发现 blocker。
- 发布文档更新前源码树通过 `git diff --check`。
- 重构建前已通过 embedded firmware review 和最终 code review。
- 重构建前实机验证显示风扇稳定在 cooling state 2 / PWM 112 附近，没有来回跳档；LuCI/ubus 可读取 tmpfs 温度记录；模拟重启（停止服务 + 清空 tmpfs + 重启服务）成功从持久化快照恢复并继续采样。
- 重构建前实机 crash-forensics smoke test 显示服务已启用，cron 只有一条，pstore 已归档，snapshot 已写入，重复服务重启不会追加重复 boot event。

## 校验值

```text
10a74b09735ad3c82619033b1b23847b44f486a3abbd8a727bdd9c55f3c4a61e  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
add3cdf72e7dc98f86d1fb06b6f775c7c4d4141896231f6546157ba068ab071a  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
ff83037f018fdd52fae2fc2f96dce0cc7331a76ac5f1c4d341a1198334e849ae  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
4605b40e3cdd1f621a03dd5e10bf2b3adeac16bcf8fcadfb9a4629eb782d89ad  sha256sums
19a0a0bc2e43e95a242f16dc77f6645a1b58d48348c4e8d247cf8273daaabdc2  config.buildinfo
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
