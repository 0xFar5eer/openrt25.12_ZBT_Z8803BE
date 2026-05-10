# ZBT-Z8803BE OpenWrt v25.12.2-5-zbt8803be maintenance release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-5-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since `v25.12.2-4-zbt8803be`

### Firmware / DTS

- **Direct DTSI base.** ZBT-Z8803BE now includes `mt7988a.dtsi` directly instead of inheriting the MT7988A reference-board DTS.
- **Required board nodes restored after removing the RFB DTS include.** The local DTS now carries the board-specific `chosen` bootargs, `memory@40000000`, Ethernet/MDIO setup, switch/LAN LED pinctrl, PCIe0/PCIe1/PCIe3 enablement, SPI-NAND/Factory NVMEM layout, USB PHY/controller enablement, SFP over `i2c2`, PWM fan, and watchdog nodes that were previously inherited.
- **CPUFreq regulator fix.** Restored the RT5190A PMIC/regulator path, `i2c0` pinctrl, and CPU/CCI `proc-supply = <&rt5190_buck3>` wiring needed by MT7988A OPP/CPUFreq; live validation now shows CPU frequencies `800000 1100000 1500000 1800000` instead of `failed to get proc regulator`.
- **Compatibility metadata cleanup.** The legacy `zbtlink,zbt-z8803be,mt7988a-nand` string was removed from the DTS `compatible` list but kept in `SUPPORTED_DEVICES`, and the earlier `DEVICE_COMPAT_VERSION` / `DEVICE_COMPAT_MESSAGE` bump was removed.
- **Label MAC fixed.** `label-mac-device` now points to `&gmac0`, matching the printed/base LAN MAC and the validated live device-tree alias.
- **Wired MAC handling kept stable.** The validated DTS keeps explicit NVMEM cell index `0` for `gmac0`, `gmac1`, and `gmac2`; live validation showed stable wired MACs and no random-MAC fallback.
- **Fan node cleanup.** Removed the unused `#thermal-sensor-cells` property from the `pwm-fan` node.
- **WiFi reset rationale documented.** `wifi-reset-gpios` remains on `&pcie3`, with an expanded comment explaining the MediaTek Gen3 PCIe probe order and why the reset must fire before the MT7996 endpoint on `pcie0` enumerates.
- **Modem slot GPIO rationale documented.** The DTS documents why the primary `5g1` modem slot is powered by default and the secondary `5g2` slot is left off by default.

### WiFi / sysupgrade behavior

- **WiFi preserve-config fix.** The board WiFi uci-defaults script now skips factory SSID rewrites when preserved custom SSIDs already exist, so `sysupgrade` with config preservation keeps existing MLO/IoT/Guest WiFi profiles.
- **Live preserved-config verification.** Existing `AlegriaWifi`, `AlegriaWifi_IOT1`, `AlegriaWifi_IOT2`, and `AlegriaWifi_Guest` profiles survived the tested preserved-config sysupgrade.

### Modem monitoring

- **No-SIM monitor quieting.** QModem monitoring now suspends curl/ping probes while `AT+CPIN?` reports no SIM, records a single informational `Monitor suspended because SIM is missing` event, and resumes normal monitoring when a SIM is present again. This prevents repeated warning/critical rows and reboot-action attempts when the cellular slot is intentionally empty.

### Release metadata / documentation

- **Static About/banner version wording.** LuCI About and the SSH banner now use stable build-channel/base wording instead of embedding the per-release `-N` suffix, so future patch releases do not require manual UI/banner version edits.
- **Checksums refreshed.** README files, release notes, and staged release metadata now point to the live-tested sysupgrade image `5870b7747b97d95e469cbed539db8701346fee454529dd9dfec732520cbd9f55`.
- **Validation runbook refreshed.** `docs/TESTING.md` was updated with the corrected flash/test flow, CPUFreq validation expectations, PR-review traceability, and final v25.12.2-5 test status.
- **PR comment traceability added.** The release notes now link each upstream OpenWrt PR #23053 review point to the local fix or validation result.

## PR review traceability

- **`@hauke`: direct DTS include.** Fixed by switching from `mt7988a-rfb.dts` to `mt7988a.dtsi` and restoring required board nodes. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213293080>.
- **`@hauke`: legacy compatible handling.** Fixed by removing `zbtlink,zbt-z8803be,mt7988a-nand` from DT `compatible` while keeping it in `SUPPORTED_DEVICES`. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213257972>.
- **`@hauke`: fan thermal cell.** Fixed by removing the unused `#thermal-sensor-cells` property from the `pwm-fan` node. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213303728>.
- **`@hauke`: label MAC target.** Fixed by setting `label-mac-device = &gmac0`. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213304880>.
- **`@hauke`: WiFi reset placement.** Fixed by documenting that the MediaTek Gen3 PCIe driver handles `wifi-reset-gpios` and that it must remain on `&pcie3` because `pcie3` probes before `pcie0`. Links: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213261930>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213309837>.
- **`@joelinux60`: wired MAC cells and label MAC.** Kept explicit NVMEM cell index `0` for `gmac0` / `gmac1` / `gmac2` and verified no random MAC fallback; label MAC points to `gmac0`. Links: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206902888>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206909949>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206915357>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3210123646>.
- **`@openwrt-ai`: review confirmation and WiFi reset wording.** Confirmed the DTS cleanup addressed earlier feedback and restored the empirical explanation for keeping reset on `&pcie3`. Links: <https://github.com/openwrt/openwrt/pull/23053#pullrequestreview-4258463777>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206703>.
- **`@openwrt-ai`: modem slot asymmetry.** The DTS already documents why `5g1` is powered by default and `5g2` is off by default. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206797>.
- **`@pttuan`: RT5190A / CPUFreq confirmation.** Local CPUFreq fix follows the restored RT5190A CPU/CCI `proc-supply` path and matches `@pttuan`'s reported available frequencies. Links: <https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414098516>, <https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414354486>.
- **Local-only fix: WiFi reset during preserved-config sysupgrade.** Root cause was this firmware's `70-zbt-z8803be-wifi` uci-defaults script overwriting `/etc/config/wireless`; fixed by exiting early when custom non-`OpenWrt` SSIDs are present.

## Validation

- DTS cleanup passed `git diff --check` and static inherited-node review.
- LuCI About JavaScript passed `node --check`.
- Firmware was rebuilt from this release branch and extracted to `output/mediatek/filogic`.
- The rebuilt sysupgrade image was flashed to the live router with config preservation.
- Live CPUFreq validation passed with available frequencies `800000 1100000 1500000 1800000`.
- Existing `AlegriaWifi`, `AlegriaWifi_IOT1`, `AlegriaWifi_IOT2`, and `AlegriaWifi_Guest` profiles survived the preserved-config sysupgrade.
- Live no-SIM monitor validation passed: the monitor now records `Monitor suspended because SIM is missing` once and stops generating repeated probe-failure/threshold events while no SIM is present.

## Checksums

```text
5870b7747b97d95e469cbed539db8701346fee454529dd9dfec732520cbd9f55  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
6ad6a892ad29b636313521c62235618dd68ee2d7fc3d5a7d4004b8905c920047  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
384713d6d6db10e67f7221ee2cd8bbeb91385406dbc747fe305e4a6ec894c1bb  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
cfea01de20bb0c227723be17f3f38c575839d55ccce926ed94202aecbef378c9  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## Assets

Upload exactly these files:

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

## Flash

Existing OpenWrt:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
