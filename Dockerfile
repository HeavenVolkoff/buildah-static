#syntax=docker/dockerfile:1.5.1

FROM ubuntu:22.04@sha256:f05532b6a1dec5f7a77a8d684af87bc9cd1f2b32eab301c109f8ad151b5565d1 AS clone
# renovate: datasource=github-releases depName=containers/buildah
ARG BUILDAH_VERSION=1.29.0
RUN apt-get update \
 && apt-get -y install --no-install-recommends \
        git \
        ca-certificates
WORKDIR /tmp/buildah
RUN test -n "${BUILDAH_VERSION}" \
 && git clone --config advice.detachedHead=false --depth 1 --branch "v${BUILDAH_VERSION}" \
        https://github.com/containers/buildah .

FROM clone AS build
RUN apt-get -y install --no-install-recommends \
        make \
        gcc \
        bats \
        btrfs-progs \
        libapparmor-dev \
        libdevmapper-dev \
        libglib2.0-dev \
        libgpgme11-dev \
        libseccomp-dev \
        libselinux1-dev \
        golang-go \
        go-md2man \
 && rm /usr/local/sbin/unminimize
COPY --from=clone /tmp/buildah /tmp/buildah
WORKDIR /tmp/buildah
ENV CFLAGS='-static -pthread' \
    LDFLAGS='-s -w -static-libgcc -static' \
    EXTRA_LDFLAGS='-s -w -linkmode external -extldflags "-static -lm"' \
    BUILDTAGS='static netgo osusergo exclude_graphdriver_btrfs exclude_graphdriver_devicemapper seccomp apparmor selinux' \
    CGO_ENABLED=1
RUN make all \
 && mkdir -p /usr/local/share/bash-completion/completions \
 && cp contrib/completions/bash/buildah /usr/local/share/bash-completion/completions/

FROM build AS install
RUN make install

FROM scratch AS local
COPY --from=install /usr/local/bin   ./bin
COPY --from=install /usr/local/share ./share
