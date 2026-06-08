# Corrected Router Reflash / Setup / DTS Validation Plan

This file is the release gate for the local unreleased `v25.12.2-6-zbt8803be` test build. The previous generic firmware checks are considered covered; use this plan for the router reflash, setup, live DTS validation, and any DTS fix/rebuild/retest loop.

No router action should run until the explicit green flag is given.

## PR Review Traceability

- **`@hauke`: direct DTS include.** Fixed by switching from `mt7988a-rfb.dts` to `mt7988a.dtsi` and restoring required board nodes. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213293080>.
- **`@hauke`: legacy compatible handling.** Fixed by removing `zbtlink,zbt-z8803be,mt7988a-nand` from DT `compatible` while keeping it in `SUPPORTED_DEVICES`. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213257972>.
- **`@hauke`: fan thermal cell.** Fixed by removing the unused `#thermal-sensor-cells` property from the `pwm-fan` node. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213303728>.
- **`@hauke`: label MAC target.** Fixed by setting `label-mac-device = &gmac0`. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213304880>.
- **`@hauke`: WiFi reset placement.** Fixed by documenting that the MediaTek Gen3 PCIe driver handles `wifi-reset-gpios` and that it must remain on `&pcie3` because `pcie3` probes before `pcie0`. Links: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213261930>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3213309837>.
- **`@joelinux60`: wired MAC cells and label MAC.** Kept explicit NVMEM cell index `0` for `gmac0` / `gmac1` / `gmac2` and verified no random MAC fallback; label MAC points to `gmac0`. Links: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206902888>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206909949>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3206915357>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3210123646>.
- **`@openwrt-ai`: review confirmation and WiFi reset wording.** Confirmed the DTS cleanup addressed earlier feedback and restored the empirical explanation for keeping reset on `&pcie3`. Links: <https://github.com/openwrt/openwrt/pull/23053#pullrequestreview-4258463777>, <https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206703>.
- **`@openwrt-ai`: modem slot asymmetry.** The DTS already documents why `5g1` is powered by default and `5g2` is off by default. Link: <https://github.com/openwrt/openwrt/pull/23053#discussion_r3214206797>.
- **`@pttuan`: RT5190A / CPUFreq confirmation.** Local CPUFreq fix follows the restored RT5190A CPU/CCI `proc-supply` path and matches `@pttuan`'s reported available frequencies. Links: <https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414098516>, <https://github.com/openwrt/openwrt/pull/23053#issuecomment-4414354486>.
- **Local-only fix: WiFi reset during preserved-config sysupgrade.** Root cause was this firmware's `72-zbt-z8803be-wifi` uci-defaults script overwriting `/etc/config/wireless`; fixed by exiting early when custom non-`OpenWrt` SSIDs are present.

## Correct Host Flow

Before reflash, the current router is available at:

```text
3fl.lan
```

After reflash, before bootstrap/setup, the router resets to default access:

```text
192.168.1.1
```

Default password:

```text
admin
```

After bootstrap/setup, the router should again be available at:

```text
3fl.lan
```

## Phase 0: Hard Gate

Do nothing to the router until this exact approval is given:

```text
green flag, flash router
```

Do not flash the router until the explicit green flag is given. Publishing release assets before the reflash is allowed when the goal is to make the image available for the reflash.

## Phase 1: Local Artifact Preflight

Run from:

```text
/Users/numwan/Documents/Remix/bitbucket/openrt-zbt8803be
```

### 1.1 Confirm image

```sh
ls -lh releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
sha256sum releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Expected sysupgrade hash:

```text
373420c401352f4890c4480de24d333174f8decdae5d3631d58e91fc0ffeed0b
```

### 1.2 Confirm archive structure

```sh
tar -tf releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Expected:

```text
sysupgrade-zbtlink_zbt-z8803be/
sysupgrade-zbtlink_zbt-z8803be/CONTROL
sysupgrade-zbtlink_zbt-z8803be/kernel
sysupgrade-zbtlink_zbt-z8803be/root
```

