# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.016
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `c82f2724f5`
- **Kernel:** `6.18.34`
- **Build revision:** `r34764-819875e2d1`
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
```

Do not upload `REDDIT_POST.md`.

## Current checksums

```text
563436090b583af71c60abaff86d08dadc048ab4ab45479acc96aa967d2d4c5d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
6b417afd3de82f06d8279f9748e9dd135168b0deeefb8f571c02288af1687f3b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
8f6ed9bfc98222735d883fab1c0f6c31bfac0fad0dd5ff928d32eae877bd2072  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
f226f8d9be2855d6fdb30a9a54e60f2cdc19028abecca8ba46262f184dfc5bc8  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
4b36ec5747ddf223b41ddf41f84e631882f8db2f9ba449ef4cf336f4bfe42465  version.buildinfo
eb2e3d319c6ee3cfc73b1df80b9a7125cb3c5bf65feb667dfd3d3dc79dda1fb3  RELEASE_NOTES.md
```

## Publish

```sh
TAG=v25.12.016
TITLE="ZBT-Z8803BE OpenWrt main / kernel 6.18.34 - dual wired WAN defaults for issue #7"

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
  --latest \
  --title "$TITLE" \
  --notes-file releases/RELEASE_NOTES.md
```
