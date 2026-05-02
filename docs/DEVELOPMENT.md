# Development

This document describes how to work on this firmware repository without disturbing the OpenWrt build tree or accidentally committing generated artifacts.

## Branch and release model

The active firmware branch is `25.12`. The public release tag is `v25.12.2-1-zbt8803be`.

Release documentation lives in:

```text
releases/README.md
releases/RELEASE_NOTES.md
releases/RELEASE_NOTES.zh-CN.md
```

The root READMEs provide public-facing installation and build instructions:

```text
README.md
README.zh-CN.md
```

## Development workflow

A typical firmware change follows this loop:

1. Edit board defaults, packages, LuCI apps, or seed config.
2. Run syntax checks for modified shell and JavaScript files.
3. Run `.buildenv/build.sh config` so the seed config is merged and expanded.
4. Run a full build when the change affects image content.
5. Run `.buildenv/build.sh extract` to copy firmware artifacts into `output/`.
6. Verify the generated rootfs or image metadata when changing first-boot defaults.
7. Update release docs/checksums only after a successful rebuild.
8. Commit source and documentation changes, not generated build outputs.

## Build harness

The Docker wrapper in `.buildenv/build.sh` is the supported local build entry point.

Common commands:

| Command | Use |
|---------|-----|
| `./.buildenv/build.sh init` | Build the Docker image, create the Docker volume, and link heavy build directories. |
| `./.buildenv/build.sh feeds` | Update and install feeds. |
| `./.buildenv/build.sh config` | Merge `.buildenv/zbt8803be.config` into `.config` and run `make defconfig`. |
| `./.buildenv/build.sh download` | Pre-download sources. |
| `./.buildenv/build.sh build` | Run the full parallel build. |
| `./.buildenv/build.sh build -j1 V=s` | Run a serial verbose build for diagnosis. |
| `./.buildenv/build.sh extract` | Copy `bin/targets` outputs into `output/`. |

The wrapper exists because macOS APFS is commonly case-insensitive, while OpenWrt kernel/package extraction expects a Linux-style case-sensitive filesystem. Heavy build directories are linked to a Docker volume.

## Where to make changes

| Change type | Primary location |
|-------------|------------------|
| Package selection | `.buildenv/zbt8803be.config` |
| Feed pins | `feeds.conf.default` |
| Board DTS/hardware modeling | `target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts` |
| Image profile | `target/linux/mediatek/image/filogic.mk` |
| Network defaults | `target/linux/mediatek/filogic/base-files/etc/board.d/02_network` and `etc/uci-defaults/30-zbt-z8803be-wan-failover` |
| GPIO switches | `target/linux/mediatek/filogic/base-files/etc/board.d/03_gpio_switches` |
| WiFi defaults | `target/linux/mediatek/filogic/base-files/etc/uci-defaults/70-zbt-z8803be-wifi` |
| DNS defaults | `target/linux/mediatek/filogic/base-files/etc/uci-defaults/90-zbt-z8803be-dns-cache` |
| QModem monitor defaults | `target/linux/mediatek/filogic/base-files/etc/uci-defaults/45-zbt-qmodem-monitor-enable` |
| Modem helper scripts | `target/linux/mediatek/filogic/base-files/usr/sbin/` and `usr/lib/zbt/` |
| Local LuCI apps | `package/luci-app-zbt-*` and `package/luci-app-mlo` |
| Release notes | `releases/RELEASE_NOTES*.md` |

## Local LuCI app structure

The local LuCI apps follow the standard package layout:

```text
package/<app>/Makefile
package/<app>/htdocs/luci-static/resources/view/...
package/<app>/root/usr/share/luci/menu.d/*.json
package/<app>/root/usr/share/rpcd/acl.d/*.json
```

Apps with background services also include init scripts, uci-defaults, and helper scripts under `root/`.

Examples:

- `package/luci-app-zbt-temperature/root/usr/sbin/zbt-temperature-log`
- `package/luci-app-zbt-modem-events/root/usr/sbin/zbt-modem-events`
- `package/luci-app-zbt-modem-events/root/etc/init.d/zbt_modem_events`

## First-boot scripts

Board uci-defaults are designed to be idempotent and board-guarded. When editing them:

- Keep the board-name guard intact.
- Prefer `uci -q set` and `uci -q delete` for idempotency.
- Commit only after running shell syntax checks.
- If changing first-boot behavior, rebuild and verify the generated rootfs contains the expected script content.

## Generated artifacts to avoid committing

The repository `.gitignore` excludes normal OpenWrt build outputs and local release binaries:

```text
.config
.config.old
bin/
build_dir/
staging_dir/
tmp/
dl/
feeds/
package/feeds/
output/
releases/* except Markdown
private-key.pem
public-key.pem
```

Do not force-add generated images, build directories, feeds, keys, logs, or `.config` unless there is an explicit reason.

## Release-doc workflow

When publishing a rebuilt image:

1. Build and extract artifacts.
2. Copy the release assets into `releases/` for local staging.
3. Run checksum validation with `sha256sum -c sha256sums --ignore-missing`.
4. Update README and release-note checksums.
5. Push branch and retarget the release tag.
6. Upload assets with `gh release upload --clobber`.
7. Update the release body from `releases/RELEASE_NOTES.md`.
8. Download release assets to a temporary directory and validate them against the published `sha256sums`.

## Style guidance

- Keep public docs specific to the repository and board.
- Avoid claims that cannot be traced to files in the repository or release assets.
- Keep deployment-specific private details out of public documentation unless they are already intentionally documented.
- Prefer source paths and UCI option names over vague descriptions.
