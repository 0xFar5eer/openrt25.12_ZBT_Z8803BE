# ZBT-Z8803BE OpenWrt 25.12.2 维护版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-3-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 `v25.12.2-2-zbt8803be` 的变化

- **重启后保留应用统计。** Temperature、Modem Events、WiFi Client History 改为写入 `/etc/...` 下的持久化、有界数据，不再依赖易丢失的 `/var`/`/tmp`。
- **轮转而不是清空。** Temperature 与 Modem Events 保留 7 天；WiFi Client History 清理超过 90 天未出现的客户端。
- **安全迁移。** 首次运行会把当前 `/var/log/zbt-*` 和 `/var/lib/wifihistory` 数据复制到新的持久化目录。
- **QModem 硬重启恢复。** 联网监控每 10 秒探测一次，连续 6 次失败后走带保护的 GPIO 调制解调器断电重启路径。

## 验证

- 自定义 shell 脚本通过 `sh -n`。
- 自定义 LuCI JavaScript 视图通过 `node --check`。
- LuCI ACL JSON 通过 `python3 -m json.tool`。
- 已在在线路由器 `3fl.lan` 验证 `/etc/zbt-temperature`、`/etc/zbt-modem-events`、`/etc/wifihistory` 持久化数据已生成。
- 固件已从当前发布分支重新构建并提取到 `output/mediatek/filogic`。

## 校验值

```text
TBD  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
TBD  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
TBD  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
TBD  sha256sums
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
