<h1 align="center">ZBTLink ZBT-Z8803BE · Minimal Build</h1>

<p align="center">
  Far5eer's pinned OpenWrt foundation with focused dual-modem, LED, and MLO repairs.<br>
  Primary modem enabled. Secondary modem opt-in. No added MultiWAN manager or recovery watchdog.
</p>

<p align="center">
  <a href="https://github.com/mfoster978/openwrt-zbtlink-zbt-z8803be-speedify-minimal-build/actions/workflows/build-openwrt-firmware.yml"><img alt="Build" src="https://github.com/mfoster978/openwrt-zbtlink-zbt-z8803be-speedify-minimal-build/actions/workflows/build-openwrt-firmware.yml/badge.svg"></a>
  <img alt="OpenWrt" src="https://img.shields.io/badge/OpenWrt-25.12.2-00B5E2">
  <img alt="Kernel" src="https://img.shields.io/badge/Linux-6.12.74-FCC624">
  <img alt="Profile" src="https://img.shields.io/badge/profile-Minimal-7952B3">
</p>

> **Device-specific, hardware testing required.** Only for the ZBTLink ZBT-Z8803BE target. Build checks do not prove SIM registration, radio stability, or safety on a different board. Nothing in this repository automatically flashes a router.

## What this edition contains

