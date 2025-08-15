# Dockerfile for Android 14 6.1.124 Kernel Build
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set build environment variables
ENV ANDROID_VERSION="android14"
ENV KERNEL_VERSION="6.1"
ENV SUB_LEVEL="124"
ENV OS_PATCH_LEVEL="2025-02"
ENV CONFIG="${ANDROID_VERSION}-${KERNEL_VERSION}-${SUB_LEVEL}"

# Environment variables to match GitHub Actions runner
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV CI=true
ENV GITHUB_ACTIONS=true

# ccache configuration
ENV CCACHE_DIR="/ccache"
ENV CCACHE_COMPILERCHECK="%compiler% -dumpmachine; %compiler% -dumpversion"
ENV CCACHE_NOHASHDIR="true"
ENV CCACHE_HARDLINK="true"

# PATH additions (similar to GitHub runner)
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create non-root user for builds
RUN groupadd -r builder && useradd -r -g builder -m -d /home/builder -s /bin/bash builder

# Install system dependencies to match GitHub Actions Ubuntu runner
RUN apt-get update && apt-get install -y \
    # Build tools (GitHub runner standard)
    build-essential \
    gcc \
    g++ \
    clang \
    llvm \
    make \
    cmake \
    ninja-build \
    ccache \
    # Development libraries
    libc6-dev \
    libssl-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libgdbm-dev \
    libdb5.3-dev \
    libbz2-dev \
    libexpat1-dev \
    liblzma-dev \
    libffi-dev \
    uuid-dev \
    # Kernel build specific
    bc \
    bison \
    flex \
    libelf-dev \
    # Archive and compression tools
    zip \
    unzip \
    gzip \
    tar \
    xz-utils \
    p7zip-full \
    # Network tools
    curl \
    wget \
    # Version control
    git \
    git-lfs \
    # Python and tools
    python3 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    # System utilities
    ca-certificates \
    coreutils \
    rsync \
    file \
    findutils \
    grep \
    sed \
    gawk \
    # Additional tools found in GitHub runners
    jq \
    software-properties-common \
    apt-transport-https \
    gnupg \
    lsb-release \
    locales \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up locale (GitHub runners have this configured)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Configure git globally (required for repo tool)
RUN git config --global user.name "Kernel Builder" && \
    git config --global user.email "builder@localhost" && \
    git config --global color.ui false && \
    git config --global init.defaultBranch main

# Create directories for build
RUN mkdir -p /workspace /ccache /output && \
    chown -R builder:builder /workspace /ccache /output

# Switch to non-root user
USER builder
WORKDIR /workspace

# Ensure Git configuration is set for builder user
RUN git config --global user.name "Kernel Builder" && \
    git config --global user.email "builder@localhost" && \
    git config --global color.ui false && \
    git config --global init.defaultBranch main

# Download and set up build tools
RUN echo "Setting up Android build tools..." && \
    AOSP_MIRROR=https://android.googlesource.com && \
    BRANCH=main-kernel-build-2024 && \
    git clone $AOSP_MIRROR/kernel/prebuilts/build-tools -b $BRANCH --depth 1 kernel-build-tools && \
    git clone $AOSP_MIRROR/platform/system/tools/mkbootimg -b $BRANCH --depth 1 mkbootimg

# Set up environment variables for tools
ENV AVBTOOL="/workspace/kernel-build-tools/linux-x86/bin/avbtool"
ENV MKBOOTIMG="/workspace/mkbootimg/mkbootimg.py"
ENV UNPACK_BOOTIMG="/workspace/mkbootimg/unpack_bootimg.py"
ENV BOOT_SIGN_KEY_PATH="/workspace/kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem"

# Install Google's repo tool
RUN mkdir -p ./git-repo && \
    curl https://storage.googleapis.com/git-repo-downloads/repo > ./git-repo/repo && \
    chmod a+rx ./git-repo/repo
ENV REPO="/workspace/git-repo/repo"

# Clone AnyKernel3 for packaging
RUN ANYKERNEL_BRANCH="gki-2.0" && \
    git clone https://github.com/WildPlusKernel/AnyKernel3.git -b "$ANYKERNEL_BRANCH"

# Set up ccache
RUN mkdir -p ~/.cache/bazel && \
    ccache --version && \
    ccache --max-size=2G && \
    ccache --set-config=compression=true

# Create build script
RUN cat << 'EOF' > /workspace/build_kernel.sh
#!/bin/bash
set -e

echo "Starting Android 14 6.1.124 kernel build..."

# Ensure Git identity is configured (safety check)
git config --global user.name "Kernel Builder" 2>/dev/null || true
git config --global user.email "builder@localhost" 2>/dev/null || true
git config --global color.ui false 2>/dev/null || true

# Create configuration directory and sync kernel source
mkdir -p "$CONFIG"
cd "$CONFIG"

echo "Initializing kernel source repository..."
FORMATTED_BRANCH="android-gs-pantah-6.1-android16"
$REPO init --depth=1 --u https://android.googlesource.com/kernel/manifest -b ${FORMATTED_BRANCH} --repo-rev=v2.16


echo "Syncing kernel source code..."
$REPO --version
$REPO --trace sync -c -j$(nproc --all) --no-tags --fail-fast

