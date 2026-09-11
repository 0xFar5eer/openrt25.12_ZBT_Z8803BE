#!/usr/bin/env bash
# Build the complete imported Minimal edition using this repository's pinned base.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPE="$ROOT/.buildenv/minimal"
BASE_COMMIT=edc738504fe8fae81eb15de967456204699b1830
BUILD_DIR="${MINIMAL_BUILD_DIR:-$ROOT/minimal-build}"
IMAGE="${MINIMAL_IMAGE:-zbt-z8803be-minimal-builder}"
# The unchanged Minimal Dockerfile uses the x86 multilib toolchain. Docker
# Desktop on ARM can run this platform through its amd64 emulation support.
PLATFORM=linux/amd64

check() {
    python3 "$ROOT/.buildenv/check-minimal-source.py"
    bash "$RECIPE/firmware/scripts/check-build-inputs.sh"
}

prepare() {
    check
    git -C "$ROOT" cat-file -e "$BASE_COMMIT^{commit}" || {
        echo "Missing pinned base; fetch origin $BASE_COMMIT before building." >&2
        exit 2
    }
    mkdir -p "$BUILD_DIR"
    BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
    if [[ ! -e "$BUILD_DIR/openwrt" ]]; then
        git clone --no-hardlinks --no-checkout "$ROOT" "$BUILD_DIR/openwrt"
        git -C "$BUILD_DIR/openwrt" checkout --detach "$BASE_COMMIT"
    fi
    [[ "$(git -C "$BUILD_DIR/openwrt" rev-parse HEAD)" == "$BASE_COMMIT" ]] || {
        echo 'Existing build checkout has a different base; use another MINIMAL_BUILD_DIR.' >&2
        exit 2
    }
    echo "Minimal build source: $BUILD_DIR/openwrt"
}

case "${1:-build}" in
    check) check ;;
    prepare) prepare ;;
    build)
        prepare
        docker build --platform "$PLATFORM" \
            -f "$RECIPE/firmware/docker/Dockerfile.remote-builder" -t "$IMAGE" "$RECIPE"
        docker run --rm --platform "$PLATFORM" \
            -v "$RECIPE:/recipe:ro" -v "$BUILD_DIR/openwrt:/workspace/openwrt" \
            -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
            -e GIT_CONFIG_VALUE_0=/workspace/openwrt \
            -e OPENWRT_ROOT=/workspace/openwrt -e ALLOW_CLONE_OPENWRT=0 \
            -e PROFILE_PACKAGES_FILE=/recipe/firmware/profiles/packages-default.txt \
            -e PROFILE_KCONFIG_FILE=/recipe/firmware/profiles/kconfig-fragment.conf \
            -e BASE_CONFIG_FILE=/recipe/firmware/profiles/base-config-zbt-z8803be-v25.12.021.config \
            -e FILES_OVERLAY_DIR=/recipe/firmware/files \
            -e FINAL_MAKE_JOBS="${FINAL_MAKE_JOBS:-2}" -e HOST_MAKE_JOBS="${HOST_MAKE_JOBS:-1}" \
            "$IMAGE" bash /recipe/firmware/docker/build-openwrt.sh
        echo "Validated Minimal images: $BUILD_DIR/openwrt/bin/targets/mediatek/filogic/"
        ;;
    *) echo "Usage: $0 [check|prepare|build]" >&2; exit 2 ;;
esac
