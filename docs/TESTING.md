# Testing

This project does not define a conventional application test suite. Most validation is firmware-oriented: syntax checks, OpenWrt config expansion, full image builds, rootfs inspection, release checksum validation, and live-router smoke checks.

## Quick checks before committing

Run these from the repository root after editing tracked source files.

### Shell syntax

Check modified shell scripts and executable helpers:

```sh
sh -n path/to/script.sh
```

Common paths to check include:

```text
target/linux/mediatek/filogic/base-files/etc/uci-defaults/*
target/linux/mediatek/filogic/base-files/etc/init.d/*
target/linux/mediatek/filogic/base-files/etc/hotplug.d/*/*
target/linux/mediatek/filogic/base-files/usr/sbin/*
target/linux/mediatek/filogic/base-files/usr/lib/zbt/*
package/luci-app-zbt-*/root/etc/init.d/*
package/luci-app-zbt-*/root/usr/sbin/*
```

### JavaScript syntax

Check local LuCI JavaScript views with Node when Node is available:

```sh
node --check package/luci-app-zbt-temperature/htdocs/luci-static/resources/view/zbt8803be/temperature.js
node --check package/luci-app-zbt-modem-events/htdocs/luci-static/resources/view/zbt8803be/modem-events.js
```

### JSON syntax

Check LuCI menu and rpcd ACL JSON files:

```sh
python3 -m json.tool package/luci-app-zbt-about/root/usr/share/luci/menu.d/luci-app-zbt-about.json >/dev/null
python3 -m json.tool package/luci-app-zbt-about/root/usr/share/rpcd/acl.d/luci-app-zbt-about.json >/dev/null
python3 -m json.tool package/luci-app-zbt-temperature/root/usr/share/luci/menu.d/luci-app-zbt-temperature.json >/dev/null
python3 -m json.tool package/luci-app-zbt-temperature/root/usr/share/rpcd/acl.d/luci-app-zbt-temperature.json >/dev/null
python3 -m json.tool package/luci-app-zbt-modem-events/root/usr/share/luci/menu.d/luci-app-zbt-modem-events.json >/dev/null
python3 -m json.tool package/luci-app-zbt-modem-events/root/usr/share/rpcd/acl.d/luci-app-zbt-modem-events.json >/dev/null
```

### Git whitespace checks

```sh
git diff --check
git diff --stat
```

## Build validation

The minimum build validation for firmware-impacting changes is:

```sh
./.buildenv/build.sh config
./.buildenv/build.sh build
./.buildenv/build.sh extract
```

Use serial verbose mode for hard failures:

```sh
./.buildenv/build.sh build -j1 V=s
```

## Config validation

After `./.buildenv/build.sh config`, confirm important selections are present in `.config` or generated buildinfo:

```sh
grep -E 'CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be|CONFIG_PACKAGE_luci-app-zbt|CONFIG_PACKAGE_luci-app-mlo|CONFIG_TESTING_KERNEL' .config
```

The seed file intentionally keeps `CONFIG_TESTING_KERNEL` unset so the build stays on the official OpenWrt 25.12.2 stable kernel.

## Rootfs validation

For first-boot defaults, inspect the generated sysupgrade rootfs rather than only the source file.

Example pattern:

```sh
tmp=$(mktemp -d)
tar -xf releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin -C "$tmp" sysupgrade-zbtlink_zbt-z8803be/root
unsquashfs -cat "$tmp/sysupgrade-zbtlink_zbt-z8803be/root" etc/uci-defaults/70-zbt-z8803be-wifi
rm -rf "$tmp"
```

Useful rootfs targets:

| Change area | File to inspect in rootfs |
|-------------|---------------------------|
| WiFi defaults | `etc/uci-defaults/70-zbt-z8803be-wifi` |
| WAN/WWAN failover | `etc/uci-defaults/30-zbt-z8803be-wan-failover` |
| DNS defaults | `etc/uci-defaults/90-zbt-z8803be-dns-cache` |
| QModem monitor | `etc/uci-defaults/45-zbt-qmodem-monitor-enable` and `usr/lib/zbt/qmodem-modem_monitor.sh` |
| Modem events app | `usr/sbin/zbt-modem-events`, LuCI menu/ACL/view files, init script, and service symlinks |
| Temperature app | `usr/sbin/zbt-temperature-log`, LuCI menu/ACL/view files, init script, and service symlinks |

## Release asset validation

After staging release assets in `releases/`, validate checksums:

```sh
cd releases
sha256sum -c sha256sums --ignore-missing
```

Expected checked files include:

```text
config.buildinfo
feeds.buildinfo
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
version.buildinfo
```

After publishing, download the GitHub release to a temporary directory and run the same checksum command against the downloaded files.

## Live-router smoke checks

After flashing or applying runtime scripts to a router, useful checks include:

```sh
ubus call system board
uci show wireless
uci show network.wan
uci show network.4_1
uci show qmodem.4_1
```

For WiFi regulatory and live interface state:

```sh
iw reg get
iw dev
```

For modem monitor state:

```sh
uci show qmodem.4_1 | grep monitor
ps w | grep '[m]odem_monitor'
logread | grep -E 'qmodem_monitor|zbt-modem'
```

For cellular HTTP probe behavior:

```sh
curl -4 --interface wwan0 --connect-timeout 3 --max-time 8 -o /dev/null -sS -w 'http_code=%{http_code} time=%{time_total}\n' http://142.250.23.94/generate_204
```

## Feature-specific checks

### WiFi defaults

Confirm the generated rootfs and live UCI state include:

- `country=PH`
- `cell_density=0`
- no per-radio `txpower`, `min_tx_power`, `channels`, or `scan_list` clamps
- 2.4 GHz channel `11` / `EHT20`
- 5 GHz channel `149` / `EHT80`
- 6 GHz channel `37` / `EHT160`

### WAN/WWAN failover

Confirm:

- `network.wan.metric=10`
- `network.4_1.metric=20`
- `network.4_1.device=wwan0`
- `network.4_1.ifname=wwan0`
- `4_1` and `4_1v6` are listed in the firewall `wan` zone

### DNS defaults

Confirm:

- dnsmasq `noresolv=1`
- dnsmasq cache size `10000`
- upstream servers are the seeded public resolvers unless a deployment script intentionally replaced them
- QModem DNS suppression remains enabled when expected

### Local LuCI apps

Confirm package files are present in the rootfs and the installed router has the expected menu entries, ACL files, backend helpers, and init scripts.

## What is not covered

The repository does not currently contain automated hardware-in-the-loop tests. SFP+ support is included in the device tree/profile, but the public README notes it has not been physically verified here.