### 1.3 Confirm staged checksums

```sh
cd releases
sha256sum -c sha256sums --ignore-missing
```

Expected:

```text
config.buildinfo: OK
feeds.buildinfo: OK
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin: OK
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin: OK
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest: OK
version.buildinfo: OK
```

### 1.4 Confirm metadata intent

```sh
grep -n 'SUPPORTED_DEVICES\|DEVICE_COMPAT_VERSION\|DEVICE_COMPAT_MESSAGE' target/linux/mediatek/image/filogic.mk
```

Expected for `zbtlink_zbt-z8803be`:

```make
SUPPORTED_DEVICES += zbtlink,zbt-z8803be,mt7988a-nand
```

Expected absent for this device:

```make
DEVICE_COMPAT_VERSION
DEVICE_COMPAT_MESSAGE
```

## Phase 2: Pre-Flash Baseline

Current router access before reflash:

```text
3fl.lan
```

### 2.1 Confirm SSH access

```sh
ssh root@3fl.lan true
```

### 2.2 Capture identity

```sh
ssh root@3fl.lan 'cat /tmp/sysinfo/board_name; cat /tmp/sysinfo/model; ubus call system board'
```

### 2.3 Capture boot/kernel baseline

```sh
ssh root@3fl.lan 'uptime; dmesg | tail -200'
```

