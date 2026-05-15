![OpenWrt logo](include/logo.png)

# OpenWrt main for ZBTLink ZBT-Z8803BE

[English](README.md) | [中文](README.zh-CN.md)

> **Community build.** This firmware is maintained by a single contributor outside of any vendor or the OpenWrt Project. Expect rough edges. Bug reports and pull requests are very welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **OpenWrt base:** current OpenWrt `main`
- **Kernel:** MediaTek target `6.18`
- **Target:** `mediatek/filogic`
- **Device:** MediaTek MT7988A / Filogic 880 + MT7996-family tri-band WiFi 7
- **Release tag:** pending main/6.18 test build

## Download

Use the latest GitHub release assets after a release build is published:

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `RELEASE_NOTES.md`
- `RELEASE_NOTES.zh-CN.md`

## Checksums

Pending rebuild. Refresh this section from `releases/sha256sums` after `./.buildenv/build.sh extract`.

## Included features

- **Mainline OpenWrt main base:** no MediaTek vendor feed required.
- **WiFi 7 tri-band:** 2.4 GHz, 5 GHz, 6 GHz, EHT320, WPA3, MLO-capable.
- **PH WiFi defaults:** country `PH`, full PH-allowed channel set, no firmware txpower/channel clamps, and automatic regulatory max power.
- **LuCI:** HTTPS, Argon dark theme, Chinese translations, package manager, curated Services menu ordering, and shared ZBT styling across custom firmware apps.
- **Custom LuCI apps:** About, Health, Temperature, Modem Events, Speedtest, WiFi Clients, Traffic Statistics, and MLO tooling.
- **Traffic and QoS tooling:** wrtbwmon device/domain traffic views and QoSmate available for manual tuning.
- **QModem Next:** modern JS modem UI with built-in SMS, Monitor, AT Debug, and modem controls.
- **Modem stack:** QMI, MBIM, NCM, MHI, USB serial, QModem, `sms_tool_q`.
- **Z8803BE-T SIM wiring note:** on this exact model/variant, SIM1 is wired to modem1 and SIM2 is wired to modem2; one module cannot control both SIM cards, so SIM switching is not supported.
- **Public WAN-only defaults:** wired WAN is primary, modem rails default off, cellular is dormant with metric `200` and no default route, QoSmate is disabled by default, and firewall flow offload is enabled.
- **No built-in crash-forensics package:** detailed reboot/crash investigation tooling is intentionally installed only by private setup scripts after flashing.
- **Storage:** USB 3.0, ext4, vfat, exfat, ntfs3, Samba 4, SFTP.
- **Monitoring:** router health, autocore, cpufreq, collectd/statistics, WiFi clients/history, temperature history, and modem event history.
- **Shell defaults:** banner, color prompt, useful aliases/tools, `git`, `git-http`, and a BusyBox-compatible `install` shim.
- **Package feeds:** OpenWrt + ImmortalWrt overlay feeds configured for APK.

## Private setup-only crash forensics

The public firmware image is kept generalized for normal users. It does **not** include `zbt-crash-forensics` or enable scheduled reboot tooling.

For private investigation on a flashed router, use the setup repository phase:

```sh
/Users/numwan/Documents/Remix/bitbucket/wrt/setup/015-crash-forensics.sh root@3fl.lan
```

That phase installs the enhanced flight recorder, per-minute snapshots, reboot context archives, and `/etc/sysupgrade.conf` keep entries on the target router.

## Install

### Existing OpenWrt

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

For a clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

### U-Boot recovery

1. Hold **Reset** while powering on until recovery starts.
2. Open `http://192.168.1.1`.
3. Upload the `squashfs-sysupgrade.bin` image.
4. Wait for reboot.

Default login after first boot:

- **IP:** `192.168.1.1`
- **User:** `root`
- **Password:** `admin`

Change the password immediately.

## Build

Use the included Docker build harness:

```sh
./.buildenv/build.sh init
./.buildenv/build.sh feeds
./.buildenv/build.sh config
./.buildenv/build.sh download
./.buildenv/build.sh build
./.buildenv/build.sh extract
```

Output image:

```text
output/mediatek/filogic/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

## Notes

- SFP+ is included but not physically verified here.
- This branch is based on OpenWrt main and the MediaTek 6.18 target kernel.
- PH WiFi defaults follow `wireless-regdb`; confirm local compliance before changing country, channels, or antenna gain.

## Support / contact

- **Issues / PRs:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Telegram:** https://t.me/Far5eer

PRs and issue reports are very welcome. The same info is also surfaced on the router itself in the SSH banner and at **LuCI -> System -> About this build**.

## Credits

- [@pttuan](https://github.com/pttuan) — upstream OpenWrt board port via [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053): DT-native fan, GPIO watchdog, thermal cooling maps, modern LED bindings.
- [@sjanulonoks](https://github.com/sjanulonoks) — fan-control suggestion and general release testing that helped tune and validate this ZBT-Z8803BE build.
- [FUjr/QModem](https://github.com/FUjr/QModem) — QModem Next modern JS UI shipped with this build; SIM switching is disabled for this exact Z8803BE-T variant because SIM1/SIM2 are wired to separate M.2 modems.
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) — vendor firmware research that documented the dead opkg feeds and phone-home tunnel in stock 21.02-SNAPSHOT.
- [OpenWrt mainline](https://openwrt.org) — the underlying distribution this build is based on.
- [ImmortalWrt](https://github.com/immortalwrt) — additional package and LuCI overlays used during build.

## More documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration](docs/CONFIGURATION.md)
- [Getting started](docs/GETTING-STARTED.md)
- [Development](docs/DEVELOPMENT.md)
- [Testing](docs/TESTING.md)
