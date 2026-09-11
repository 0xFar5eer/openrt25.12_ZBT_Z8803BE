# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.022` is a community firmware build for ZBTLink ZBT-Z8803BE. It is a new release, not an in-place refresh of `v25.12.021`: everything validated in 021 carries over, and this page describes only what changed since that tag. The OpenWrt base and kernel are unchanged.

## Highlights

This release adapts the safe subset of upstream QModem PR #14 (the dialer fixes and the MLO shared-interface repair), hardens two hotplug handlers that only matter once a second modem is installed, and vendors the packages those patches touch so the fixes ship in the image instead of waiting on the feed.

### 1. QModem dialer: five fixes, vendored

The whole `qmodem` application (3.0.2) now lives in the tree as `package/qmodem/`, following the same pattern as the `autocore` fork. The feed's Makefile installs straight from its `files/` tree and cannot carry patches, so shipping a fixed `modem_dial.sh` required vendoring; the vendored copy supersedes the feed package (`qmodem - 3.0.2-r1` in the manifest). Adapted from PR #14:

- Two shell syntax bugs in `modem_dial.sh`: the missing space before `]` in `unlock_sim`'s "this PIN already failed this boot" guard made the comparison error out and take the false branch, so every dial attempt re-sent `AT+CPIN=` toward an already-rejected PIN (modems count failed attempts and eventually present PUK). The same `]`-space bug in the `suggest_pdp_index` fallback inside `update_config` meant the platform-suggested PDP index was never filled in when the option was unset.
- The SIM-slot-2 branch now falls back to the modem-level `pincode` when `pincode2` is unset; previously it fetched the common PIN into an unused variable, so a locked SIM on slot 2 with only `pincode` set never unlocked.
- Metric preservation: `set_if()` copied the qmodem profile's `metric` into `network.<iface>.metric` on every redial, clobbering the router-wide route contract (SFP `9`, RJ45 WAN `10`, cellular `200`). A numeric `network.<iface>.metric` now wins over the profile value, so the cellular metric cannot drift away from the WAN-failover seeding.
- Redial retention: the hang/cleanup pass no longer deletes the primary `network.<iface>` section. It now clears only the runtime `ifname`/`device` binding while keeping `modem_config`, `defaultroute=1` and the metric, and leaves `dns`/`peerdns` untouched, so operator DNS edits and the route metric survive redials. The IPv6 companion section is still deleted and recreated from the current PDP mode.

### 2. RNDIS hotplug no longer restarts the whole dialer stack

`15-zbt-rndis-auto` disabled the QModem profile for a detected Quectel RNDIS composition and then restarted `qmodem_network` globally, bouncing every configured modem's dial loop. It now hangs only the matching profile's procd instance (`modem_4_1`/`modem_4_2`), derived from the USB path. With a single modem the visible behavior is identical; with a second modem installed, the unrelated dialer is no longer interrupted.

### 3. Front-panel modem LEDs bind by exact USB slot

`20-zbt-modem-led` derived the slot by suffix-matching the USB path, so a WWAN netif appearing on a root-hub port such as `2-1` or `1-1` — which has no modem slot behind it on the MT7988A — would have been bound to the 5G1/5G2 front-panel LED. The hotplug now resolves the LED from `qmodem.@modem-slot[N].led` by exact slot match (seeded by `20-zbt-qmodem-slots` with `blue:mobile-1`/`blue:mobile-2`), keeps a hard-wired `4-1`/`4-2` fallback for configs saved before the option existed, and logs and binds nothing for unmapped paths.

### 4. The MLO page now writes what netifd consumes — plus a one-shot repair