### 2.4 Capture hardware baseline

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "pcie|pci |mt7996|mt76|wifi|usb|xhci|sfp|gmac|sgmii|usxgmii|phy|regulator|rt5190|cpufreq|opp|thermal|fan|pwm|ubi|ubifs|nmbm|nand|bad block|ecc"'
```

### 2.5 Capture network baseline

```sh
ssh root@3fl.lan 'ip link; ip addr; ip route; ubus call network.interface.lan status; ubus call network.interface.wan status'
```

### 2.6 Capture service baseline

```sh
ssh root@3fl.lan '/etc/init.d/rpcd status; /etc/init.d/uhttpd status; /etc/init.d/network status'
ssh root@3fl.lan '/etc/init.d/qmodem_monitor status 2>/dev/null; /etc/init.d/wrtbwmon status 2>/dev/null; /etc/init.d/zbt_temperature status 2>/dev/null'
```

## Phase 3: Flash Router

Use current pre-flash hostname:

```text
3fl.lan
```

### 3.1 Upload image

```sh
scp releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@3fl.lan:/tmp/v25.12.2-6-zbt8803be-sysupgrade.bin
```

### 3.2 Verify uploaded hash

```sh
ssh root@3fl.lan 'sha256sum /tmp/v25.12.2-6-zbt8803be-sysupgrade.bin'
```

Expected:

```text
373420c401352f4890c4480de24d333174f8decdae5d3631d58e91fc0ffeed0b
```

### 3.3 Run sysupgrade

```sh
ssh root@3fl.lan 'sysupgrade /tmp/v25.12.2-6-zbt8803be-sysupgrade.bin'
```

Expected:

- **No compatibility blocker:** no `DEVICE_COMPAT_VERSION` blocker.
- **No force path:** no need for `--force-compat-version-check`.
- **Compatibility accepted:** upgrade is accepted through `SUPPORTED_DEVICES`.
- **If refused:** stop and capture the exact warning.

## Phase 4: First Boot After Reflash

After reflash, the router should return at default address:

```text
192.168.1.1
```

Default password:

```text
admin
```

Do not use `3fl.lan` yet.

### 4.1 Wait for ping

```sh
ping 192.168.1.1
```

Wait until replies are stable.

### 4.2 Wait for SSH

```sh
ssh root@192.168.1.1 true
```

Password if prompted:

```text
admin
```

### 4.3 Mandatory 3-minute stabilization wait

After both ping and SSH are up:

```sh
sleep 180
```

Reason:

- **First boot scripts:** allow OpenWrt first boot work to settle.
- **UCI defaults:** allow defaults to finish.
- **PCIe/WiFi enumeration:** allow MT7996 and radios to initialize.
- **USB modem hotplug:** allow modem enumeration.
- **SFP/I2C probing:** allow SFP-related probing.
- **LuCI/rpcd startup:** allow management services to start.
- **qmodem/wrtbwmon initialization:** allow local services to settle.

### 4.4 Confirm WiFi before setup

```sh
ssh root@192.168.1.1 'wifi status'
ssh root@192.168.1.1 'iw dev'
ssh root@192.168.1.1 'dmesg | grep -Ei "mt7996|mt76|wlan|radio|eeprom|firmware"'
```

Expected:

- **Radios exist:** WiFi radios are present.
- **No MT7996 regression:** no PCIe/train/eeprom failure.

## Phase 5: Bootstrap and Setup

Setup repo:

```text
/Users/numwan/Documents/Remix/bitbucket/wrt
```

Target before setup completes:

```text
192.168.1.1
```

Default password:

```text
admin
```

### 5.1 Run setup phases in order

Run:

```text
001-bootstrap.sh
...
014-reboot-verify.sh
```

### 5.2 Expected setup result

After bootstrap/setup scripts complete, hostname should be:

```text
3FL
```

Router should again be accessible at:

```text
3fl.lan
```

### 5.3 Capture setup output

Save setup logs.

Watch for:

```text
failed
error
timeout
permission denied
no such file
ubus call failed
rpcd
uhttpd
qmodem
wrtbwmon
wifi
dns
```

## Phase 6: Post-Setup Access Switch

Primary target now:

```text
3fl.lan
```

Fallback only if DNS/hostname is not ready:

```text
192.168.1.1
```

### 6.1 Confirm hostname and identity

```sh
ssh root@3fl.lan 'hostname; cat /tmp/sysinfo/board_name; cat /tmp/sysinfo/model'
```

Expected hostname:

```text
3FL
```

Expected board name:

```text
zbtlink,zbt-z8803be
```

### 6.2 Service checks

```sh
ssh root@3fl.lan '/etc/init.d/rpcd status'
ssh root@3fl.lan '/etc/init.d/uhttpd status'
ssh root@3fl.lan '/etc/init.d/network status'
ssh root@3fl.lan '/etc/init.d/qmodem_monitor status 2>/dev/null'
ssh root@3fl.lan '/etc/init.d/zbt_qmodem_watchdog status 2>/dev/null'
ssh root@3fl.lan '/etc/init.d/wrtbwmon status 2>/dev/null'
ssh root@3fl.lan '/etc/init.d/zbt_temperature status 2>/dev/null'
```

## Phase 7: Final Reboot

Use:

```text
3fl.lan
```

### 7.1 Reboot

```sh
ssh root@3fl.lan 'reboot'
```

### 7.2 Wait for ping

```sh
ping 3fl.lan
```

Fallback:

```sh
ping 192.168.1.1
```

### 7.3 Wait for SSH

```sh
ssh root@3fl.lan true
```

Fallback:

```sh
ssh root@192.168.1.1 true
```

### 7.4 Mandatory 3-minute wait

After ping and SSH are both up:

```sh
sleep 180
```

Then:

```sh
ssh root@3fl.lan 'wifi status; iw dev'
```

## Phase 8: Live DTS / Device-Tree Validation

Use:

```text
3fl.lan
```

### 8.1 Compatible string

```sh
ssh root@3fl.lan 'tr "\0" "\n" < /proc/device-tree/compatible'
```

Expected includes:

```text
zbtlink,zbt-z8803be
mediatek,mt7988a
```

Expected not to include:

```text
zbtlink,zbt-z8803be,mt7988a-nand
```

### 8.2 Board name

```sh
ssh root@3fl.lan 'cat /tmp/sysinfo/board_name; cat /tmp/sysinfo/model'
```

Expected:

```text
zbtlink,zbt-z8803be
```

### 8.3 Label MAC alias

```sh
ssh root@3fl.lan 'find /proc/device-tree/aliases -maxdepth 1 -type f -print -exec sh -c "echo -n \"{}: \"; tr \"\0\" \"\n\" < \"{}\"" \;'
```

Look for:

```text
label-mac-device
```

Expected target should correspond to `gmac0`.

## Phase 9: Boot Log Health Gate

### 9.1 Critical error scan

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "fail|failed|error|timeout|deferred|probe|panic|oops|call trace|reset|hang|not found|invalid"'
```

