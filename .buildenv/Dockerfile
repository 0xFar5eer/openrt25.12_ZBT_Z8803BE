# OpenWrt build environment for ZBT-Z8803BE
#   - base: openwrt/openwrt @ main (no mtk-openwrt-feeds overlay)
#   - device port: pttuan/openwrt @ zbt8803_25.12 commit fce4731b5c,
#                  cherry-picked on top of main (see this repo's README).
# Native aarch64 Ubuntu 24.04 - cross-compiles to target SoC MT7988A.
#
# Base image is pinned by manifest-list digest for reproducibility.
# The digest below is the multi-arch manifest list (linux/amd64 +
# linux/arm64), so the same line works on both Apple Silicon and x86_64
# build hosts. Refreshing the pin (and rebuilding the layer cache) is a
# deliberate step:
#   docker buildx imagetools inspect ubuntu:24.04
# pick the new manifest-list digest, update the line, run
#   ./.buildenv/build.sh init
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

# OpenWrt build dependencies.
# gcc-multilib / g++-multilib are x86-only; skipped on arm64.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ccache \
        clang \
        flex \
        bison \
        g++ \
        gawk \
        gcc \
        gettext \
        git \
        libncurses-dev \
        libssl-dev \
        python3 \
        python3-setuptools \
        python3-pip \
        python3-distutils-extra \
        rsync \
        unzip \
        zlib1g-dev \
        file \
        wget \
        curl \
        zstd \
        swig \
        time \
        xsltproc \
        ca-certificates \
        subversion \
        libelf-dev \
        ecj \
        fastjar \
        java-propose-classpath \
        sudo \
        vim \
        nano \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a 'ubuntu' user at UID 1000. Remove then create 'builder'.
RUN userdel -r ubuntu 2>/dev/null || true \
    && (getent group ${BUILDER_GID} || groupadd -g ${BUILDER_GID} builder) \
    && useradd -m -u ${BUILDER_UID} -g ${BUILDER_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

USER builder
WORKDIR /workdir

RUN git config --global --add safe.directory '*' \
    && git config --global user.email "builder@docker.local" \
    && git config --global user.name  "OpenWrt Builder"

CMD ["/bin/bash"]
