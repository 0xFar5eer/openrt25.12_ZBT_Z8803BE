# Complete Minimal source handoff

This branch contains the full Far5eer OpenWrt source tree plus **all 73 tracked
files** from Michael Foster's Minimal edition at
[`8edc09442a088a3e89df03e7947700cc8fe7b261`](https://github.com/mfoster978/openwrt-zbtlink-zbt-z8803be-speedify-minimal-build/tree/8edc09442a088a3e89df03e7947700cc8fe7b261).
The complete snapshot is in [`.buildenv/minimal/`](.buildenv/minimal/), including
every runtime file, patch, package selection, exclusion, build script, test,
document, and original CI/publication script. Its content and executable modes
are unchanged; [the inventory](.buildenv/minimal-source.json) records each file.
No source or commit history is imported from the Mega repository.

The base is Far5eer `v25.12.021`, commit
`edc738504fe8fae81eb15de967456204699b1830`, OpenWrt 25.12.2 / Linux 6.12.74.
The build uses the complete source already in this repository and downloads
the original pinned feeds and package sources through OpenWrt's normal build
system. The QModem feed stays at `a8b8a63e5b0853c79d2ad3f1ebbb673a724872bf`;
the complete Minimal patch is applied to it with zero fuzz.

## Build this edition

Clone this PR branch with Git, then run from the repository root:

```sh
bash .buildenv/build-minimal.sh build
```

The host needs Git, Python 3, Bash, ripgrep and Docker, plus at least 40 GiB
of free space. The unchanged Minimal Dockerfile builds for Linux amd64; ARM
hosts need Docker's amd64 emulation. Use a case-sensitive Linux filesystem for
the build directory. `MINIMAL_BUILD_DIR=/path/on/linux/filesystem` selects another
build directory; `FINAL_MAKE_JOBS=2` is the conservative default.

The wrapper verifies all 73 files and creates a separate checkout of the pinned
base under `minimal-build/openwrt/`. It then runs the original Minimal builder,
which applies **every** runtime/feed/kernel/MLO change, installs the complete
overlay, resolves Minimal's package configuration, removes the exact inherited
watchdog files, and validates the finished image. It does not require access to
Michael's Minimal or Mega repository to obtain custom source. The older
`.buildenv/build.sh` commands still select Far5eer's original configuration;
use **`build-minimal.sh`** for this handoff.

Outputs are in `minimal-build/openwrt/bin/targets/mediatek/filogic/`:

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- the target manifest and checksums.

`bash .buildenv/build-minimal.sh check` verifies the snapshot and build inputs.
`bash .buildenv/build-minimal.sh prepare` creates the source checkout without
compiling. A shallow clone must contain the pinned base; if it does not, run
`git fetch origin edc738504fe8fae81eb15de967456204699b1830` first.

The imported `.github` files inside `.buildenv/minimal/` preserve the original
automation source. The active root workflow runs the Minimal checks; local
builds need no release-generation credentials. The inventory intentionally
detects later source edits: update it deliberately when revising this snapshot.

## Both physical modems

The full connection fixes are included: independent per-modem processes and
configuration fingerprints, physical USB discovery, targeted reconnects,
QMI/MBIM/MHI address ownership, automatic/manual APNs, PIN/PDP guards, band
capability/readback controls, editable labels, and persistent route priorities.
It also includes per-modem IPv4 TTL / IPv6 Hop Limit policies, GPIO/LED repairs,
WAN PHY LEDs, LuCI startup repairs, Wi-Fi 7 MLO changes, and the latest first-boot
network and route-priority fixes.

| Physical modem | Stable QModem ID | USB path | Power GPIO | Default |
|---|---|---|---|---|
| Modem 1 / 5G1 | `4_1` | `4-1` | 17 / `5g1` | Powered, dialing enabled |
| Modem 2 / 5G2 | `2_1` | `2-1` | 52 / `5g2` | Power and dialing opt-in |

To use both after installing the Minimal image:

1. Enable **Power 5G2 modem slot** in LuCI's GPIO/Switches controls; save/apply.
2. Wait for QModem to discover modem **`2_1`**.
3. Enable dialing for that modem and enter its carrier-required APN/PIN; save/apply.
4. Verify registration and data connectivity separately for each modem. Wired
   routes remain preferred; cellular metrics are 200 for modem 1 and 210 for modem 2.

The second modem's later power/dialing choices persist. Enabling it does not
intentionally power-cycle modem 1. Both connections can be active, with the
ordinary route metrics selecting the preferred uplink. Minimal does not provide
bonding, load balancing, or a health-probed failover manager.

Use the ZBT-Z8803BE sysupgrade image and the normal recovery/backup procedure.
For Minimal's fresh defaults, do not preserve the previous firmware's settings;
old scripts and configuration can retain the behavior being fixed. After boot,
run the included
[`verify-router-runtime.sh`](.buildenv/minimal/firmware/scripts/verify-router-runtime.sh)
for read-only diagnostics. Successful source/build checks do not substitute for
testing both SIM/carrier sessions on Far5eer's router.

The [complete feature and behavior documentation](.buildenv/minimal/README.md),
[original build guide](.buildenv/minimal/firmware/README-build.md), and
[runtime repair notes](.buildenv/minimal/firmware/docs/runtime-repair-2026-09.md)
are included unchanged. Upstream component licenses and credits remain in place.
