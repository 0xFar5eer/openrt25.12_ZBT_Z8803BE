# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** `r32802-f505120278`
- **ZBT source commit:** `395adbe584`
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
1bdbdf0dbdb5f59fd85df8b481fa8786d7bb5609731c30738fad3df4d7671690  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
da05844b3fc62cd5fdd263ad791c3d42a1e19a6399fc10aee7711823c72a6db5  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
a1333b907c7c2f21924ea7d1aa3d5e9e6a48d1f483a463f8c94c97f9d8e81690  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2646c6753d9c8158a87bbbfe0b60e7f97372040820cfbfb14a2b4767e8e146ea  sha256sums
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
