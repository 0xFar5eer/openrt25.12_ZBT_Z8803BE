# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** `r32802-f505120278`
- **ZBT source commit:** `1684bdf309`
- **Kernel:** `6.12.74`

Firmware binaries in this folder are gitignored. Upload them to GitHub Releases.

## Assets to publish

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

Do not upload `REDDIT_POST.md`.

## Current checksums

```text
82c478cda5d033b829e9445b7d1e54e167f2373d74856fb826a49418130ff963  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
0b33bc33be11bfb76045746194f781df4d7af4624b92cece56439b561488e0bc  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
a1333b907c7c2f21924ea7d1aa3d5e9e6a48d1f483a463f8c94c97f9d8e81690  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
4208dac8453f813ed93d1a7ae5dd395213747a707cd93a7b6c22abaa41d1d9aa  sha256sums
```

## Publish

```sh
git tag -a v25.12.2-1-zbt8803be -m "ZBT-Z8803BE OpenWrt 25.12.2 stable port"
git push origin 25.12
git push origin v25.12.2-1-zbt8803be

gh release create v25.12.2-1-zbt8803be \
  releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin \
  releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin \
  releases/openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest \
  releases/sha256sums \
  releases/config.buildinfo \
  releases/feeds.buildinfo \
  releases/version.buildinfo \
  releases/RELEASE_NOTES.md \
  releases/RELEASE_NOTES.zh-CN.md \
  --latest \
  --title "ZBT-Z8803BE OpenWrt 25.12.2 stable port" \
  --notes-file releases/RELEASE_NOTES.md
```
