FROM registry.fedoraproject.org/fedora:latest AS base

# Don't install documentation
RUN printf 'tsflags=nodocs\n' >> /etc/dnf/dnf.conf

RUN dnf -y install --allowerasing \
    bash \
    findutils diffutils util-linux \
    file patch which \
    bzip2 p7zip xz gzip lzip unzip zip cpio \
    git \
    curl \
    wget \
    gcc gcc-c++ \
    clang llvm \
    glibc-static glibc-devel \
    libstdc++-static libstdc++-devel \
    libtool \
    make \
    ninja-build \
    automake autoconf \
    cmake \
    meson \
    bison flex \
    m4 \
    gnulib \
    texinfo help2man \
    python3 python3-setuptools python3-wheel python3-pip \
    openssl \
    ncurses-devel \
    patchelf \
    xar uuid

FROM base AS osxcross-build

RUN dnf -y install \
    bzip2-devel \
    openssl-devel \
    xz-devel \
    libxml2-devel \
    llvm-devel \
    uuid-devel \
    xar-devel

# Follow the instructions at
# https://github.com/tpoechtrager/osxcross/blob/master/README.md#packaging-the-sdk
# to construct a MacOS SDK tarball from the Apple Xcode Command Line Tools release package

# For a list of SDK versions and MacOS version support, see
# - https://en.wikipedia.org/wiki/Xcode#Xcode_11.0_-_14.x_(since_SwiftUI_framework)
# - https://xcodereleases.com/

ARG macos_sdk_version=11.3
ARG macos_version_min=11.0
ENV SDK_VERSION=${macos_sdk_version}
ENV OSX_VERSION_MIN=${macos_version_min}
RUN mkdir -p /work/prefix/
RUN git clone https://github.com/tpoechtrager/osxcross.git /work/osxcross
COPY MacOSX${SDK_VERSION}.sdk.tar.xz /work/osxcross/tarballs/
RUN cd /work/osxcross && UNATTENDED=1 TARGET_DIR=/work/prefix/osxcross-${SDK_VERSION} ./build.sh
RUN printf 'Patching RUNPATH in installed tools to make the toolchain relocatable\n'; \
    for f in $(find /work/prefix/osxcross-${SDK_VERSION}/bin/ -type f); do \
      test -n "$(readelf -d "$f" 2>/dev/null | grep RUNPATH || true)" && \
        patchelf --set-rpath '$ORIGIN/../lib' "$f" || true; \
    done

FROM base AS crosstool-build

COPY ./crosstool-configs /work/crosstool-configs
RUN useradd -s /bin/bash -U -d /work cross
RUN mkdir -p /work/prefix /work/src
RUN chown cross:cross -R /work
WORKDIR /work
USER cross:cross

RUN git clone https://github.com/crosstool-ng/crosstool-ng.git /work/crosstool-ng
RUN cd /work/crosstool-ng && ./bootstrap && ./configure --enable-local && make -j9
ENV PATH=$PATH:/work/crosstool-ng
ENV CT_PREFIX=/work/prefix
RUN set -eux; for config in /work/crosstool-configs/*; do \
      mkdir -p "/work/build-${config##*/}" && \
      cd "/work/build-${config##*/}" && \
      cp "${config}" defconfig && \
      printf '%s\n' \
        'CT_USE_MIRROR=y' \
        'CT_MIRROR_BASE_URL="https://cache.nohlgard.se/crosstool-ng/"' \
        'CT_CC_GCC_BUILD_ID=y' \
        >> defconfig && \
      ct-ng defconfig && \
      ct-ng build; \
    done

FROM base AS final

RUN mkdir -p /work
RUN useradd -s /bin/bash -U -d /work cross
RUN chown -R cross:cross /work

COPY --from=osxcross-build /work/prefix/osxcross-* /opt/osxcross
COPY --from=crosstool-build /work/prefix/ /opt/
ENV PATH="${PATH}:/opt/aarch64-unknown-linux-gnu/bin:/opt/riscv64-unknown-linux-gnu/bin:/opt/x86_64-pc-linux-gnu/bin:/opt/osxcross/bin"

RUN printf 'Installing mingw64 cross toolchain\n' && \
  dnf -y install mingw64-gcc-c++

WORKDIR /work
USER cross:cross