`luci-app-mlo` is vendored and its page rewritten (adapted from PR #14): saving an MLD writes ONE `wifi-iface` whose `device` is the list of participating radios, with `mlo='1'` and `ieee80211w='2'`, instead of one scalar-device section per band. The old representation carried a single link per record, so hostapd never formed a multi-link group. Bands dropped from an existing MLD are rewritten into standalone per-band sections with their PMF rules preserved.

New `74-zbt-mlo-shared-iface-repair` migrates groups written by the old page on first boot: an SSID-group of `mlo=1` AP sections with two or more radios is rewritten into the shared multi-device representation, redundant peer sections and the per-record `mld_ap`/`mld_id` options are removed, and LAN membership is made explicit. Ordinary APs and single-link groups are left alone; the script is board-guarded and commits only when something changed.

### 5. Packages feed tarball regenerated

`packages-aarch64_cortex-a53.tar.gz` was regenerated from this build's package tree with the same 156-apk layout (157 tar members). It now carries the fixed, vendored `qmodem-3.0.2-r1` apk and the current `luci-app-zbt-about` build; the `v25.12.021` tarball had been assembled before the dialer fixes existed (the 021 firmware image itself was not affected — the fixed dialer ships in the image, only the feed tarball lagged). While regenerating, one stale leftover from 021 still present in the feed tree (the superseded `luci-app-zbt-about-26.218.24774~bd3a8ec` apk) was removed, so the tarball again contains exactly one apk per package.

### 6. Misc

- Manifest: 280 packages, image unchanged at ~20.7 MB. `qmodem` and `luci-app-mlo` now come from the vendored copies (`qmodem - 3.0.2-r1`, `luci-app-mlo - 26.221.38405~a36ca24`); the QModem companion apps (`luci-app-qmodem-monitor`/`-next`/`-ttlfw4`, `qmodem_monitor`) report the vendored release number as well.

## Validation

- Full Docker rebuild completed successfully; `sha256sum -c sha256sums --ignore-missing` passes for all artifacts.
- The staged rootfs was inspected in the build volume: all five dialer fixes are present in the installed `modem_dial.sh`; the feed's `qmi|mbim|mhi) proto="none"` interface-ownership code is absent; the scoped RNDIS hang, exact-path LED resolution, seeded `led` options, the MLO repair script and the rewritten MLO page are all present.
- `tests/check-zbt-firmware.sh` — expanded this cycle with guards for the scoped hang (a global `qmodem_network restart` in the RNDIS hotplug now fails the check), exact-path LED mapping, the seeded `led` options, the five vendored dialer fixes, and the MLO repair — plus `node --check` on the MLO page and `git diff --check` pass. The checker also forbids the PR parts deliberately not adopted (`dual-modem.sh`, `zbt_netcard`, `proto="none"` QMI ownership).
- The regenerated feed tarball was verified member-by-member against the fresh package tree: 157 members, and its `qmodem-3.0.2-r1.apk` is byte-identical to the apk the image was built from.
- **Not hardware-tested:** MLO client association (no MLO-capable client was available for this pass), the SIM-slot-2 PIN path (single-SIM wiring on this unit), and everything behind a second modem — the 5G2 slot is unpopulated and the remaining PR #14 dual-modem work is deferred until that hardware is in hand. The cellular unit (RM551E-GL, QMI, slot 4-1) and its validated issue #9 behavior are unchanged by this release.

## Artifacts

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `37d2364c3219afb26b9c9b2e6ccdea8a73fe7941de2a0d39b2bb0a9368991ea9`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `ff1e023ee2aa1170778552db9e58e334226d3c60d5ef0f3c4daa6250cb2a02cf`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `b7773d432b257ac851b2c973e0397bcbb6eb6f588aa32c0740806c1c8715fc7a`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `fc7b71089f4e1ab3f280294d4bdb64b7acff1018a207b73f99de16e0b771a9ae`
- `sha256sums`, `config.buildinfo`, `feeds.buildinfo`, and `version.buildinfo`

## Upgrade
To preserve configuration:

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

For a clean configuration:

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

Upgrading from v25.12.021 with configuration kept:

- The one-shot `74-zbt-mlo-shared-iface-repair` rewrites MLO groups created with the previous MLO page into the shared representation on first boot; MLO groups saved afterwards use the new representation directly. If you never configured an MLO group, nothing happens.
- Existing `network.<cellular>.metric`, `dns` and `peerdns` values now survive redials; nothing needs to be re-entered after upgrading.

## Donate
Optional donations help support maintenance and testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
