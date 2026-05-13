# ZBT-Z8803BE OpenWrt v25.12.2-7-zbt8803be Speedtest 维护版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-7-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 `v25.12.2-6-zbt8803be` 的变化

### Speedtest LuCI 应用

- **仅保留 Speedtest.net 后端。** Speedtest 页面不再显示后端选择，只使用 Speedtest.net 后端。
- **固定国际测速预设。** 新增 PH、KH、SG、MY、US、DE、NL、FR、TH 的精选 Speedtest.net 服务器预设，包含固定 server ID，并保留旧 preset alias 兼容。
- **更可靠的预设执行。** 固定预设会跳过按地理位置偏置的 XML 服务器发现流程；测试流量 URL 会先校验 HTTP/HTTPS scheme；保存国家时使用规范化 country code。
- **持久化应用配置。** LuCI 页面通过 `/usr/sbin/zbt-speedtest-json --config` 读取 `/etc/config/zbt-speedtest`，并在测速后保存所选国家、预设、传输大小和连接数。
- **持久化测速历史。** 完成的测速会写入 `/etc/zbt-speedtest/history.json`，包含时间、国家、预设、服务器、下载/上传 Mbps、ping、字节数和耗时。历史最多保留 100 条，并使用文件锁避免并发写入丢记录。
- **LuCI 历史表格。** Speedtest 页面现在会以表格显示历史测速记录，并在每次测速后刷新。
- **LuCI 兼容性修复。** 移除 JavaScript `.format()` 调用，并修复嵌套 table row 导致显示 `[object HTMLTableRowElement]` 的问题。
- **ACL 与备份覆盖。** rpcd ACL 允许应用读写历史数据库；app-history backup/restore 会保留 `/etc/zbt-speedtest/history.json`。

## 验证

- 固件从 commit `58a983ad76` 重新构建，并提取到 `output/mediatek/filogic`。
- 已修正构建配置 `CONFIG_PACKAGE_luci-app-zbt-speedtest=y`；最终 manifest 包含 `luci-app-zbt-speedtest - 26.133.41786~58a983a`。
- staged release assets 已通过 `sha256sum -c sha256sums --ignore-missing`。
- `zbt-speedtest-json` 通过 Python 语法校验。
- Speedtest LuCI JavaScript 通过 `node --check`。
- Speedtest rpcd ACL 通过 JSON 校验。
- 已执行 engineering code review workflow；修复项包括历史写入加锁，以及历史记录使用当前配置解析 preset label。
- 本地和路由器临时文件测试通过，覆盖 append、自定义 preset label 解析和 clear-history 行为。
- 已在实机 `3fl.lan` 热部署验证，清理 LuCI cache 并重启 `rpcd`/`uhttpd` 后，`/usr/sbin/zbt-speedtest-json --history` 可返回已持久化的 SG Singtel 历史记录。

## 校验值

```text
a3c35330d09649e56e4ad29b9d6dcbabe3ac3983989e35e54a7d6f3fb3889d7a  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
4f9c90aebc44ddd9aa6c2594a4d55ad2fa7855492c2381946902dc4f126e6c90  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
c755428ec8874006d1572f2b0a457ae61092d1907119ac01ea5e9c46ad443e4d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
22cd03fcfd73f645c0be48165b4449e5768fef147908db51dcb8a25db88b98a5  sha256sums
43a7d0d006229a8c60a42915e59c7220623778508f18387be37dc8d79ea15777  config.buildinfo
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
