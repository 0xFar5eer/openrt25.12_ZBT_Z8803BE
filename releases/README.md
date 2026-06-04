# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.15-zbt8803be-main6.18
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `c82f2724f5`
- **Kernel:** `6.18.34`
- **Build revision:** `r34651-08fc94e13c`
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
74f8cd372e5c41942ce281942a4114813bb2de5830156d0e4dd172324c2cd2a7  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
a2482fcec710bdffd8ccf1881f96dd4d9d8fedb8e2cbdadbd0f4b521cf036f44  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
9cc19cf62dabdca83cb107b941465ee49ea19d750e3108f0664f241f8cf02e67  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
f226f8d9be2855d6fdb30a9a54e60f2cdc19028abecca8ba46262f184dfc5bc8  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
2503f023144e11bb00097a4927c8af2cef1c7c8100685e3f97a99465211e006f  version.buildinfo
89048f7ef7c907e2974047b55559b0bdb32b7b3a39ad5cba088c4d79792c5df4  RELEASE_NOTES.md
```

## Publish

```sh
TAG=v25.12.15-zbt8803be-main6.18
TITLE="ZBT-Z8803BE OpenWrt main / kernel 6.18.34 - latest upstream rebase"

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