Manually inspect anything related to:

```text
pcie
mt7996
mt76
gmac
phy
sfp
usb
xhci
regulator
cpufreq
thermal
pwm
ubi
ubifs
nmbm
nand
```

### 9.2 Kernel warnings

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "warning|warn|taint|backtrace"'
```

## Phase 10: NAND / UBI / Overlay Integrity

### 10.1 MTD layout

```sh
ssh root@3fl.lan 'cat /proc/mtd'
```

Expected important partitions:

```text
BL2
u-boot-env
Factory
FIP
ubi
```

### 10.2 UBI/UBIFS health

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "ubi|ubifs|nmbm|nand|bad block|ecc|bitflip|read error|write error"'
ssh root@3fl.lan 'ubinfo -a 2>/dev/null || true'
```

Expected:

- **No fatal storage errors:** no new fatal UBI/UBIFS errors.
- **No suspicious NAND errors:** no suspicious ECC/read/write failures.

### 10.3 Overlay health

```sh
ssh root@3fl.lan 'df -h /overlay; mount | grep overlay'
```

Expected:

- **Overlay mounted:** overlay is mounted read-write.
- **Free space reasonable:** enough space remains after setup.

## Phase 11: CPU / Regulator / OPP Validation

This verifies the restored old RFB RT5190A/CPU regulator nodes are binding correctly.

### 11.1 Regulator/cpufreq logs

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "cpufreq|opp|regulator|rt5190|vproc|proc-supply|voltage|failed"'
```

### 11.2 CPU frequency state

```sh
ssh root@3fl.lan 'for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor; do echo "$f:"; cat "$f" 2>/dev/null || true; done'
```

### 11.3 Thermal under light runtime

```sh
ssh root@3fl.lan 'cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null'
```

Decision:

- **Good:** no regulator/OPP/cpufreq failures and available frequencies include `800000 1100000 1500000 1800000`.
- **Bad:** CPU frequency is missing with bad OPP/regulator logs.
- **Next step:** recheck RT5190A probe, I2C0 pinctrl, and CPU/CCI `proc-supply`.
- **DTS rule:** keep RT5190A nodes only with live CPUFreq validation.

## Phase 12: PCIe / WiFi Reset Timing

### 12.1 PCIe domains and devices

```sh
ssh root@3fl.lan 'find /sys/bus/pci/devices -maxdepth 1 -type l -print 2>/dev/null'
ssh root@3fl.lan 'for d in /sys/bus/pci/devices/*; do echo "### $d"; cat "$d/vendor" "$d/device" 2>/dev/null; done'
```

If `lspci` exists:

```sh
ssh root@3fl.lan 'lspci -nn 2>/dev/null || true'
```

### 12.2 PCIe/WiFi logs

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "pcie|pci |mt7996|mt76|wifi-reset|reset-gpio|eeprom|firmware"'
```

### 12.3 WiFi runtime

```sh
ssh root@3fl.lan 'iw dev'
ssh root@3fl.lan 'wifi status'
ssh root@3fl.lan 'ubus call network.wireless status 2>/dev/null || true'
```

Expected:

