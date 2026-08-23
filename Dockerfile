#syntax=docker/dockerfile:1

# renovate: datasource=docker depName=golang versioning=docker
ARG GOLANG_VERSION="1.27"
# renovate: datasource=docker depName=alpine versioning=docker
ARG ALPINE_VERSION="3.24"
# renovate: datasource=github-releases depName=containers/buildah
ARG BUILDAH_VERSION="1.45.0"

#-- Import xx toolchain
FROM --platform=$BUILDPLATFORM docker.io/tonistiigi/xx:latest AS xx

#-- Source Stage
FROM --platform=$BUILDPLATFORM docker.io/library/alpine:${ALPINE_VERSION} AS src

RUN apk add --no-cache git

WORKDIR /src
ARG BUILDAH_VERSION
RUN test -n "${BUILDAH_VERSION}" \
    && git init . \
    && git remote add origin https://github.com/containers/buildah.git \
    && git fetch --depth 1 origin tag "v${BUILDAH_VERSION}" \
    && git checkout FETCH_HEAD

#-- Builder Stage (Alpine host + tonistiigi/xx + musl + Clang/LLVM)
FROM --platform=$BUILDPLATFORM docker.io/library/golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} AS builder

# Inject tonistiigi/xx cross-compilation tools
COPY --from=xx / /

# Install host build toolchain
RUN apk add --no-cache \
    bash \
    make \
    git \
    clang \
    lld \
    llvm \
    pkgconf \
    ca-certificates \
    curl \
    gcc \
    musl-dev

ARG TARGETPLATFORM
ARG TARGETARCH

# Install target static dependencies into the xx sysroot
RUN xx-apk add --no-cache --no-scripts \
    musl-dev \
    gcc \
    libgcc-static \
    linux-headers \
    libseccomp-dev \
    libseccomp-static \
    btrfs-progs-dev \
    btrfs-progs-static \
    shadow-dev

WORKDIR /srv/buildah
COPY --from=src /src /srv/buildah

# Cross-compile statically using xx-go wrapper and LLD
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    xx-go --wrap && \
    ARCH_OPT="" && \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        ARCH_OPT="-march=x86-64-v2"; \
    fi && \
    export CC="xx-clang" \
           CXX="xx-clang++" \
           CGO_ENABLED=1 \
           CGO_CFLAGS="-O3 -flto=thin -pthread ${ARCH_OPT}" \
           CGO_LDFLAGS="-fuse-ld=lld -flto=thin" \
           BUILDTAGS="static netgo osusergo exclude_graphdriver_devicemapper seccomp containers_image_openpgp" \
           EXTRA_LDFLAGS='-s -w -linkmode external -extldflags "-static -fuse-ld=lld -flto=thin"' && \
    make bin/buildah

# Verify static binary integrity
RUN xx-verify --static bin/buildah

# Assemble clean, minimal distribution layout
RUN DEST="/out/buildah-linux-${TARGETARCH}" && \
    mkdir -p \
        "${DEST}/usr/local/bin" \
        "${DEST}/usr/local/share/bash-completion/completions" \
        "${DEST}/usr/local/share/zsh/site-functions" \
        "${DEST}/usr/local/share/fish/vendor_completions.d" \
        "${DEST}/etc/containers" && \
    cp bin/buildah "${DEST}/usr/local/bin/buildah" && \
    chmod 755 "${DEST}/usr/local/bin/buildah" && \
    [ -f contrib/completions/bash/buildah ] && cp contrib/completions/bash/buildah "${DEST}/usr/local/share/bash-completion/completions/buildah" || true; \
    [ -f contrib/completions/zsh/_buildah ] && cp contrib/completions/zsh/_buildah "${DEST}/usr/local/share/zsh/site-functions/_buildah" || true; \
    [ -f contrib/completions/fish/buildah.fish ] && cp contrib/completions/fish/buildah.fish "${DEST}/usr/local/share/fish/vendor_completions.d/buildah.fish" || true; \
    [ -f tests/policy.json ] && cp tests/policy.json "${DEST}/etc/containers/policy.json" || true; \
    [ -f tests/registries.conf ] && cp tests/registries.conf "${DEST}/etc/containers/registries.conf" || true; \
    [ -f tests/storage.conf ] && cp tests/storage.conf "${DEST}/etc/containers/storage.conf" || true; \
    [ -f LICENSE ] && cp LICENSE "${DEST}/LICENSE" || true; \
    [ -f README.md ] && cp README.md "${DEST}/README.md" || true

#-- Final Stage (Exports clean buildah-linux-<arch>/ bundle)
FROM scratch AS local

COPY --from=builder /out /