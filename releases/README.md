# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release candidate.

- **Tag:** v25.12.4-zbt8803be-main6.18
- **OpenWrt base:** current OpenWrt `main` / `r303+1-d841179375`
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
dd571dfe6d82d003c9bb73947c93a7d588494c2019e8aca755146871029ec2fb  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
c65dd17640567042ab4349124571df6448362caaf35472644e0e299d7dccf9b7  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
2ae4f56dd79908e5ee37bc98e006bcba66e74a21c4d53b0196f8388cf05c57dc  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
291d52d106f823bb129b0d007b3f7a3fa79bafaac41cdee3e42044aab5efeb36  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
f814ce4b83e191a6148421107142da56b42a1771f191c79f86d2ca3b8918a688  version.buildinfo
```

## Publish

```sh
TAG=v25.12.4-zbt8803be-main6.18
TITLE="ZBT-Z8803BE OpenWrt main kernel 6.18 AdGuard/compat3 release"

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
