# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-7-zbt8803be`
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
a3c35330d09649e56e4ad29b9d6dcbabe3ac3983989e35e54a7d6f3fb3889d7a  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
4f9c90aebc44ddd9aa6c2594a4d55ad2fa7855492c2381946902dc4f126e6c90  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
c755428ec8874006d1572f2b0a457ae61092d1907119ac01ea5e9c46ad443e4d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
22cd03fcfd73f645c0be48165b4449e5768fef147908db51dcb8a25db88b98a5  sha256sums
43a7d0d006229a8c60a42915e59c7220623778508f18387be37dc8d79ea15777  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## Publish

```sh
git tag -a v25.12.2-7-zbt8803be -m "ZBT-Z8803BE OpenWrt v25.12.2-7-zbt8803be speedtest maintenance release"
git push origin 25.12
git push origin v25.12.2-7-zbt8803be

gh release create v25.12.2-7-zbt8803be \
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
  --title "ZBT-Z8803BE OpenWrt v25.12.2-7-zbt8803be speedtest maintenance release" \
  --notes-file releases/RELEASE_NOTES.md
```
