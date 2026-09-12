# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.023` is a maintenance release on top of `v25.12.022`. The OpenWrt base (`r32858-16347e93b6`), kernel (`6.12.74`) and package set are unchanged; the image ships two service-side fixes that came out of chasing a wedged-cellular incident on the maintainer's unit.

## Highlights

### 1. Modem monitor worker: three fixes

The QModem monitor's worker script is hardened in the tree copy (`usr/lib/zbt/qmodem-modem_monitor.sh`), which `52-zbt-qmodem-monitor-overlay` installs over the feed's `/usr/share/qmodem/modem_monitor.sh` at first boot as before:

- **Strict probe verification.** The HTTP probe previously counted any `curl` invocation that exited 0 as a success. A walled-garden/portal answer (a 302 redirect or a 200 landing page instead of the probe URL) therefore reset the failure counter, and a wedged connection survived for hours with the monitor running and never reached the action threshold. Probe URLs matching `*generate_204*` must now answer exactly `204`; all other URLs accept any 2xx/3xx.
- **Recovery streak.** The failure counter is cleared only after `zbt_monitor_recovery_streak` (default `3`) consecutive good probes, so a single stray success no longer clears a failure streak. The default is runtime-only (`qmodem.main.zbt_monitor_recovery_streak`); it is deliberately not seeded into UCI.
- **Action cooldown is marked after dispatching.** The guard script re-checks the same cooldown and refuses to fire while it is active, so marking the cooldown before `run_actions` made every dispatch a self-blocked no-op.

Monitor defaults are unchanged and remain **off** (`monitor_enabled=0`). If you had the monitor enabled, upgrading with configuration kept replaces the worker at first boot and restarts the service; if it was never enabled, nothing happens.

### 2. WiFi client names are display-normalized (luci-app-wifi-clients)

DHCP hostnames are often reported all-lowercase by the device itself (`robot-2fl`), which reads badly next to hand-named entries. The collector now renders display names: floor labels (`1FL`/`2FL`/`3FL`) and acronyms (`LG`, `TV`, `AP`) stay uppercase, everything else renders Title-Case-with-dashes, mixed-case tokens (iPhone, OpenWrt, G5Pro) and hex-id-like tokens (69D1, 1B28) are preserved, a trailing `.lan` suffix stays lowercase, and the `unknown-<mac>` fallback is untouched. Both static names and lease-reported names are normalized.

Note: `luci-app-wifi-clients` is not preinstalled in the trimmed image — the fix ships for anyone who selects the package on demand.

### 3. Misc

- Manifest: 280 packages, image unchanged at ~20.7 MB. `qmodem - 3.0.2-r1`, `qmodem_monitor - 3.0.2-r1` and `luci-app-mlo - 26.254.33408~0ac766c` (version stamp follows the build tree commit).
- `packages-aarch64_cortex-a53.tar.gz` is byte-identical to the `v25.12.022` tarball (same SHA-256): nothing feed-visible changed in this release.

## Validation

- Full Docker rebuild completed successfully; `sha256sum -c sha256sums --ignore-missing` passes for all artifacts.
- `tests/check-zbt-firmware.sh` — expanded this cycle with guards for the strict-204 probe, the recovery streak, the mark-after-dispatch ordering, and the display-name normalization in the collector — plus `git diff --check` pass.
- The hardened monitor script is the same content that was validated live on the maintainer's RM551E-GL (QMI, slot 4-1) unit during the incident that motivated it: the strict probe classifies a portal answer as a failure, and the full recovery chain (probe → threshold → action → cooldown → recovery streak) was proven end-to-end there with a deliberate failure test. The only difference between that live-validated copy and the tree copy is one generalized comment.
- **Not hardware-tested:** the `v25.12.023` image itself has not been flashed to a board — the sysupgrade path was not exercised for this tag. The display-name normalization is covered by unit checks only; the maintainer's unit does not run `luci-app-wifi-clients`. Everything listed as not hardware-tested in `v25.12.022` (MLO client association, the SIM-slot-2 PIN path, and everything behind a second modem) remains unverified.

## Artifacts

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `1a7ba593cb00d84c2920a977cd95d1666270314a3f808da60c721b7c3a833fd2`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `789bc85751c8cafb0da68c9ac876590968728078d52ab3ddb30d8b4e5df7ba3b`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `2f9c1628d40ad17c43779c54bfd3f0c847718f9565b7580eb85e5653c3d15162`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `fc7b71089f4e1ab3f280294d4bdb64b7acff1018a207b73f99de16e0b771a9ae`
- `sha256sums`, `config.buildinfo`, `feeds.buildinfo`, and `version.buildinfo`

## Upgrade
To preserve configuration:

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

For a clean configuration:

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

Upgrading from `v25.12.022` with configuration kept:

- No migrations run and no stored values change. If the monitor was enabled, the hardened worker is installed at first boot and the monitor service restarts; otherwise nothing happens.
- All `v25.12.022` behaviors (vendored dialer fixes, scoped RNDIS hang, exact-path modem LEDs, MLO shared-iface representation and its one-shot repair) carry over unchanged.

## Donate
Optional donations help support maintenance and testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
