![OpenWrt logo](include/logo.png)

# OpenWrt for ZBTLink ZBT-Z8803BE

[English](README.md) | [中文](README.zh-CN.md)

**Complete Minimal edition:** Michael Foster's full Minimal source snapshot,
both-modem setup instructions, and dedicated build command are in
[README-MINIMAL.md](README-MINIMAL.md).

> **Community build.** This firmware is maintained by a single contributor outside of any vendor or the OpenWrt Project. Expect rough edges. Bug reports and pull requests are very welcome.

Current custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **OpenWrt base:** official `v25.12.2` / `r32858-16347e93b6`
- **Kernel:** Linux `6.12.74`
- **Target:** `mediatek/filogic`
- **Device:** MediaTek MT7988A / Filogic 880 + MT7996-family tri-band WiFi 7
- **Release tag:** `v25.12.021`

## Download

Use the latest GitHub release assets:

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `packages-aarch64_cortex-a53.tar.gz`
- `RELEASE_NOTES.md`
- `RELEASE_NOTES.zh-CN.md`

## Checksums

```text
ad74444a8a552798b8fc896b878ac69a4538b0be68b967632c1d4ec7709c2f3d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
e327e89279036f5d2746fe75d7a113e984ebc707b71be4fe5875b6b19ab7ad0e  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
4a4cf6dbc0688f858a092ea0a0d7a79e3d27ce5cb840888df927bbea37e52a5f  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
b91a24b6d113bb9e5e90fcdd612c9c43f8516890dca71ff0e0cb7724f30b40f1  packages-aarch64_cortex-a53.tar.gz
```

## Included features

