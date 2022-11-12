FROM quay.io/centos/centos:stream9 AS base

RUN dnf -y install dnf-plugins-core
RUN dnf -y config-manager --set-enabled crb
RUN dnf -y install epel-release epel-next-release
RUN dnf -y install --allowerasing \
    bash \
    findutils diffutils util-linux \
    patch \
    bzip2 p7zip xz gzip lzip unzip zip cpio \
    git \
    curl \
    wget \
    gcc gcc-c++ \
    clang llvm \
    glibc-static glibc-devel \
    libstdc++-static libstdc++-devel \
    make \
    ninja-build \
    automake autoconf \
    cmake \
    meson \
    bison flex \
    m4 \
    texinfo help2man \
    python3 python3-setuptools python3-wheel python3-pip \
    ncurses-devel

RUN dnf -y install \
  gcc-c++-aarch64-linux-gnu \
  gcc-c++-arm-linux-gnu \
  gcc-c++-ppc64le-linux-gnu \
  gcc-c++-riscv64-linux-gnu \
  gcc-c++-x86_64-linux-gnu \
  mingw64-gcc-c++

RUN mkdir -p /work

FROM base AS osxcross-build

RUN dnf -y install \
    bzip2-devel \
    openssl-devel \
    xz-devel \
    libxml2-devel

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
RUN git clone https://github.com/tpoechtrager/osxcross.git /work/osxcross
COPY MacOSX${SDK_VERSION}.sdk.tar.xz /work/osxcross/tarballs/
RUN cd /work/osxcross && mkdir /work/prefix/ && UNATTENDED=1 TARGET_DIR=/work/prefix/osxcross-${SDK_VERSION} ./build.sh

FROM base AS final

COPY --from=osxcross-build /work/prefix/osxcross* /opt/osxcross/
ENV PATH="${PATH}:/opt/osxcross/bin"
RUN useradd -s /bin/bash -U -d /work cross
RUN chown -R cross:cross /work

WORKDIR /work
USER cross:cross
