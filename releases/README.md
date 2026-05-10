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
5870b7747b97d95e469cbed539db8701346fee454529dd9dfec732520cbd9f55  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
6ad6a892ad29b636313521c62235618dd68ee2d7fc3d5a7d4004b8905c920047  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
384713d6d6db10e67f7221ee2cd8bbeb91385406dbc747fe305e4a6ec894c1bb  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
cfea01de20bb0c227723be17f3f38c575839d55ccce926ed94202aecbef378c9  sha256sums
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