- **Mainline OpenWrt 25.12.2 base:** no MediaTek vendor feed required.
- **WiFi 7 tri-band:** 2.4 GHz, 5 GHz, 6 GHz, EHT320, WPA3, MLO-capable; **Network → WiFi 7 MLO** provides opt-in MLO configuration in LuCI.
- **Shell timeout:** GNU `timeout` is included at `/usr/bin/timeout`.
- **PH WiFi defaults:** country `PH`, full PH-allowed channel set, no firmware txpower/channel clamps, and automatic regulatory max power.
- **LuCI:** HTTPS, Argon dark theme, Chinese translations, package manager, curated Services menu ordering, and shared ZBT styling across custom firmware apps.
- **QModem Next:** modern JS modem UI with built-in SMS, Monitor, AT Debug, and modem controls.
- **Carrier TTL handling:** the firmware rewrites the IPv4 TTL / IPv6 hop limit of traffic leaving the cellular interface to `64` — the value a native phone presents — via a permanent nft rule (`/etc/nftables.d/99-tether-ttl.nft`). That is correct whenever the modem is a transparent pipe, which is the normal case: a carrier-assigned address on `wwan0` (e.g. CGNAT `10.x`) means the carrier sees exactly `64`. A Quectel dialed QMI can still NAT behind its own embedded DHCP (module-assigned `192.0.0.x` / `192.168.225.x` addresses); the carrier then sees `63`, which is what US postpaid tethering policing reacts to (issue #9). A background probe (`zbt-modem-nat-probe`, fired on cellular ifup) detects that case and raises the **opt-in** TTL plugin (**Modem → QModem → TTL**, pre-seeded to `64` and disabled because enabling it also clears hardware flow offloading) to `65` automatically; it never enables the plugin for you and backs off permanently if you hand-edit the value. Turning TTL back off does not restore flow offloading — do that with `uci set firewall.@defaults[0].flow_offloading='1' && uci commit firewall && /etc/init.d/firewall restart`. Note the nft rule matches `oifname "wwan0"` only: test TTL from a LAN client, not from the router itself.
- **Modem stack:** QMI, MBIM, NCM, MHI, USB serial, QModem, `sms_tool_q`.
- **Z8803BE-T SIM wiring note:** on this exact model/variant, SIM1 is wired to modem1 and SIM2 is wired to modem2; one module cannot control both SIM cards, so SIM switching is not supported. Supplier notes that another Z8803BE-T version does support one module controlling two SIM cards.
- **Modem LEDs:** firmware-enabled LED services and state poller.
- **Default modem power:** slot 1 on (`5g1=1`), slot 2 off (`5g2=0`). When slot 2 is manually powered, its QModem profile and WAN integration are selected by USB path without modifying slot 1.
- **Networking:** WireGuard (`wireguard-tools`, command line only), firewall4/nftables.
- **WAN failover defaults:** first boot seeds SFP metric `9`, RJ45 WAN metric `10`, and cellular metric `200`, so a wired uplink always wins and cellular carries the router when nothing wired is up.
- **Storage:** USB 3.0, ext4, vfat, exfat, `block-mount`, SFTP.
- **Monitoring:** ZBT Health page, autocore, temperature logging, modem event history.
- **Deliberately small image:** v25.12.016 shipped 525 packages in a 62 MB image; v25.12.021 ships 280 in 20.7 MB. This board runs from SPI-NAND with a squashfs rootfs plus a UBIFS overlay, and a fat rootfs stretched the post-flash configuration reset into minutes during which modem hotplug, WiFi bring-up and firewall rules raced a half-built overlay. Traffic statistics, QoS, DDNS, NAS, DNS filtering and broad diagnostic tools are therefore not preinstalled; install them on demand from the package manager.
- **Temperature monitor:** built-in ZBT temperature charts with per-module avoid-limit overlays and fan PWM logging.
- **Router health page:** built-in ZBT Health page for overlay/storage, RAM, conntrack, uptime, and write-hotspot checks.
- **Shell defaults:** banner, color prompt, useful aliases/tools, `git`, `git-http`, and a BusyBox-compatible `install` shim.
- **Package feeds:** OpenWrt + ImmortalWrt overlay feeds configured for APK.

## Verified setup

Validated:

- WAN primary route OK
- WWAN failover works when the WAN link drops
- failover metrics persist correctly after reboot
- DNS/internet OK
- WiFi/MLO active
- QModem Next modem controls working; SIM1 is fixed to modem1 and SIM2 is fixed to modem2 on this exact unit
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
- PH WiFi defaults follow `wireless-regdb` and remove only firmware-side txpower/channel clamps; confirm local compliance before changing country, channels, or antenna gain.

## Support / contact

- **Issues / PRs:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Email:** [0xfar5eer@gmail.com](mailto:0xfar5eer@gmail.com)
- **Discord:** `0xFar5eer#6504`

PRs and issue reports are very welcome — this is a community build, so please file anything you spot. The same info is also surfaced on the router itself in the SSH banner and at **LuCI -> System -> About this build**.

## Donate

Optional donations support continued maintenance and hardware testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`

## Credits

- [@pttuan](https://github.com/pttuan) — upstream OpenWrt board port via [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053): DT-native fan, GPIO watchdog, thermal cooling maps, modern LED bindings.
- [@sjanulonoks](https://github.com/sjanulonoks) — fan-control suggestion and general release testing that helped tune and validate this ZBT-Z8803BE build.
- [FUjr/QModem](https://github.com/FUjr/QModem) — QModem Next modern JS UI shipped with this build; SIM switching is disabled for this exact Z8803BE-T variant because SIM1/SIM2 are wired to separate M.2 modems.
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) — vendor firmware research that documented the dead opkg feeds and phone-home tunnel in stock 21.02-SNAPSHOT.
- [OpenWrt mainline](https://openwrt.org) — the underlying distribution this build is based on (no MediaTek vendor feed required).
- [ImmortalWrt](https://github.com/immortalwrt) — additional package and LuCI overlays used during build.

## Contributing

Bug reports and pull requests are welcome. Builds run in Docker through
`.buildenv/build.sh` — its usage block lists the subcommands — and
`sh tests/check-zbt-firmware.sh` is the static gate a change has to clear
before it ships in a release.
