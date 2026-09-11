# Minimal edition: repair scope and verification

This edition imports the focused cellular userspace repairs from the full build, then removes its optional networking tools.

## Retained repairs

- Exact physical USB/AT ownership for both modems, independent dialer lifecycle, and targeted stop/redial.
- QMI/MBIM/MHI direct-address ownership using `proto=none` with Quectel CM, avoiding competing DHCP.
- Correct slot-based boot discovery and stale-profile path refresh.
- GPIO/LED mapping based on pinned board definitions and physical USB paths.
- Retired automatic factory reset, forced re-enable and cross-modem recovery loops.
- Carrier-profile blank/auto APN handling, a narrow AT&T US `310/410` fallback to `broadband`, matching editable U.S. presets for both SIM selectors, and manual settings preserved.
- Per-modem SA/NSA band parsing, command validation and readback.
- Correct shared-interface Wi-Fi 7 MLO representation plus migration of the old per-band layout.

## Minimal-specific changes

The September 10 follow-up adds the same LED startup/state repairs and friendly Modem 1 / Modem 2 display labels as the full edition. Labels are independent of routing IDs and do not restart dialers. LED control starts after the generic LED service, recovers overwritten trigger settings and has a visible fallback for unavailable triggers/carrier indication. Physical LED/power GPIO definitions are unchanged; this code never writes modem power or SIM pins. `zbt-modem-led-poller status` reports its state without writes.

The Ethernet follow-up also includes the single orange copper WAN lamp, omitted from the previous three-LAN inventory. It enables the board's existing WAN LED0 as `mdio-bus:0f:amber:wan` (LED1 stays disabled), adds missing MT7988 2.5GbE LED callbacks, and corrects shared TX masks. All four Ethernet jacks get user-editable netdev rules: solid linked, blink RX/TX, off without link. The driver backport keeps the PHY firmware cache separate from LED state. Kernel version, modem/Wi-Fi drivers, power and SIM pins remain pinned. Both 5G lights use the same startup repair; in this edition 5G2 remains deliberately dark while its slot is powered off.

Build #1 stopped because the inherited `luci-app-zbt-modem-events` package requires `qmodem_monitor`, forcing an excluded package back on. This optional watchdog-dependent event sampler/history is now excluded too; the config, manifest and rootfs checks still reject any reintroduced monitor. The orphan USB event hook is removed from this edition's overlay. General temperature/status pages remain.

Modem 2's board GPIO starts off and its newly discovered QModem profile defaults to dialing off. Existing operator power/dial selections are not overwritten. Modem 1 defaults on. SIM mux GPIOs are not remapped.

mwan3, additional speed tests, OpenVPN, Tailscale, WireGuard, custom modem-watchdog UX/service and QModem monitor/recovery packages are excluded. The inherited cellular-watchdog files and monitor installer are removed from the source image tree by an explicit path allowlist.

The router hardware watchdog, procd service supervision and normal Quectel session retries remain. No added ping/speed/health policy reboots or power-cycles the modems.

The proprietary bonding installer, UI and dedicated tunnel/web dependencies are not part of this image. LuCI uses the stock uhttpd service.

## Evidence and limitations

Host regression tests exercise GPIO/default selection, package and rootfs exclusions, APN preservation, per-modem ownership, service transactions, targeted redial, band readback, MLO serialization and LuCI service recovery. Device, SIM, AT and service operations are mocked.

The tests also fetch the exact pinned upstream DTS/board defaults and QModem source, validate the exclusion targets, apply patches without fuzz, verify reverse applicability and parse patched shell/JavaScript. The actual Ethernet C LED callbacks and shared helpers are compiled against simulated MDIO registers to test 2.5G link, separate RX/TX, brightness and firmware-cache isolation; this does not replace a full kernel build.

No test here proves RF registration, resolves every carrier rejection, certifies the firmware or validates a physical flash. The reported secondary modem `PS: Detached` condition may still require carrier/APN/band/provisioning investigation. No modem module firmware is upgraded. LAN/WAN activity and the repaired 5G lamps await on-device validation; unrelated GPIOs are not changed.

Use a clean-settings test flash to validate this edition's fresh defaults. Preserving the old full build's configuration/scripts can retain its behavior. The provided runtime verifier is read-only.