- **Endpoint present:** MT7996 PCIe endpoint appears.
- **Radios present:** radios appear.
- **No reset race:** no reset timing regression.
- **EEPROM OK:** no EEPROM load failure.
- **Firmware stable:** no firmware crash/restart loop.

## Phase 13: Ethernet / Switch / PHY / MAC

### 13.1 Interface existence

```sh
ssh root@3fl.lan 'ip -br link'
```

Expected:

```text
lan0
lan1
lan2
eth1
eth2
```

### 13.2 Network config status

```sh
ssh root@3fl.lan 'ubus call network.interface.lan status'
ssh root@3fl.lan 'ubus call network.interface.wan status'
```

### 13.3 PHY/switch logs

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "gmac|switch|mt753|phy|mdio|sgmii|usxgmii|link"'
```

### 13.4 MAC address validation

```sh
ssh root@3fl.lan 'for i in lan0 lan1 lan2 eth1 eth2; do echo "$i $(cat /sys/class/net/$i/address 2>/dev/null)"; done'
```

Expected:

- **Valid MACs:** MAC addresses are valid.
- **No random fallback:** no random locally-administered fallback unless expected.
- **No invalid MACs:** no all-zero or duplicate MACs.

### 13.5 NVMEM source hint

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "nvmem|mac-address|random mac|using random"'
```

Expected:

- **No wired random MACs:** no `using random MAC address` for wired interfaces.

## Phase 14: Label MAC Validation

### 14.1 System board JSON

```sh
ssh root@3fl.lan 'ubus call system board'
```

### 14.2 Compare against physical sticker

Record:

```sh
ssh root@3fl.lan 'for i in lan0 lan1 lan2 eth1 eth2; do echo "$i $(cat /sys/class/net/$i/address 2>/dev/null)"; done'
```

Decision:

- **If sticker matches gmac0/expected interface:** keep `label-mac-device = &gmac0;`.
- **If sticker matches another interface:** update DTS accordingly.

## Phase 15: USB / Modem / GPIO Power

### 15.1 USB enumeration

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "usb|xhci|ttyUSB|cdc|qmi|mbim|wwan"'
ssh root@3fl.lan 'lsusb'
ssh root@3fl.lan 'ls /dev/ttyUSB* 2>/dev/null || true'
```

### 15.2 QModem state

```sh
ssh root@3fl.lan 'uci show qmodem'
ssh root@3fl.lan 'ps w | grep -E "qmodem|modem_monitor" | grep -v grep'
```

### 15.3 GPIO modem/SIM exports

```sh
ssh root@3fl.lan 'ls -l /sys/class/gpio | grep -E "5g1|5g2|sim1"'
```

Expected:

- **5G1 powered:** primary modem slot powered.
- **5G2 off:** secondary modem slot off by default.
- **SIM1 selected:** default SIM line selected.
- **Modem enumerates:** modem appears from powered slot.

### 15.4 Optional modem AT health

If safe and available:

```sh
ssh root@3fl.lan 'sms_tool -d /dev/ttyUSB3 at "AT" 2>/dev/null || sms_tool_q -d /dev/ttyUSB3 at "AT" 2>/dev/null || true'
```

Expected:

```text
OK
```

## Phase 16: SFP / I2C2 / GMAC2

### 16.1 SFP logs

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "sfp|i2c|gmac2|usxgmii|10gbase|in-band"'
```

### 16.2 Interface state

```sh
ssh root@3fl.lan 'ip link show eth2'
ssh root@3fl.lan 'ethtool eth2 2>/dev/null || true'
```

### 16.3 I2C bus presence

```sh
ssh root@3fl.lan 'ls /sys/bus/i2c/devices 2>/dev/null || true'
```

Expected:

- **No SFP probe regression:** no I2C2/SFP probe failure.
- **eth2 exists:** SFP/GMAC2 interface exists.
- **SFP state sane:** module state is sane if a module is inserted.

### 16.4 Dual uplink routing defaults

After a clean first boot, verify generated network sections and metrics:

