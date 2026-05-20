# ZBT-Z8803BE OpenWrt main / kernel 6.18.28 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.8-zbt8803be-main6.18`
- **Kernel:** `6.18.28`
- **Build revision:** `r32875-11fafa0ecd`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.7

- **Removed crash-forensics from the firmware docs/config path.** The public image and firmware configuration no longer carry stale `zbt-crash-forensics` references.
- **Updated Traffic Statistics guidance.** The wrtbwmon LuCI setup page now warns that per-client nftables accounting may reduce Internet/LAN throughput on some routers, and recommends enabling it only temporarily to identify over-consuming clients, domains, or global traffic.
- **Crash root cause is now treated as power/voltage related.** The private setup/live crash-forensics layer has been removed because the router crash investigation is no longer needed.

## Validation

- Full Docker rebuild completed as `r32875-11fafa0ecd` after freeing Docker disk space and rebuilding stale Python host PGO artifacts.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest/config scan confirmed no `zbt-crash`, `zbt_crash`, or `crash-forensics` references.
- Manifest includes:

```text
kernel - 6.18.28~1d3ce6949449162367278daa4d610965-r1
kmod-nft-netdev - 6.18.28-r1
kmod-phy-aquantia - 6.18.28-r1
wrtbwmon - 0.36-r1
luci-app-wrtbwmon - 2.0.13-r1
```

## Checksums

```text
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
373d7a4c3cf2994fec81e5fb36659beccec74371e807ee6bb3ba2d54b8c1e82c *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
b3075c2e2b93ccab8e4f4c1d959387cfb346c412e8f4a3ffd31ecbce9fb4e831 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
64005a4f4609cf35481b198c0a345107326114aa4a1cddbd0b4dd8203b78e703 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2a9c14559ba2743187a21e3e521b08b1f0b95e3773df0aeae6404892b25b0023 *version.buildinfo
```

## Flash

Preserve settings and app history:

```sh
scp openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@<router>:/tmp/
ssh root@<router> 'sysupgrade -v /tmp/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin'
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
