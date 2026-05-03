#!/bin/bash
set -e
set -o pipefail

# Build configuration - modify these values as needed
OS_PATCH_LEVEL="2026-03-05"
CONFIG="pantah-kernel"

# This is called Android14 kernel bacause device was initially with Android14
SEC_PATCH="${OS_PATCH_LEVEL:0:7}"
echo "Starting Android kernel build..."

# Ensure Git identity is configured (safety check)
git config --global user.name "Kernel Builder" 2 >/dev/null || true
git config --global user.email "builder@localhost" 2 >/dev/null || true
git config --global color.ui false 2 >/dev/null || true

# Create configuration directory and sync kernel source
mkdir -p "$CONFIG"
cd "$CONFIG"

echo "Initializing kernel source repository..."
ANDROID_BRANCH="common-android14-6.1-${SEC_PATCH:0:7}"
$REPO init --depth=1 --u https://android.googlesource.com/kernel/manifest -b ${ANDROID_BRANCH} --repo-rev=v2.16 &> /dev/null
$REPO --trace sync -c -j$(nproc --all) --no-tags --fail-fast &> /dev/null

cd common
KERNEL_VERSION=$(make kernelversion)
echo "Kernel version from source: $KERNEL_VERSION"
cd ../

echo "Adding ReSukiSU..."
SUKISU_BRANCH=main
cd common
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s $SUKISU_BRANCH

echo "Adding Baseband Guard..."
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash

echo "Applying SUSFS patches..."
cd /workspace
git clone https://github.com/ShirkNeko/susfs4ksu -b gki-android14-6.1
cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./$CONFIG/common
cp ./susfs4ksu/kernel_patches/fs/* ./$CONFIG/common/fs/
cp ./susfs4ksu/kernel_patches/include/linux/* ./$CONFIG/common/include/linux/
cd ./$CONFIG/common

#cp /workspace/$CONFIG/common/fs/proc/base.c /workspace/output/
#cp 50_add_susfs_in_gki-android14-6.1.patch /workspace/output/
echo "Apply 50_add_susfs_in_gki-android14-6.1.patch for 6.1.162"
#mv /workspace/patches/50.patch .
#patch -p1 <50.patch

# Fix hunk #1 of fs/namespace.c: upstream kernel has an extra `#include <trace/hooks/blk.h>`
# between `#include "internal.h"` and the blank line that the SUSFS patch's context expects.
# Rewrite the hunk header (-32,10 -> -32,11; +32,21 -> +32,22) and add the missing context line.
python3 - <<'PYEOF'
p = '50_add_susfs_in_gki-android14-6.1.patch'
lines = open(p).read().splitlines(keepends=True)
# Find the start of fs/namespace.c diff section
ns_start = next((i for i, l in enumerate(lines) if l.startswith('diff --git a/fs/namespace.c')), -1)
if ns_start < 0:
    raise SystemExit('[fix] fs/namespace.c diff section not found')
# Within that section, find the first hunk header
for i in range(ns_start, len(lines)):
    if lines[i].startswith('@@ '):
        hh = i
        break
else:
    raise SystemExit('[fix] no hunk header found in fs/namespace.c section')
import re
m = re.match(r'^@@ -32,(\d+) \+32,(\d+) @@', lines[hh])
if not m:
    raise SystemExit('[fix] unexpected hunk header: ' + lines[hh].rstrip())
old_ctx, old_add = int(m.group(1)), int(m.group(2))
if old_ctx == 11:
    print('[fix] fs/namespace.c hunk #1 already patched, skipping')
elif old_ctx == 10:
    # Bump context count by 1 (we add `#include <trace/hooks/blk.h>` as context); +N grows by 1 too
    lines[hh] = '@@ -32,11 +32,%d @@\n' % (old_add + 1)
    for j in range(hh + 1, min(hh + 40, len(lines))):
        if lines[j].rstrip('\r\n') == ' #include "internal.h"':
            lines.insert(j + 1, ' #include <trace/hooks/blk.h>\n')
            break
    else:
        raise SystemExit('[fix] internal.h context line not found in hunk')
    open(p, 'w').writelines(lines)
    print('[fix] fs/namespace.c hunk #1 rewritten for trace/hooks/blk.h context (+32,%d -> +32,%d)' % (old_add, old_add + 1))
else:
    raise SystemExit('[fix] unexpected hunk header: ' + lines[hh].rstrip())
PYEOF

patch --fuzz=3 -p1 < 50_add_susfs_in_gki-android14-6.1.patch

# NOTE: Do NOT apply scope_min_manual_hooks_v1.6.patch with modern ReSukiSU on kernel < 6.8.
# ReSukiSU's CONFIG_KSU_MANUAL_HOOK_AUTO_* options (default y) install the manual hooks via LSM
# automatically, and ReSukiSU's inline_hook_check.mk explicitly rejects builds where the legacy
# `ksu_vfs_read_hook` symbol still appears in fs/read_write.c.

echo "Apply Hide Stuff Patches"
cd /workspace
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git
cp SukiSU_patch/69_hide_stuff.patch ./$CONFIG/common
cd ./$CONFIG/common
patch -p1 -F 3 <69_hide_stuff.patch

echo "Configuring kernel for build..."
cd /workspace/$CONFIG

# Add KSU configuration settings
echo "CONFIG_KSU=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KPM=n" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_SU=n" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_MANUAL_HOOK=y" >>./common/arch/arm64/configs/gki_defconfig

# Add SUSFS configuration settings
echo "CONFIG_KSU_SUSFS=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MAP=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_MANUAL_SU=n" >>./common/arch/arm64/configs/gki_defconfig

# Add additional tmpfs config setting
echo "CONFIG_TMPFS_XATTR=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_TMPFS_POSIX_ACL=y" >>./common/arch/arm64/configs/gki_defconfig

# Add additional config setting
echo "CONFIG_IP_NF_TARGET_TTL=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_TARGET_HL=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_MATCH_HL=y" >>./common/arch/arm64/configs/gki_defconfig

# Add BBR Config
echo "CONFIG_TCP_CONG_ADVANCED=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_BBR=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_NET_SCH_FQ=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_BIC=n" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_WESTWOOD=n" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_TCP_CONG_HTCP=n" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_DEFAULT_BBR=y" >>./common/arch/arm64/configs/gki_defconfig

# Add optimized
echo "CONFIG_BPF_STREAM_PARSER=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_NETFILTER_XT_SET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_MAX=65534" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_BITMAP_IP=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_BITMAP_IPMAC=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_BITMAP_PORT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IP=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IPMARK=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IPPORT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IPPORTIP=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IPPORTNET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_IPMAC=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_MAC=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_NETPORTNET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_NET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_NETNET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_NETPORT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_HASH_NETIFACE=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP_SET_LIST_SET=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_NAT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >>./common/arch/arm64/configs/gki_defconfig

# Enable Baseband-guard
echo "CONFIG_BBG=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_LSM=\"landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf,baseband_guard\"" >>./common/arch/arm64/configs/gki_defconfig

# Test for KPM?
echo "CONFIG_KALLSYMS=y" >>./common/arch/arm64/configs/gki_defconfig

# Debug
cp ./common/arch/arm64/configs/gki_defconfig /workspace/output/
# Remove defconfig check
sed -i 's/check_defconfig//' ./common/build.config.gki

# Set security patch level
# sed -i 's/local spl_date="\$3"/local spl_date="${OS_PATCH_LEVEL}"/g' ./build/kernel/build_utils.sh

# Set kernel version string with SukiSU naming
perl -pi -e 's/-maybe-dirty//g' ./build/kernel/kleaf/impl/stamp.bzl
# echo "CONFIG_LOCALVERSION=\"-SukiSU-SUSFS-pantah\"" >> ./common/arch/arm64/configs/gki_defconfig

# Set kernel timestamp
CURRENT_TIME=$(date -u +"%a %b %d %H:%M:%S UTC %Y")

echo "CURRENT_TIME=$CURRENT_TIME"
perl -pi -e "s{UTS_VERSION=\"\\\$\(echo \\\$UTS_VERSION \\\$CONFIG_FLAGS \\\$TIMESTAMP \\| cut -b -\\\$UTS_LEN\)\"}{UTS_VERSION=\"#1 SMP PREEMPT $CURRENT_TIME\"}" ./common/scripts/mkcompile_h
sed -i -e "s|\$(preempt-flag-y) \"\$(build-timestamp)\"|\$(preempt-flag-y) \"$CURRENT_TIME\"|" ./common/init/Makefile

# Remove protected exports that might cause issues
rm -rf ./common/android/abi_gki_protected_exports_* || true
perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' ./common/BUILD.bazel || true

echo "Starting kernel compilation..."

tools/bazel build --disk_cache=$HOME/.cache/bazel --config=fast --lto=thin //common:kernel_aarch64_dist 2>&1 | tee build.log

if [ $? -eq 0 ]; then
    echo "Kernel build completed successfully!"
else
    echo "Kernel build failed!"
    exit 1
fi

# Extract versions from build log (try ReSukiSU first, then SukiSU-Ultra as fallback)
SUKISU_VERSION=$(grep -E "(ReSukiSU|SukiSU-Ultra) version" build.log | head -1 | awk '{print $NF}')
# SUSFS version is not in build log, extract from source
SUSFS_VERSION=$(grep -r "SUSFS_VERSION" ./common/include/linux/susfs.h 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "1.5.11")

# Fallback if versions are empty
if [ -z "$SUKISU_VERSION" ]; then
    SUKISU_VERSION="unknown"
fi
if [ -z "$SUSFS_VERSION" ]; then
    SUSFS_VERSION="2.0.0"
fi

echo "Detected SukiSU version: $SUKISU_VERSION"
echo "Detected SUSFS version: $SUSFS_VERSION"

echo "Extracting built kernel images..."
cd /workspace

# Create output directory
mkdir -p output

# Find and copy built kernel image
IMAGE_PATH="./$CONFIG/bazel-bin/common/kernel_aarch64/Image"
echo "Looking for Image at: $IMAGE_PATH"

if [ -f "$IMAGE_PATH" ]; then
    cp "$IMAGE_PATH" ./
    echo "Image copied successfully"
else
    echo "ERROR: Image not found at $IMAGE_PATH"
    echo "Searching for Image file..."
    find ./$CONFIG -name "Image" -type f 2>/dev/null | head -5
    # Try alternative path
    ALT_PATH=$(find ./$CONFIG -name "Image" -type f 2>/dev/null | head -1)
    if [ -n "$ALT_PATH" ]; then
        echo "Found Image at: $ALT_PATH"
        cp "$ALT_PATH" ./
    else
        echo "FATAL: Cannot find kernel Image file"
        exit 1
    fi
fi

echo "Creating AnyKernel3 flashable ZIPs..."
cd ./AnyKernel3

# Create AnyKernel3 archive
FILENAME_PREFIX="ReSukiSU-$SUKISU_VERSION-SUSFS-$SUSFS_VERSION-Android14-${KERNEL_VERSION}-${SEC_PATCH}"
ZIP_NAME="${FILENAME_PREFIX}-AnyKernel3.zip"
cp ../Image ./Image
zip -r "../output/$ZIP_NAME" ./*
echo "Created ZIP: $ZIP_NAME"
ls -la
rm ./Image

cd /workspace

echo "Build completed successfully!"
echo "Output files are in /workspace/output/"
ls -la /workspace/output/
