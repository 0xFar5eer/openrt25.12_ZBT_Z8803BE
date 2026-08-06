#!/usr/bin/env bash
# Wrapper: drive OpenWrt Docker build from host.
# Usage:
#   ./.buildenv/build.sh init         # build image, create volume, link build dirs
#   ./.buildenv/build.sh shell        # interactive shell in container
#   ./.buildenv/build.sh feeds        # update + install feeds
#   ./.buildenv/build.sh config       # make defconfig (reads .config)
#   ./.buildenv/build.sh menuconfig   # interactive menuconfig (TTY required)
#   ./.buildenv/build.sh download     # pre-download all sources
#   ./.buildenv/build.sh build        # full parallel build
#   ./.buildenv/build.sh build -j1 V=s  # serial verbose build (debug)
#   ./.buildenv/build.sh extract      # copy firmware -> host output/
#   ./.buildenv/build.sh clean        # make clean
#   ./.buildenv/build.sh dirclean     # make dirclean
#   ./.buildenv/build.sh nuke-volume  # destroy the Docker build volume only
#   ./.buildenv/build.sh nuke-all     # full scrub: volume + output/ + symlinks
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$HERE")"

# A replay'd worktree (.buildenv/replay-customizations.sh seeds this)
# may drop a per-tree env file with a different VOL. Auto-source it
# first so user env still wins.
[ -f "$HERE/local.env" ] && . "$HERE/local.env"

# Image and Docker volume names. Both can be overridden via env so a
# replay'd checkout (e.g. the zbt8803be-upstream-latest worktree) can
# point at its own build state without touching this file:
#   IMAGE=openwrt-zbt8803be:ubuntu-24.04 \
#   VOL=openwrt-zbt8803be-upstream-buildvol \
#       ./.buildenv/build.sh build
# The defaults match the original snapshot tree.
IMAGE="${IMAGE:-openwrt-zbt8803be:ubuntu-24.04}"
VOL="${VOL:-openwrt-zbt8803be-buildvol}"
# Optional per-worktree resolver for Docker Desktop environments whose
# embedded DNS proxy cannot reach the active LAN resolver. Leave empty to
# retain Docker's normal DNS behavior; `.buildenv/local.env` may set it.
DOCKER_DNS="${DOCKER_DNS:-}"
CONTAINER_SRC="/workdir"
VOL_MOUNT="/volume"

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

ncpu() {
    sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4
}

build_image() {
    docker build -t "$IMAGE" \
        --build-arg BUILDER_UID="$(id -u)" \
        --build-arg BUILDER_GID="$(id -g)" \
        "$HERE"
}

ensure_volume() {
    docker volume inspect "$VOL" >/dev/null 2>&1 || docker volume create "$VOL"
}

# Move/link heavy build dirs onto Linux volume (case-sensitive FS).
# macOS APFS is case-insensitive -> kernel/package extraction fails otherwise.
link_build_dirs() {
    docker run --rm \
        -v "$PROJ":$CONTAINER_SRC \
        -v "$VOL":$VOL_MOUNT \
        "$IMAGE" bash -c '
            set -e
            sudo chown -R builder: '"$VOL_MOUNT"'
            cd '"$CONTAINER_SRC"'
            for d in build_dir staging_dir dl tmp bin; do
                mkdir -p '"$VOL_MOUNT"'/$d
                if [ -e "$d" ] && [ ! -L "$d" ]; then
                    echo "Migrating existing $d into volume..."
                    rsync -a "$d"/ '"$VOL_MOUNT"'/$d/
                    rm -rf "$d"
                fi
                if [ ! -L "$d" ]; then
                    ln -sfn '"$VOL_MOUNT"'/$d "$d"
                fi
                echo "ok: $d -> '"$VOL_MOUNT"'/$d"
            done
        '
}

run_in_container() {
    local tty_flag=""
    local dns_flag=""
    [ -t 0 ] && [ -t 1 ] && tty_flag="-it"
    [ -n "$DOCKER_DNS" ] && dns_flag="--dns $DOCKER_DNS"
    docker run --rm $tty_flag $dns_flag \
        -v "$PROJ":$CONTAINER_SRC \
        -v "$VOL":$VOL_MOUNT \
        -w $CONTAINER_SRC \
        -e TERM="${TERM:-xterm}" \
        "$IMAGE" "$@"
}

ensure_version_file() {
    [ -s "$PROJ/version" ] && return 0

    local rev=""
    if git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1; then
        local reboot="ee53a240ac902dc83209008a2671e7fdcf55957a"
        local count hash
        count="$(git -C "$PROJ" rev-list "${reboot}..HEAD" 2>/dev/null | wc -l | awk '{print $1}')"
        hash="$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || true)"
        [ -n "$count" ] && [ -n "$hash" ] && rev="r${count}-${hash}"
    fi
    [ -n "$rev" ] || rev="r0-tarball"
    printf '%s\n' "$rev" > "$PROJ/version"
    echo "ok: seeded ./version ($rev)"
}

