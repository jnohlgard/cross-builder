FROM quay.io/centos/centos:stream9 AS base

# Don't install documentation
RUN printf 'tsflags=nodocs\n' >> /etc/dnf/dnf.conf

RUN dnf -y install dnf-plugins-core
RUN dnf -y config-manager --set-enabled crb
RUN dnf -y install epel-release epel-next-release
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
RUN git clone --depth 1 https://github.com/tpoechtrager/osxcross.git /work/osxcross
COPY MacOSX${SDK_VERSION}.sdk.tar.xz /work/osxcross/tarballs/
RUN cd /work/osxcross && UNATTENDED=1 TARGET_DIR=/work/prefix/osxcross-${SDK_VERSION} ./build.sh
RUN printf 'Patching RUNPATH in installed tools to make the toolchain relocatable\n'; \
    for f in $(find /work/prefix/osxcross-${SDK_VERSION}/bin/ -type f); do \
      test -n "$(readelf -d "$f" 2>/dev/null | grep RUNPATH || true)" && \
        patchelf --set-rpath '$ORIGIN/../lib' "$f" || true; \
    done

FROM base AS final

RUN mkdir -p /work
RUN useradd -s /bin/bash -U -d /work cross
RUN chown -R cross:cross /work

COPY --from=osxcross-build /work/prefix/osxcross* /opt/osxcross/
ENV PATH="${PATH}:/opt/osxcross/bin"

RUN printf 'Installing mingw64 cross toolchain\n' && \
  dnf -y install mingw64-gcc-c++

ARG dnf_cross_args="--repo baseos --repo appstream --nodocs --releasever=/"

RUN printf 'Installing aarch64-linux-gnu cross toolchain\n' && \
  dnf -y install gcc-c++-aarch64-linux-gnu && \
  dnf -y install \
    --forcearch=aarch64 --installroot=/usr/aarch64-linux-gnu/sys-root \
    ${dnf_cross_args} \
    glibc-devel

RUN printf 'Installing ppc64le-linux-gnu cross toolchain\n' && \
  dnf -y install gcc-c++-ppc64le-linux-gnu && \
  dnf -y install \
    --forcearch=ppc64le --installroot=/usr/powerpc64le-linux-gnu/sys-root \
    ${dnf_cross_args} \
    glibc-devel

RUN printf 'Installing x86_64-linux-gnu cross toolchain\n' && \
  dnf -y install gcc-c++-x86_64-linux-gnu && \
  dnf -y install \
    --forcearch=x86_64 --installroot=/usr/x86_64-linux-gnu/sys-root \
    ${dnf_cross_args} \
    glibc-devel libstdc++-devel glibc-static libstdc++-static

RUN printf 'Installing arm-linux-gnu cross toolchain\n' && \
  dnf -y install gcc-c++-arm-linux-gnu && \
  update-crypto-policies --set DEFAULT:SHA1 && \
  dnf -y install \
    --forcearch=armv7hl --installroot=/usr/arm-linux-gnu/sys-root \
    --releasever=7 --repofrompath 'base,http://mirror.centos.org/altarch/$releasever/os/$basearch/' \
    --repo base \
    --setopt=base.gpgkey="https://centos.org/keys/RPM-GPG-KEY-CentOS-7 https://centos.org/keys/RPM-GPG-KEY-CentOS-SIG-AltArch-Arm32" \
    glibc-devel

RUN printf 'Installing riscv64-linux-gnu cross toolchain (missing sysroot)\n' && \
  dnf -y install gcc-c++-riscv64-linux-gnu

WORKDIR /work
USER cross:cross
