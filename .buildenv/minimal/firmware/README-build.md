# Build the Minimal edition

This repository is an independent build recipe, not a complete OpenWrt checkout. It downloads the pinned Far5eer source and feeds during the build. The [main README](../README.md) documents pins, features, safety limits and default modem behavior.

## GitHub Actions

Push firmware/workflow changes to `main`, or open **Build Minimal Firmware → Run workflow**. The source tag is `v25.12.021`; the expected commit is checked separately. Changing the tag alone intentionally fails the build.

The firmware job depends on the reusable Sanity workflow. No personal access token, router password or server SSH key is needed; checkout uses the read-only built-in GitHub token. Builds are serialized within this repository and do not cancel an already-running build.

Only successful builds publish a firmware artifact. Diagnostics are separate. Both artifact types expire after 14 days.

## Local Docker build

Use a Linux build host with Docker, Git, reliable network access and sufficient free space. The hosted workflow requires at least 40 GiB free before starting; package/source caches and repeated local builds may need more.

From this repository:

```sh
bash firmware/scripts/check-build-inputs.sh
node firmware/tests/check-patches.cjs
docker build -f firmware/docker/Dockerfile.remote-builder -t zbt-minimal-builder .
docker run --rm \
  -e FINAL_MAKE_JOBS=2 \
  -v "$PWD:/workspace" \
  zbt-minimal-builder bash /workspace/firmware/docker/build-openwrt.sh
```

Host tests need Node 22+, BusyBox, jq, patch, ripgrep and a C compiler (`cc` / GCC). The LED tests compile real driver callbacks/shared helpers against simulated MDIO registers; a full kernel/firmware build is not part of the host tests. The container uses the repository-mounted `openwrt/` directory for compiler inputs/outputs. No physical router is accessed.

Results are under `openwrt/bin/targets/mediatek/filogic/`. Inspect the target manifest, checksums and `openwrt/.config` before testing images.

## Inputs and safeguards

- `profiles/base-config-zbt-z8803be-v25.12.021.config`: original checksum-verified release baseline.
- `profiles/packages-default.txt`: required board, cellular and LuCI support packages.
- `profiles/kconfig-fragment.conf`: explicit minimal-build exclusions, including upstream WireGuard and QModem monitor packages.
- `profiles/excluded-base-files.txt`: exact inherited watchdog/monitor files omitted from this image.
- `patches/qmodem-dual-runtime.patch`: strict, zero-fuzz userspace patch against the pinned QModem feed.
- `patches/zbt-wan-led.patch`: enables the board's existing WAN LED0 node, leaving LED1 disabled.
- `kernel-patches/753-net-phy-mediatek-mt7988-led-control.patch`: backports Ethernet PHY LED callbacks and corrects TX masks in the pinned kernel.
- `patches/luci-app-mlo-shared-iface.patch`: stores a real MLD as one shared multi-radio interface.
- `patches/hostapd-mlo-interoperability.patch`: applies reviewed upstream AP-MLD advertisement, reassociation, interface-reuse, and reload fixes after OpenWrt's hostapd patch queue without changing the pinned source version.
- `files/`: modem isolation/GPIO defaults, safe band controls, LED ownership repair and MLO migration.
- `scripts/check-minimal-profile.sh`: rejects excluded packages and leftover watchdog/menu files in resolved configuration and build output.

The recipe applies the narrow WAN LED DTS/driver patches before kernel preparation; the kernel version and modem/Wi-Fi sources remain pinned. Tests read the original modem GPIO definitions and verify 5G1 on / 5G2 off. Removing speedtest-go and Tailscale also removes the old forced Go bootstrap build step.

Never copy old `artifacts/`, router backups, SIM/account data or local deployment scripts into the public build. They are ignored by Git and are not embedded by the builder.
