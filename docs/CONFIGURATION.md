# Configuration

This document describes the configuration surfaces that are tracked in this repository and baked into the ZBT-Z8803BE firmware image.

## Seed build configuration

The build seed lives at:

```text
.buildenv/zbt8803be.config
```

The Docker build wrapper merges that seed into `.config` during:

```sh
./.buildenv/build.sh config
```

The seed selects the ZBT-Z8803BE target:

```text
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y
```

It also selects the local and feed packages that define the feature set.

## Core package selections

| Area | Selected packages and settings |
|------|--------------------------------|
| LuCI | `luci`, `luci-ssl`, `luci-app-package-manager` |
| WiFi security | `wpad-openssl`; `wpad-basic-mbedtls` disabled |
| Storage | `kmod-usb3`, `kmod-usb-storage`, ext4/vfat/exfat support, `block-mount`, `openssh-sftp-server` |
| VPN | WireGuard packages |
| Monitoring | `luci-app-zbt-health`, `autocore`, `luci-app-zbt-temperature`, `luci-app-zbt-modem-events` |
| ZBT LuCI apps | `luci-app-zbt-about`, `luci-app-zbt-health`, `luci-app-zbt-modem-events`, `luci-app-zbt-temperature` |
| Cellular modem | QMI, MBIM, NCM, MHI, USB serial, QModem Next, QModem monitor, `sms-tool_q`, `tom_modem`, `qfirehose`, `quectel-CM-5G-M`, `jq`, and the required coreutils utilities |
| Translation | `CONFIG_LUCI_LANG_zh_Hans=y` |

The seed follows OpenWrt main's MediaTek 6.12 kernel series. This customized tree pins Linux 6.12.101 in `target/linux/generic/kernel-6.12`.

## Packages intentionally not selected

The seed config intentionally excludes some packages:

| Package or group | Reason recorded in config |
|------------------|---------------------------|
| `luci-app-attendedsysupgrade` | This firmware is released from GitHub, not OpenWrt buildbot. |
| `modemmanager`, `luci-proto-modemmanager` | QModem owns modem management; ModemManager can race QModem for modem devices. |
| `luci-proto-3g` | Legacy AT/PPP path is not the intended path for this M.2 QMI/MBIM board. |
| `luci-app-qmodem`, `luci-app-qmodem-ttlfw4`, `luci-app-qmodem-sms` | The build uses QModem Next and QModem monitor instead. |
| `kmod-crypto-eip` | Vendor crypto accelerator module is disabled by seed config. |

## Feed configuration

Feed pins are tracked in:

```text
feeds.conf.default
```

The file includes:

- OpenWrt packages feed.
- OpenWrt LuCI feed.
- OpenWrt routing feed.
- OpenWrt telephony feed.
- OpenWrt video feed.
- ImmortalWrt package and LuCI overlay feeds.
- FUjr/QModem feed.

The build wrapper installs feeds with:

```sh
./.buildenv/build.sh feeds
```

During feed installation, `.buildenv/build.sh` removes selected unused ImmortalWrt overlay LuCI apps from `package/feeds/iwrt_luci/` to avoid unwanted recursive Kconfig selections.

## Board profile configuration

The image profile for this board is in:

```text
target/linux/mediatek/image/filogic.mk
```

The `Device/zbtlink_zbt-z8803be` profile sets:

- Vendor: `Zbtlink`
- Model: `ZBT-Z8803BE`
- DTS: `mt7988a-zbtlink-zbt-z8803be`
- Supported compatibility: `zbtlink,zbt-z8803be,mt7988a-nand`
- Output image: `sysupgrade.bin`

## Device tree configuration

The device tree is:

```text
target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts
```

It models:

- Board compatible strings.
- Status, WAN, power, `5g1`, and `5g2` LEDs.
- Reset and WPS buttons.
- GPIO exports for modem slot power and SIM mux.
- SFP cage using `i2c2`.
- PWM fan with seven cooling levels.
- GPIO watchdog.
- SPI-NAND fixed partitions and UBI firmware volume.

The Factory partition exposes wired MAC cells used by the board DTS:

| Interface | Factory offset |
|-----------|----------------|
| `gmac0` | `0xffff4` |
| `gmac1` | `0xffffa` |
| `gmac2` | `0xfffee` |

## Network defaults

The board network mapping is in:

```text
target/linux/mediatek/filogic/base-files/etc/board.d/02_network
```

For this board it seeds:

```text
LAN: lan0 lan1 lan2
WAN: eth1 eth2
```

WAN and cellular failover defaults are applied by:

```text
target/linux/mediatek/filogic/base-files/etc/uci-defaults/32-zbt-z8803be-wan-failover
```

Key values:

| UCI path | Value |
|----------|-------|
| `network.wan.metric` | `10` |
| `network.wan6.metric` | `10` |
| `network.wan.defaultroute` | `1` |
| `network.wan.peerdns` | `0` |
| `network.wan_sfp.proto` | `dhcp` |
| `network.wan_sfp.metric` | `9` |
| `network.wan_sfp.defaultroute` | `1` |
| `network.wan_sfp.peerdns` | `0` |
| `network.wan_sfp6.metric` | `9` |
| `network.4_1.proto` | `none` |
| `network.4_1.device` | `wwan0` |
| `network.4_1.ifname` | `wwan0` |
| `network.4_1.metric` | `200` |
| `network.4_1.peerdns` | `0` |
| `network.4_1v6.proto` | `none` |
| `network.4_1v6.device` | `wwan0` |
| `network.4_1v6.metric` | `200` |

The same script ensures `wan_sfp`, `wan_sfp6`, `4_1`, and `4_1v6` are present in the firewall `wan` zone network list.

## DNS defaults

DNS defaults are split across multiple uci-default scripts:

| File | Role |
|------|------|
| `32-zbt-z8803be-wan-failover` | Sets `peerdns=0` on wired IPv4 WANs, seeds wired/cellular metrics, and keeps extra uplinks in the `wan` firewall zone. |
| `40-zbt-qmodem-dns-suppress` | Suppresses QModem DNS injection. |
| `80-zbt-z8803be-dns-cache` | Configures dnsmasq cache and fixed upstream resolvers. |

`80-zbt-z8803be-dns-cache` configures dnsmasq with:

| Option | Value |
|--------|-------|
| `dhcp.@dnsmasq[0].cachesize` | `10000` |
| `dhcp.@dnsmasq[0].noresolv` | `1` |
| `dhcp.@dnsmasq[0].server` | `1.1.1.1`, `1.0.0.1`, `8.8.8.8`, `8.8.4.4` |

The DNS list is intentionally deterministic; post-flash configuration can replace it if the deployment requires different resolvers.

## WiFi defaults

WiFi defaults are configured by:

```text
target/linux/mediatek/filogic/base-files/etc/uci-defaults/72-zbt-z8803be-wifi
```

Device-level defaults:

- Set every radio country to `PH`.
- Set every radio `cell_density=0`.
- Delete per-radio `txpower`, `min_tx_power`, `channels`, and `scan_list` clamps.
- Enable every radio.

Interface-level defaults:

- AP mode.
- Network `lan`.
- WPA3-SAE encryption.
- Starter key `12345678`.
- PMF required via `ieee80211w=2`.
- MLO disabled by default.

Band defaults:

| Band | Channel | HT mode |
|------|---------|---------|
| 2.4 GHz | `11` | `EHT20` |
| 5 GHz | `149` | `EHT80` |
| 6 GHz | `37` | `EHT160` |

## Modem monitor defaults

QModem monitor defaults are applied by:

```text
target/linux/mediatek/filogic/base-files/etc/uci-defaults/48-zbt-qmodem-monitor-defaults
```

The monitor contract is:

| UCI option | Value |
|------------|-------|
| `monitor_enabled` | `1` |
| `monitor_method` | `curl` |
| `monitor_http_url` | `http://142.250.23.94/generate_204` |
| `monitor_interval` | `30` |
| `monitor_threshold` | `10` |
| `qmodem.main.zbt_monitor_cooldown` | `300` |
| `monitor_action` | `run_scripts` |
| `script` | `/usr/sbin/zbt-modem-reboot-guard` |

The service is enabled with `/etc/init.d/qmodem_monitor enable` by the same script.

## GPIO switches

LuCI switch defaults are seeded by:

```text
target/linux/mediatek/filogic/base-files/etc/board.d/03_gpio_switches
```

For this board:

| Switch | Label | Default |
|--------|-------|---------|
| `5g1` | `Power 5G1 modem slot` | `1` |
| `5g2` | `Power 5G2 modem slot` | `0` |
| `sim1` | `SIM1 slot active (off = SIM2 slot)` | `1` |

## Local application runtime storage

The local monitoring applications intentionally write runtime history to tmpfs under `/var/log`:

| App | Runtime path |
|-----|--------------|
| `luci-app-zbt-temperature` | `/var/log/zbt-temperature/readings.csv` |
| `luci-app-zbt-modem-events` | `/var/log/zbt-modem-events/events.csv` |

This keeps current-boot telemetry available without creating persistent overlay flash writes.
