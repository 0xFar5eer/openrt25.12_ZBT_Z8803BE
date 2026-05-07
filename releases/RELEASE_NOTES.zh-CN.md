# ZBT-Z8803BE OpenWrt v25.12.2-3-zbt8803be 维护版

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
- **QModem 手动重启冷却。** 手动软/硬重启调制解调器后，联网监控会暂停自动重启动作 10 分钟，等待蜂窝链路恢复。
- **降低 wrtbwmon CPU 占用。** NFT 状态增加缓存、锁与限流；关闭 wrtbwmon 会移除 cron 并停止正在运行的任务。

## 验证

- 自定义 shell 脚本通过 `sh -n`。
- 自定义 LuCI JavaScript 视图通过 `node --check`。
- LuCI ACL JSON 通过 `python3 -m json.tool`。
- 已在在线路由器 `3fl.lan` 验证 `/etc/zbt-temperature`、`/etc/zbt-modem-events`、`/etc/wifihistory` 持久化数据已生成。
- 已在 `3fl.lan` 验证 QModem 手动冷却、受保护的重启跳过逻辑，以及 wrtbwmon `nft -f -` 降频效果。
- 固件已从当前发布分支重新构建并提取到 `output/mediatek/filogic`。

## 校验值

```text
9dd4c08b461bd0cc00687fcaf02bfbcf03ce177011d6eb5c99f83ec78e605ea3  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
52be5036bb72275a996247bb956ab5910d65da2e1b86f441cdba7c8a82538037  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
d1657eba3df03621517132b396c5a0bcdbc44d86fe3c0c91f3743140e8108dee  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
bcd424a53c0d140eaa40c15833bb37017606dc4df10c9816ced33f296ce8e382  sha256sums
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
