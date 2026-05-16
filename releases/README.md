# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.5-zbt8803be-main6.18
- **OpenWrt base:** current OpenWrt `main` / `r32860-f96b44fbd4`
- **Kernel:** `6.18.28`
- **Build output:** `output/mediatek/filogic`

Firmware binaries are gitignored. Upload the final validated assets to GitHub Releases.

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
5253300b23ef2604d646a9982b448a0d2c41b02f320fd4a58c52e37525be719f  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
31719cefe6ce1dad70670a0f3613e2f85c96311bb180453db1fbc40dfba9342e  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
0a83381413f1c9ff287317b5edc8fb771861d22590f28090b4f615a7d8a1026d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
1841812800da9039cab6ca0bd827f2462951c00e367b23650efe6770ac4dd7dd  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
08481bee00f9c0e2ad1019ee69589f92571e6129a86aaa6b93ce900e8939c3c1  version.buildinfo
```

## Publish

```sh
TAG=v25.12.5-zbt8803be-main6.18
TITLE="ZBT-Z8803BE OpenWrt main kernel 6.18 USB tethering release"

git tag -a "$TAG" -m "$TITLE"
git push origin HEAD
git push origin "$TAG"

gh release create "$TAG" \
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
  --title "$TITLE" \
  --notes-file releases/RELEASE_NOTES.md
```