```sh
ssh root@3fl.lan 'uci -q show network.wan; uci -q show network.wan6; uci -q show network.wan_sfp; uci -q show network.wan_sfp6; uci -q show firewall | grep -E "wan_sfp|4_1"'
```

Expected:

- **RJ45 WAN metrics:** `network.wan.metric='10'` and `network.wan6.metric='10'`.
- **SFP WAN metrics:** `network.wan_sfp.metric='9'` and `network.wan_sfp6.metric='9'`.
- **Firewall membership:** `wan_sfp`, `wan_sfp6`, `4_1`, and `4_1v6` are present in the `wan` zone.

Optional live-link verification:

```sh
ssh root@3fl.lan 'ip -4 route show default; ip -6 route show default 2>/dev/null || true; ubus call network.interface.wan status; ubus call network.interface.wan_sfp status'
```

Expected:

- **Single link works:** whichever wired uplink is physically linked can acquire default routes.
- **SFP preferred when both are up:** if both wired uplinks are active, `wan_sfp` is preferred by metric.
- **No active arbitration assumed:** preference is route-metric based, not internet health-checked failover.

## Phase 17: Fan / Thermal / PWM Cooling

### 17.1 Thermal zones

```sh
ssh root@3fl.lan 'for z in /sys/class/thermal/thermal_zone*; do echo "### $z"; cat "$z/type" "$z/temp" 2>/dev/null; done'
```

### 17.2 Cooling devices

```sh
ssh root@3fl.lan 'for c in /sys/class/thermal/cooling_device*; do echo "### $c"; cat "$c/type" "$c/cur_state" "$c/max_state" 2>/dev/null; done'
```

### 17.3 PWM fan / hwmon

```sh
ssh root@3fl.lan 'find /sys/class/hwmon -maxdepth 3 -type f | grep -Ei "pwm|fan|temp|name" | while read f; do echo "$f: $(cat "$f" 2>/dev/null)"; done'
```

### 17.4 ZBT temperature app

```sh
ssh root@3fl.lan '/usr/sbin/zbt-health-json 2>/dev/null'
ssh root@3fl.lan 'tail -20 /var/log/zbt-temperature/readings.csv 2>/dev/null'
```

Expected:

- **Cooling device exists:** thermal cooling device appears.
- **Fan readable:** fan state can be read.
- **No removed-cell dependency:** no dependency on removed `#thermal-sensor-cells`.
- **Telemetry works:** temperature app logs fan/system/WiFi/modem readings.

## Phase 18: Watchdog / Recovery Safety

### 18.1 GPIO watchdog driver

```sh
ssh root@3fl.lan 'dmesg | grep -Ei "watchdog|wdt|gpio-wdt"'
```

### 18.2 Service watchdogs

```sh
ssh root@3fl.lan '/etc/init.d/zbt_qmodem_watchdog status 2>/dev/null'
ssh root@3fl.lan 'ps w | grep -Ei "watchdog|qmodem_monitor" | grep -v grep'
```

Expected:

- **No reboot loop:** no watchdog panic/reboot loop.
- **Services normal:** qmodem watchdog behaves normally.

## Phase 19: Persistence After Final Reboot

If time allows, reboot once more:

```sh
ssh root@3fl.lan 'reboot'
```

Then:

```sh
ping 3fl.lan
ssh root@3fl.lan true
sleep 180
```

Re-check:

```sh
ssh root@3fl.lan 'cat /tmp/sysinfo/board_name; ip -br link; iw dev; lsusb; dmesg | grep -Ei "failed|error|pcie|mt7996|regulator|cpufreq|usb|sfp|thermal|fan"'
```

This confirms the DTS is stable across multiple boots, not just first boot.

## Phase 20: Public Release / PR Readiness Gate

Good to proceed if all pass:

