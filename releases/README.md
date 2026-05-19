# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.6-zbt8803be-main6.18
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `a7b5bb233f`
- **Kernel:** `6.18.31`
- **Build revision:** `r363-abb692387f`
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
f8dff652e42cba5dcfd6dcc33ca5541c00ec6a81b44bdbe8383c928396d9c5d2  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
73bd990b5d28d3b41c2a810614315e30e3dc1d67ad2df5f199639166603d6686  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
8dec48f3335c89261da766ebd3ac93b39f7bcd85ba8c6bee9b8b76b72cc94fac  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
5132da1cdd420bb0b3b0891406be2b830d0518435ff9dbfb767454176c9bda85  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05ac68fd62126cfe75fb4d8280382f7a5bec4cc1d6df5979b6d8a4b4c5d02d98  version.buildinfo
```

## Publish

```sh
TAG=v25.12.6-zbt8803be-main6.18
TITLE="ZBT-Z8803BE OpenWrt main / kernel 6.18.31 - wrtbwmon netdev refactor"

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
