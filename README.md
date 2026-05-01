![OpenWrt logo](include/logo.png)

# OpenWrt for ZBTLink ZBT-Z8803BE

[English](README.md) | [中文](README.zh-CN.md)

> **Community build.** This firmware is maintained by a single contributor outside of any vendor or the OpenWrt Project. Expect rough edges. Bug reports and pull requests are very welcome.

Current custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Build:** `r34156+1-f2ce3e7c4a`
- **Kernel:** Linux `6.12.74`
- **Target:** `mediatek/filogic`
- **Device:** MediaTek MT7988A / Filogic 880 + MT7996-family tri-band WiFi 7
- **Release tag:** `v34156-1-zbt8803be`

## Download

Use the latest GitHub release assets:

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

```text
0a6c1f5f0520acdb7e528c5c45e92716982dd3b7137132dcd82aab7c45943035  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
5a27c934a088e7e27796c8b628ee66f8211a4b5604dbceeb7f58ce31271b2738  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
9e3bc8886ab24ef54c2c096ff32e81a14f5527e5138601967deeb8893a213507  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## Included features

- **Mainline OpenWrt base:** no MediaTek vendor feed required.
- **WiFi 7 tri-band:** 2.4 GHz, 5 GHz, 6 GHz, EHT320, WPA3, MLO-capable.
- **PH regdomain patch:** full 6 GHz range enabled for local testing.
- **LuCI:** HTTPS, Argon dark theme, Chinese translations, package manager.
- **QModem Next:** modern JS modem UI with built-in SMS, Monitor, AT Debug, and SIM Switch.
- **Modem stack:** QMI, MBIM, NCM, MHI, USB serial, QModem, `sms_tool_q`.
- **Built-in SIM Switch:** QModem Next controls SIM slots through `AT+QUIMSLOT`.
- **Modem LEDs:** firmware-enabled LED services and state poller.
- **Default modem power:** slot 1 on (`5g1=1`), slot 2 off (`5g2=0`).
- **Networking:** WireGuard, SQM/CAKE, DDNS, firewall4/nftables.
- **WAN failover defaults:** first boot seeds WAN metric `10` and WWAN/QModem metric `20` for carrier-driven cable-unplug failover.
- **Storage:** USB 3.0, ext4, vfat, exfat, ntfs3, Samba 4, SFTP.
- **Monitoring:** autocore, cpufreq, collectd/statistics, WiFi history.
- **Shell defaults:** banner, color prompt, useful aliases/tools.
- **Package feeds:** OpenWrt + ImmortalWrt overlay feeds configured for APK.

## Verified setup

Validated:

- WAN primary route OK
- WWAN failover works when the WAN link drops
- failover metrics persist correctly after reboot
- DNS/internet OK
- WiFi/MLO active
- QModem Next and SIM Switch working
- modem LED services active

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
cp .buildenv/zbt8803be.config .config
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
- Hardware NAT/offload is not enabled; this build stays on mainline OpenWrt.
- The PH WiFi regulatory patch is for local/private testing. Use responsibly.

## Support / contact

- **Issues / PRs:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Telegram:** https://t.me/Far5eer

PRs and issue reports are very welcome — this is a community build, so please file anything you spot. The same info is also surfaced on the router itself in the SSH banner and at **LuCI -> System -> About this build**.

## Credits

- [@pttuan](https://github.com/pttuan) — upstream OpenWrt board port via [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053): DT-native fan, GPIO watchdog, thermal cooling maps, modern LED bindings.
- [FUjr/QModem](https://github.com/FUjr/QModem) — QModem Next modern JS UI shipped with this build, including the built-in SIM Switch page (`AT+QUIMSLOT`).
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) — vendor firmware research that documented the dead opkg feeds and phone-home tunnel in stock 21.02-SNAPSHOT.
- [OpenWrt mainline](https://openwrt.org) — the underlying distribution this build is based on (no MediaTek vendor feed required).
- [ImmortalWrt](https://github.com/immortalwrt) — additional package and LuCI overlays used during build.
