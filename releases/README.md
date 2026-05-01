# Release staging

Local staging folder for the current **ZBTLink ZBT-Z8803BE** firmware release.

- **Tag:** `v34156-1-zbt8803be`
- **Build:** `r34156+1-f2ce3e7c4a`
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
0a6c1f5f0520acdb7e528c5c45e92716982dd3b7137132dcd82aab7c45943035  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
5a27c934a088e7e27796c8b628ee66f8211a4b5604dbceeb7f58ce31271b2738  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
9e3bc8886ab24ef54c2c096ff32e81a14f5527e5138601967deeb8893a213507  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## Publish

```sh
git tag -a v34156-1-zbt8803be -m "ZBT-Z8803BE r34156 (first-flash fixes: modem auto-dial, DNS upstream, youtubeUnblock NFQUEUE auto-load)"
git push origin zbt8803_main
git push origin v34156-1-zbt8803be

gh release create v34156-1-zbt8803be \
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
  --title "ZBT-Z8803BE OpenWrt r34149 (fix WWAN firewall zone binding on first boot)" \
  --notes-file releases/RELEASE_NOTES.md
```
