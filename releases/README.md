# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **ZBT source commit:** `ac82dfb52a`
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
5f48b4146e1715363bacbe260dd566aaf1c3c637a5b75192085cec5eccca3f0c  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
5aadce77d747d3de905d8bf2dd9f416ea04917602b722000a041cad96f1c88bf  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
dce37b7ad0489a3785cb2bbab54f4922049bcea978e20ab54fd2b080e2bb1806  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
424da7175ed3728e7482b1c2233d9751d1102328f36ee79f9afe842d6d30747f  sha256sums
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
