#syntax=docker/dockerfile:1.6.0

# renovate: datasource=github-releases depName=containers/buildah
ARG BUILDAH_VERSION=1.32.2

#--

FROM debian:bookworm AS build-base

SHELL ["bash", "-euxo", "pipefail", "-c"]

# Configure apt to be docker friendly
ADD https://gist.githubusercontent.com/HeavenVolkoff/ff7b77b9087f956b8df944772e93c071/raw \
    /etc/apt/apt.conf.d/99docker-apt-config

RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get upgrade && apt-get install -y \
    git \
    gcc \
    make \
    bats \
    golang-go \
    go-md2man \
    pkg-config \
    btrfs-progs \
    libsubid-dev \
    libgpgme-dev \
    libostree-dev \
    libseccomp-dev \
    libglib2.0-dev \
    libselinux1-dev \
    libapparmor-dev \
    ca-certificates \
    libdevmapper-dev \
    libgpg-error-dev

WORKDIR /srv/buildah

ARG BUILDAH_VERSION
RUN test -n "${BUILDAH_VERSION}" \
    && git clone --config advice.detachedHead=false --depth 1 --branch "v${BUILDAH_VERSION}" \
    https://github.com/containers/buildah .

RUN export CNI_VERSION="$(grep '^# github.com/containernetworking/cni ' src/modules.txt | sed 's,.* ,,')" \
    && env \
    CFLAGS='-static -pthread' \
    LDFLAGS="-s -w -static-libgcc -static" \
    BUILDTAGS='static netgo osusergo exclude_graphdriver_devicemapper seccomp apparmor selinux' \
    CGO_ENABLED=1 \
    EXTRA_LDFLAGS='-s -w -linkmode external -extldflags "-static -lgpg-error -lassuan -lm"' \
    make buildah

FROM scratch AS local

COPY --from=build-base "/srv/buildah/bin/buildah" /buildah