This is a separate build recipe derived from the focused runtime repairs in the [Mega Edition](https://github.com/mfoster978/openwrt-zbtlink-zbt-z8803be-mega-edition). It does not modify that project or cancel its builds. Only reviewed source/build inputs are shared; private router dumps, SIM data, backups and deployment history are not published here.

| Component | This edition |
|---|---|
| Far5eer device support, Wi-Fi and cellular drivers | Retained at the pinned release |
| QModem Next, QMI/MBIM, Quectel CM, SMS and AT controls | Retained |
| Modem connection ownership, discovery and GPIO/LED repairs | Retained |
| Wi-Fi 7 MLO configuration repair and legacy-layout migration | Included |
| Speedify, its installer and its dedicated dependencies | Not installed |
| Modem 1 / physical 5G1 | Power on, dialing enabled by default |
| Modem 2 / physical 5G2 | Power off, dialing disabled by default; manual opt-in |
| Added MultiWAN Manager / mwan3 | Not installed |
| Speed Test Utility, speedtest-go/netperf, iperf | Not installed |
| OpenVPN, Tailscale and WireGuard tools/modules | Not installed |
| Added modem watchdog, speed failover, automatic recovery policies | Not installed |
| QModem monitoring/recovery package and inherited auto-watchdog | Not installed |
| Inherited watchdog-dependent modem event sampler/history | Not installed |
| Normal OpenWrt hardware watchdog / procd supervision | Retained for router safety |

The original device's temperature and general status pages, Wi-Fi, storage support and ordinary routing remain. “Minimal” means removing these optional networking add-ons, not stripping essential board support. The optional modem-event sampler is excluded because it requires the removed QModem monitor and otherwise reports that monitor's absence as a fault.

## Exact source baseline

| Input | Pin |
|---|---|
| Source | [0xFar5eer/openwrt25.12_ZBT_Z8803BE](https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/tree/v25.12.021) |
| Release | `v25.12.021` — OpenWrt `25.12.2` |
| Source commit | `edc738504fe8fae81eb15de967456204699b1830` |
| Kernel | `6.12.74` |
| Target / profile | `mediatek/filogic` / `zbtlink_zbt-z8803be` |
| QModem feed | `a8b8a63e5b0853c79d2ad3f1ebbb673a724872bf` |
| Packages feed | `db3b315119519f9194dad8aa668aa40618df9b20` |
| APK architecture | `aarch64_cortex-a53` |

The original release config is preserved, checksum-verified, then overridden by this edition's package selections and exclusions. This is **not a byte-for-byte stock image**: the package set and cellular userspace change. The WAN LED repair enables the existing board LED0 node and backports Ethernet PHY LED controls. Kernel version, Wi-Fi firmware and modem driver source pins remain unchanged. This pins a reviewed release; it does not silently follow an upstream “latest” branch.

## Cellular behavior and fixes

- One connection manager per physical modem, with independent configuration fingerprints and targeted stop/redial. Changing modem 2's APN does not blanket-restart modem 1.
- QMI/MBIM/MHI direct-address mode uses `proto=none`; the Quectel connection manager owns IP addresses/routes instead of competing with a DHCP client.
- Boot scanning uses the USB slot name, not a full sysfs path as a lock filename. Existing profiles get refreshed physical paths.
- No automatic post-flash modem factory reset, forced re-enable loop, or ping/speed-triggered modem power cycle.
- Blank or `auto` APNs preserve modem/network profile negotiation. A directly identified AT&T US `310/410` SIM gets the data-device fallback `broadband`; every manual APN still wins. Both SIM selectors offer editable presets for AT&T, FirstNet, T-Mobile, Verizon, Google Fi, and U.S. Cellular. **Automatic APN selection cannot guarantee service on every carrier or plan.**
- SA/NSA band controls validate each modem's capabilities, AT response and readback. Unknown masks have read-only diagnostics and Retry; reported bands stay separate from pending edits. See [per-modem band readback](firmware/docs/band-readback.md).
- Menus and dropdowns show editable **Modem 1** / **Modem 2** labels, separate from stable `4_1` / `2_1` routing IDs. Renaming a modem does not restart either connection.
- LEDs follow each physical USB device, not `wwan0` / `wwan1` enumeration order. The individual 5G1/5G2 lamps are physical green indicators even though their stable kernel names begin with `blue:`. The multicolor SYS lens preserves blue for no Internet and green for Internet access. It shows red when Internet remains available but a powered/present modem lacks a data session, solid green while idle, and blinking green during cellular traffic. The three LAN-jack indicators and single copper WAN-jack indicator are physical orange LEDs. They are configured to stay solid with link and blink on RX/TX through MediaTek PHY hardware offload. LAN metadata retains `green:lan`; the newly exposed WAN lamp is `mdio-bus:0f:amber:wan`, bound to `eth1`. The WAN repair enables the existing board LED0 pin and backports the missing Ethernet LED callbacks; it does not change modem power/SIM pins or the kernel version. Physical behavior still needs confirmation after flashing. All exposed LEDs can be overridden under **System → LED Configuration**; a user rule takes ownership from the automatic modem controller. `zbt-modem-led-poller status` is read-only.
- Manual reconnect controls and the connection manager's normal session retries remain. They are not the removed health-monitor/power-cycle watchdog.

### Board mapping

| Modem | QModem ID | USB path | Power GPIO, active-high | LED GPIO, active-low | Default metric |
|---|---|---|---|---|---:|
| 1 | `4_1` | `4-1` | 17 / `5g1` | 61 / `blue:mobile-1` | 200 |
| 2 | `2_1` | `2-1` | 52 / `5g2` | 53 / `blue:mobile-2` | 210 |

These match the pinned device tree; 5G2 is already off at the kernel GPIO-export stage. SIM routing is unchanged. QModem's internal “SIM Slot 1” can legitimately appear for both modems while they read different SIM cards. No SIM mux or LAN LED pins are guessed or remapped in this edition.

### Enabling modem 2 later

1. In LuCI's GPIO/Switches controls, enable **Power 5G2 modem slot** and save/apply.
2. Wait for QModem to discover the second modem under `2_1`.
3. Enable dialing for that modem, set any carrier-required APN/PIN, then save/apply.
4. Confirm its registration and Internet access.

A newly discovered modem 2 starts with dialing **off**, even after power is enabled. Later operator power/dial choices survive rediscovery and reboot. Modem 1 is not intentionally power-cycled by this process.

## Independent modem TTL

Under **QModem → TTL**, each modem has its own enable switch and automatic/custom value. You can modify only one modem or assign different IPv4 TTL / IPv6 Hop Limit values to both. Rules follow physical slots across reconnects. Primary automatic behavior is retained; secondary rewriting is opt-in and does not enable its power or dialing. Enabling either policy disables flow offloading globally. See [TTL controls, migration and tests](firmware/docs/per-modem-ttl.md).

## Wi-Fi 7 MLO

The MLO page now stores one logical `wifi-iface` with a list of all selected radios, which is the representation expected by this pinned netifd version. The previous page created one independent `mlo=1` section per band; that advertised matching SSIDs but did not create a multi-link device. A conservative first-boot migration combines only existing same-SSID AP sections that already opted into MLO, leaving ordinary same-name networks untouched.

The pinned hostapd also receives a bounded set of upstream AP-MLD fixes for partner-profile length accounting, per-link BSS change counters, EML capability fields, reassociation state, and reload/interface reuse. Key-free `MLD: association ... link bitmap=` messages in `logread` show which links the station requested and whether hostapd accepted them. A bitmap with only one bit means the client requested only one setup link; two or more bits accepted by hostapd but absent in mac80211 points lower in the stack. MLO still requires a compatible Wi-Fi 7 client, at least two enabled radios, matching credentials and WPA3/PMF-compatible settings.

## Routing without mwan3

Far5eer's ordinary wired-first route metrics remain: wired WAN routes are preferred over cellular. There is **no speed-threshold failover manager, periodic bandwidth test, or health-probed mwan3 policy**. Route metrics alone do not detect every upstream Internet outage.

## Build and download

Every push changing `firmware/**` or workflows on `main` starts **Build Minimal Firmware**. It is also available under **Actions → Run workflow**. Source tag changes must agree with the pinned source commit.

The workflow first runs host regression tests and pin checks, then builds on a separate GitHub-hosted runner. It does not require SSH/server secrets, touch the physical router, or share concurrency with the full build repository.

Each successful run creates a GitHub Release and a 14-day workflow artifact containing only:

- target-specific SquashFS sysupgrade and initramfs images;
- the package manifest, image checksums and build identity;
- detailed Gemini-generated release notes and a read-only runtime verifier.

The workflow does not upload the OpenWrt source/build tree or package archive. GitHub automatically adds “Source code” links for every release tag; those cannot be disabled and are not flashable firmware.

Failed builds upload **diagnostics only**, never partial images labeled as firmware. Artifacts expire after 14 days. Only successful, device-matching images should be considered for testing.

### Flashing and validation

Back up your router privately and confirm your recovery procedure first. Use the device's appropriate sysupgrade image only after the build passes. Do not flash individual partitions or other device images based only on a similar filename.

**To get this edition's fresh defaults, do not carry the old build's settings into the test flash.** Preserved configuration, scripts or installed extras can keep modem 2 enabled or reintroduce old behavior. Backups may contain passwords/SIM details; never commit them here.

No router has been flashed automatically. Both-modem carrier registration, real GPIO behavior, Ethernet activity blinking, and negotiated multi-link operation require on-device validation.

After flashing, run the included `verify-router-runtime.sh` for read-only diagnostics. Review/redact output before sharing. It reports physical mappings, enable flags, addresses, package state, LuCI health and the MLO section shape without dumping SIM IDs or account tokens.

## Developer notes

See [Build guide](firmware/README-build.md) for local Docker commands and [repair scope](firmware/docs/runtime-repair-2026-09.md) for the patch boundaries. Edit the new repository independently; the full-featured project is unaffected.

The build rejects forbidden packages in both resolved Kconfig and the finished manifest. It also checks the assembled rootfs for leftover recovery scripts/menus. Exact-file removal is limited to the reviewed inherited cellular-watchdog files; kernel/procd watchdog support remains intact.

## Credits and licensing

- **0xFar5eer** — device-specific OpenWrt source, board support and release baseline.
- **OpenWrt contributors** — operating system, build system, drivers and LuCI.
- **FUjr / QModem contributors** — modem discovery, controls and connection integration.
- **ZBTLink, MediaTek and Quectel** — hardware and relevant platform/modem work.
- **mfoster978** — this independent build configuration and integration.

Each upstream component retains its own license and notices. Credits are acknowledgements, **not claims of sponsorship, certification or endorsement**.