echo "Configuring kernel for clean build..."

# Add performance and networking configurations (no root modifications)
echo "CONFIG_TCP_CONG_ADVANCED=y" >> ./aosp/arch/arm64/configs/gki_defconfig 
echo "CONFIG_TCP_CONG_BBR=y" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_NET_SCH_FQ=y" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_BIC=n" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_WESTWOOD=n" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_HTCP=n" >> ./aosp/arch/arm64/configs/gki_defconfig

# Add networking features
echo "CONFIG_IP_NF_TARGET_TTL=y" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_TARGET_HL=y" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_MATCH_HL=y" >> ./aosp/arch/arm64/configs/gki_defconfig

# Add tmpfs features
echo "CONFIG_TMPFS_XATTR=y" >> ./aosp/arch/arm64/configs/gki_defconfig
echo "CONFIG_TMPFS_POSIX_ACL=y" >> ./aosp/arch/arm64/configs/gki_defconfig

# Remove defconfig check
sed -i 's/check_defconfig//' ./aosp/build.config.gki

# Set kernel version string
perl -pi -e 's/-maybe-dirty//g' ./build/kernel/kleaf/impl/stamp.bzl
echo "CONFIG_LOCALVERSION=\"-Docker-Clean-6.1.124\"" >> ./aosp/arch/arm64/configs/gki_defconfig

# Remove protected exports that might cause issues
rm -rf ./aosp/android/abi_gki_protected_exports_* || true
perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' ./aosp/BUILD.bazel || true

echo "Starting kernel compilation..."
tools/bazel build --disk_cache=$HOME/.cache/bazel --config=fast --lto=thin //aosp:kernel_aarch64_dist

if [ $? -eq 0 ]; then
    echo "Kernel build completed successfully!"
    ccache --show-stats
else
    echo "Kernel build failed!"
    exit 1
fi

echo "Extracting built kernel images..."
cd /workspace

# Create directory for images
mkdir -p bootimgs output

# Copy built kernel images
cp ./$CONFIG/bazel-bin/aosp/kernel_aarch64/Image ./bootimgs/
cp ./$CONFIG/bazel-bin/aosp/kernel_aarch64/Image.lz4 ./bootimgs/
cp ./$CONFIG/bazel-bin/aosp/kernel_aarch64/Image ./
cp ./$CONFIG/bazel-bin/aosp/kernel_aarch64/Image.lz4 ./

# Create gzip compressed version
gzip -n -k -f -9 ./Image > ./Image.gz
cp ./Image.gz ./bootimgs/

echo "Creating AnyKernel3 flashable ZIPs..."
cd ./AnyKernel3

# Create standard Image ZIP
ZIP_NAME="Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-AnyKernel3.zip"
cp ../Image ./Image
zip -r "../output/$ZIP_NAME" ./*
rm ./Image

# Create LZ4 compressed ZIP
ZIP_NAME="Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-AnyKernel3-lz4.zip"
cp ../Image.lz4 ./Image.lz4
zip -r "../output/$ZIP_NAME" ./*
rm ./Image.lz4

# Create GZIP compressed ZIP
ZIP_NAME="Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-AnyKernel3-gz.zip"
cp ../Image.gz ./Image.gz
zip -r "../output/$ZIP_NAME" ./*
rm ./Image.gz

cd /workspace

echo "Creating bootable boot images..."
cd bootimgs

# Create gzip version in bootimgs directory
gzip -n -k -f -9 ./Image > ./Image.gz

# Build standard boot.img
$MKBOOTIMG --header_version 4 --kernel Image --output boot.img
$AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot.img --algorithm SHA256_RSA2048 --key $BOOT_SIGN_KEY_PATH
cp ./boot.img ../output/Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-boot.img

# Build gzip compressed boot.img
$MKBOOTIMG --header_version 4 --kernel Image.gz --output boot-gz.img
$AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot-gz.img --algorithm SHA256_RSA2048 --key $BOOT_SIGN_KEY_PATH
cp ./boot-gz.img ../output/Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-boot-gz.img

# Build LZ4 compressed boot.img
$MKBOOTIMG --header_version 4 --kernel Image.lz4 --output boot-lz4.img
$AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot-lz4.img --algorithm SHA256_RSA2048 --key $BOOT_SIGN_KEY_PATH
cp ./boot-lz4.img ../output/Docker-Clean-Android14-6.1.124-${OS_PATCH_LEVEL}-boot-lz4.img

cd /workspace

echo "Compressing boot images..."
cd output
for image in *.img; do
    [ -f "$image" ] && gzip -vnf9 "$image"
done

# Copy raw kernel images to output
cp /workspace/Image ./Image-6.1.124
cp /workspace/Image.lz4 ./Image-6.1.124.lz4
cp /workspace/Image.gz ./Image-6.1.124.gz

echo "Build completed successfully!"
echo "Output files are in /workspace/output/"
ls -la /workspace/output/

EOF

# Make build script executable
RUN chmod +x /workspace/build_kernel.sh

# Create output directory
RUN mkdir -p /workspace/output

# Set the default command
CMD ["/workspace/build_kernel.sh"]

# Expose output directory as volume
VOLUME ["/workspace/output", "/ccache"]