- **Sysupgrade:** no compat-version blocker.
- **Boot:** flash boot and final reboot succeed.
- **Host flow:** `3fl.lan` before reflash, `192.168.1.1` after reflash, `3fl.lan` after setup.
- **Board identity:** `zbtlink,zbt-z8803be`.
- **Live compatible:** no old DTS compatible in `/proc/device-tree/compatible`.
- **WiFi:** MT7996 enumerates consistently.
- **PCIe:** no train/reset race.
- **Ethernet:** `lan0`, `lan1`, `lan2`, and WAN interfaces are correct.
- **MACs:** no random or duplicate wired MACs.
- **Label MAC:** physical label matches `gmac0`.
- **USB modem:** modem enumerates and qmodem works.
- **SFP:** no I2C/SFP/gmac2 regression.
- **Fan/thermal:** cooling maps and fan telemetry work.
- **CPU/regulator:** no OPP/regulator/cpufreq regression.
- **NAND/UBI:** no new storage integrity errors.
- **Setup:** bootstrap/setup scripts pass.
- **Services/LuCI:** critical pages and services work.

## DTS Fix / Rebuild / Retest Loop

Add DTS fixes only if failures point there.

### Regulator/cpufreq failure

- **Investigate:** confirm RT5190A hardware and PMIC behavior.
- **Fix only if confirmed:** add PMIC/regulator nodes only if hardware confirms it.
- **Candidate inherited nodes:** RT5190A PMIC, fixed regulators, `&i2c0`, CPU/CCI `proc-supply`.

### WiFi/PCIe failure

- **Investigate:** recheck PCIe probe order and reset timing.
- **Likely DTS area:** `wifi-reset-gpios` placement on `&pcie3`.

### Ethernet/SFP failure

- **Investigate:** recheck GMAC/switch/PCS/pinctrl.
- **Likely DTS areas:** `&gmac*`, `&switch`, `&gsw_phy*`, `&gsw_port*`, `gbe*_led0_pins`, `sfp`, `&i2c2`.

### USB modem failure

- **Investigate:** recheck USB PHY/controller enablement and modem power GPIOs.
- **Likely DTS areas:** `&ssusb0`, `&ssusb1`, `&tphy`, `&xsphy`, `gpio-export` modem power pins.

### Thermal/fan failure

- **Investigate:** recheck PWM fan, cooling maps, and thermal trips.
- **Likely DTS areas:** `pwm-fan`, `&pwm`, `&cpu_thermal`.

### MAC mismatch

- **Investigate:** recheck NVMEM offsets/indexes and label MAC target.
- **Likely DTS areas:** `gmac0_mac`, `gmac1_mac`, `gmac2_mac`, `nvmem-cells`, `label-mac-device`.

### Rebuild and repeat

After any DTS fix:

```sh
git diff --check
./.buildenv/build.sh config
./.buildenv/build.sh build
./.buildenv/build.sh extract
```

Then refresh release checksums/docs, reflash, and repeat this validation plan from Phase 1.

## Current Test Build Details

Version:

```text
v25.12.2-6-zbt8803be
```

Sysupgrade:

```text
releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Sysupgrade SHA256:

```text
373420c401352f4890c4480de24d333174f8decdae5d3631d58e91fc0ffeed0b
```

Build logs:

```text
.buildenv/logs/release-20260511-181850-v25.12.2-6-fan-policy-final/build.log
.buildenv/logs/release-20260511-181850-v25.12.2-6-fan-policy-final/extract.log
```

Current release status:

- **Built locally:** yes
- **Artifacts staged:** yes
- **Checksums refreshed:** yes
- **Router flashed:** no, v25.12.2-6 fan-policy image awaits user reflash
- **Live hotfix deployed:** yes, fan-temperature policy deployed and verified live on 3fl.lan; post-replug spot-check was stable; 85C DTS failsafe requires reflash
- **Release publication:** use tag `v25.12.2-6-zbt8803be` and the staged GitHub release assets before user reflash
- **PR updated:** no
