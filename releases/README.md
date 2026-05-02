# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** `r32802-f505120278`
- **ZBT source commit:** `6d558aa9e7`
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
6c93a578fa20b70c2928b22a65ae9efeae40dc83fe90d860f3b37cd61f7ac4e6  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
af82246f539fdbf682de69bfca86df5f1d3d660abdbdbbb7a29d6b1703f0bb62  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f41ebb5fa5de5e6b2d890b482f2c9e0cf8e65dbe1423521eb265f319c806c0d0  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
9347720eb2bcacdc3dc94efa04b73015251d1acbfaa8c9f74fc41f0f0561a999  sha256sums
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
