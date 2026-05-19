# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.7-zbt8803be-main6.18
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `a7b5bb233f`
- **Kernel:** `6.18.31`
- **Build revision:** `r364-8682ae2528`
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
71984653705e0a1af73a3fc74521bb1e76488f0991d7a478254aae5f40a17a4d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
df09cbf8c926e73eb15b43d057b2ae7b850b47aa15b7e5c365736d409211923b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
a58f638fcd670ba302e810501a6470544cab4f8f1b318595e7e26a2e2fde8a52  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
cf7f42d03a5adbb0b72b4444da0b8c467b360389639bb01c81442761212a7b32  version.buildinfo
```

## Publish

```sh
TAG=v25.12.7-zbt8803be-main6.18
TITLE="ZBT-Z8803BE OpenWrt main / kernel 6.18.31 - source build fix + Aquantia SFP+"

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
