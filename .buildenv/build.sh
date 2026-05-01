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
IMAGE="openwrt-zbt8803be:ubuntu-24.04"
VOL="openwrt-zbt8803be-buildvol"
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
    [ -t 0 ] && [ -t 1 ] && tty_flag="-it"
    docker run --rm $tty_flag \
        -v "$PROJ":$CONTAINER_SRC \
        -v "$VOL":$VOL_MOUNT \
        -w $CONTAINER_SRC \
        -e TERM="${TERM:-xterm}" \
        "$IMAGE" "$@"
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
        run_in_container bash -c './scripts/feeds update -a && ./scripts/feeds install -a && rm -rf package/feeds/iwrt_luci/luci-app-homeproxy package/feeds/iwrt_luci/luci-app-passwall package/feeds/iwrt_luci/luci-app-ipsec-vpnd'
        ;;
    config)
        # Idempotently merge the seed file into .config so additions
        # to .buildenv/zbt8803be.config are picked up on every run,
        # then expand with `make defconfig`. Lines in the seed
        # overwrite any previous setting with the same CONFIG key.
        run_in_container bash -c '
            touch .config
            if [ -s .buildenv/zbt8803be.config ]; then
                while IFS= read -r line; do
                    case "$line" in
                    "#"*|"") printf "%s\n" "$line" >> .config ;;
                    CONFIG_*)
                        key="${line%%=*}"
                        sed -i "/^${key}=\|^# ${key} is not set/d" .config
                        printf "%s\n" "$line" >> .config
                        ;;
                    *) printf "%s\n" "$line" >> .config ;;
                    esac
                done < .buildenv/zbt8803be.config
            fi
            make defconfig
        '
        ;;
    menuconfig)
        run_in_container bash -c 'make menuconfig'
        ;;
    download)
        run_in_container bash -c "make -j$(ncpu) download V=s"
        ;;
    build)
        local_args="$*"
        if [ -z "$local_args" ]; then
            local_args="-j$(ncpu)"
        fi
        run_in_container bash -c "make $local_args"
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