case "$cmd" in
    init)
        build_image
        ensure_volume
        link_build_dirs
        echo "=== init complete ==="
        ;;
    shell)
        run_in_container bash
        ;;
    feeds)
        run_in_container bash -c '
            export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1 GIT_CONFIG_KEY_1=http.lowSpeedLimit GIT_CONFIG_VALUE_1=1024 GIT_CONFIG_KEY_2=http.lowSpeedTime GIT_CONFIG_VALUE_2=120
            ./scripts/feeds update -a
            rm -rf \
                feeds/packages/utils/clixon package/feeds/packages/clixon \
                feeds/iwrt_packages/utils/clixon package/feeds/iwrt_packages/clixon \
                feeds/packages/net/openvswitch feeds/packages/net/ovn \
                package/feeds/packages/openvswitch package/feeds/packages/ovn \
                feeds/iwrt_packages/net/openvswitch feeds/iwrt_packages/net/ovn \
                package/feeds/iwrt_packages/openvswitch package/feeds/iwrt_packages/ovn \
                package/feeds/packages/jool \
                feeds/iwrt_luci/applications/luci-app-homeproxy \
                feeds/iwrt_luci/applications/luci-app-passwall \
                feeds/iwrt_luci/applications/luci-app-ipsec-vpnd \
                package/feeds/iwrt_luci/luci-app-homeproxy \
                package/feeds/iwrt_luci/luci-app-passwall \
                package/feeds/iwrt_luci/luci-app-ipsec-vpnd \
                feeds/packages.tmp \
                feeds/iwrt_packages.tmp \
                feeds/iwrt_luci.tmp \
                feeds/qmodem.tmp
            ./scripts/feeds update -a
            ./scripts/feeds install -a
        '
        ;;
    config)
        ensure_version_file
        # Rebuild .config from the seed file on every run, then expand
        # with `make defconfig`. This avoids stale entries accumulating
        # across upstream rebases or repeated config passes.
        run_in_container bash -c '
            if [ -s .buildenv/zbt8803be.config ]; then
                cp .buildenv/zbt8803be.config .config
            else
                : > .config
            fi
            make defconfig
        '
        ;;
    menuconfig)
        run_in_container bash -c 'make menuconfig'
        ;;
    download)
        ensure_version_file
        run_in_container bash -c "make -j$(ncpu) download V=s"
        ;;
    build)
        ensure_version_file
        if [ "$#" -eq 0 ]; then
            run_in_container make "-j$(ncpu)"
        else
            run_in_container make "$@"
        fi
        ;;
    extract)
        mkdir -p "$PROJ/output"
        run_in_container bash -c '
            set -e
            out="/workdir/bin/targets"
            if [ ! -d "$out" ]; then
                echo "ERR: $out missing - build did not produce firmware"
                exit 1
            fi
            rsync -a "$out"/ /workdir/output/
            find "$out" -maxdepth 5 -type f -printf "%p (%s bytes)\n"
        '
        echo "=== firmware files copied to $PROJ/output/ ==="
        ls -la "$PROJ/output/" || true
        ;;
    clean)
        run_in_container bash -c 'make clean'
        ;;
    dirclean)
        run_in_container bash -c 'make dirclean'
        ;;
    nuke-volume)
        docker volume rm -f "$VOL"
        echo "volume $VOL destroyed"
        ;;
    nuke-all)
        # Full scrub so a subsequent `init` starts from zero. Destroys the
        # Docker volume, removes the host-side output staging directory,
        # and deletes the symlinks that pointed into the volume from the
        # project root (if the volume is gone, these become dangling).
        docker volume rm -f "$VOL" || true
        rm -rf "$PROJ/output"
        for d in build_dir staging_dir dl tmp bin; do
            if [ -L "$PROJ/$d" ]; then
                rm -f "$PROJ/$d"
            elif [ -d "$PROJ/$d" ]; then
                rm -rf "$PROJ/$d"
            fi
        done
        rm -f "$PROJ/.config" "$PROJ/.config.old" "$PROJ/tmp.config" "$PROJ/tmp.config.old"
        echo "=== nuke-all complete (volume, output/, build symlinks, .config all gone) ==="
        ;;
    "" | help | -h | --help)
        sed -n '2,20p' "$0"
        ;;
    *)
        echo "unknown cmd: $cmd"; exit 2
        ;;
esac
