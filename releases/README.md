# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-5-zbt8803be`
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
36cd47c0579876a24343aaea6bc4f8851007bcb5a57c06632b86bd079cbb0d82  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
e18e2f4dc7986646939a44dff1cb422dfc0b10420873b45b073e2dd41835c9d8  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
8d340453b2aad72dfd6f2b0d424d90d09b97168c0c70ec6a90722b3c388420b4  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
c345615d0de8341d7e2d9a86ca1ce05213a9d50bf23eaa1f90439b532861b44e  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## Publish

```sh
git tag -a v25.12.2-5-zbt8803be -m "ZBT-Z8803BE OpenWrt v25.12.2-5-zbt8803be maintenance release"
git push origin 25.12
git push origin v25.12.2-5-zbt8803be

gh release create v25.12.2-5-zbt8803be \
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
  --title "ZBT-Z8803BE OpenWrt v25.12.2-5-zbt8803be maintenance release" \
  --notes-file releases/RELEASE_NOTES.md
```
