# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-2-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
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
45dfdda0204eb549a1dc127c3ef3ef2ef4c0be1ea3a048fca6925937641e5281  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
ccc242c1a7fb3ab4b2864f7b87654a7d1576aeec90791f5c72ed9b5b95ed7970  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f2f4454deafb186712bf11a153dbb43694f0d6bd3d5c215313d670acff300df1  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
c4898a1a2760b72c6eab640c5bfba9b08c5cf239571212b2011e815be4fa1db0  sha256sums
```

## Publish

```sh
git tag -a v25.12.2-2-zbt8803be -m "ZBT-Z8803BE OpenWrt 25.12.2 maintenance release"
git push origin 25.12
git push origin v25.12.2-2-zbt8803be

gh release create v25.12.2-2-zbt8803be \
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
  --title "ZBT-Z8803BE OpenWrt 25.12.2 maintenance release" \
  --notes-file releases/RELEASE_NOTES.md
```
