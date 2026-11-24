#!/bin/bash
set -e
set -o pipefail

# Build configuration - modify these values as needed
OS_PATCH_LEVEL="2026-09-05"
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
$REPO init --depth=1 -u https://android.googlesource.com/kernel/manifest -b ${ANDROID_BRANCH} --repo-rev=v2.16 &> /dev/null
$REPO --trace sync -c -j$(nproc --all) --no-tags --fail-fast &> /dev/null

cd common
KERNEL_VERSION=$(make kernelversion)
echo "Kernel version from source: $KERNEL_VERSION"
cd ../

echo "Adding BakaSU..."
BAKASU_BRANCH=main
cd common
curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash -s $BAKASU_BRANCH

echo "Adding Baseband Guard..."
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash

# Must run BEFORE the SUSFS patch: 69_hide_stuff.patch anchors on
# `pgoff = ((loff_t)vma->vm_pgoff) << PAGE_SHIFT;` in show_map_vma(), and SUSFS adds a
# second copy of that line in its OPEN_REDIRECT block, so fuzzy matching picks the wrong one.
echo "Apply Hide Stuff Patches"
cd /workspace
git clone https://github.com/SukiSU-Nova/SukiSU_patch.git
cp SukiSU_patch/69_hide_stuff.patch ./$CONFIG/common
cd ./$CONFIG/common
patch -p1 -F 3 <69_hide_stuff.patch

echo "Applying SUSFS patches..."
cd /workspace
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./$CONFIG/common
cp ./susfs4ksu/kernel_patches/fs/* ./$CONFIG/common/fs/
cp ./susfs4ksu/kernel_patches/include/linux/* ./$CONFIG/common/include/linux/
cd ./$CONFIG/common
# SUSFS 2.4.0: these helpers are only called under CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER (not in BakaSU Kconfig) -> -Werror unused-function
sed -i -E 's/^static (struct cred \*susfs_switch_to_ksu_domain|void susfs_restore_creds)\(/static __maybe_unused \1(/' fs/susfs.c
grep -c "__maybe_unused" fs/susfs.c

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

# NOTE: Do NOT apply scope_min_manual_hooks_v1.6.patch with modern BakaSU on kernel < 6.8.
# BakaSU's CONFIG_KSU_MANUAL_HOOK_AUTO_* options (default y) install the manual hooks via LSM
# automatically, and BakaSU's inline_hook_check.mk explicitly rejects builds where the legacy
# `ksu_vfs_read_hook` symbol still appears in fs/read_write.c.

echo "Configuring kernel for build..."
cd /workspace/$CONFIG

# Add KSU configuration settings. Hook mode is a Kconfig `choice`; select ONLY
# CONFIG_KSU_SUSFS (SUSFS Inline Hook) so the hooks come from the SUSFS patch we apply.
echo "CONFIG_KSU=y" >>./common/arch/arm64/configs/gki_defconfig

# Add SUSFS configuration settings (symbols defined in BakaSU kernel/Kconfig)
echo "CONFIG_KSU_SUSFS=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SUS_MAP=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >>./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >>./common/arch/arm64/configs/gki_defconfig

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

echo "CONFIG_KALLSYMS=y" >>./common/arch/arm64/configs/gki_defconfig

# Debug
cp ./common/arch/arm64/configs/gki_defconfig /workspace/output/
# Remove defconfig check
sed -i 's/check_defconfig//' ./common/build.config.gki

# Set security patch level
# sed -i 's/local spl_date="\$3"/local spl_date="${OS_PATCH_LEVEL}"/g' ./build/kernel/build_utils.sh

# Set kernel version string with BakaSU naming
perl -pi -e 's/-maybe-dirty//g' ./build/kernel/kleaf/impl/stamp.bzl
# echo "CONFIG_LOCALVERSION=\"-BakaSU-SUSFS-pantah\"" >> ./common/arch/arm64/configs/gki_defconfig

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

# Extract versions from build log (BakaSU prints "-- BakaSU version code: N")
BAKASU_VERSION=$(grep "BakaSU version code" build.log | head -1 | awk '{print $NF}')
# SUSFS version is not in build log, extract from source
SUSFS_VERSION=$(grep -r "SUSFS_VERSION" ./common/include/linux/susfs.h 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "1.5.11")

# Fallback if versions are empty
if [ -z "$BAKASU_VERSION" ]; then
    BAKASU_VERSION="unknown"
fi
if [ -z "$SUSFS_VERSION" ]; then
    SUSFS_VERSION="2.0.0"
fi

echo "Detected BakaSU version: $BAKASU_VERSION"
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

FILENAME_PREFIX="BakaSU-$BAKASU_VERSION-SUSFS-$SUSFS_VERSION-Android14-${KERNEL_VERSION}-${SEC_PATCH}"

# ----- Build fastboot-flashable boot.img by repacking stock factory boot.img -----
# Override FACTORY_URL env var to use a different stock build.
FACTORY_URL="${FACTORY_URL:-https://dl.google.com/dl/android/aosp/panther-cp4a.261105.040.a1-factory-fc8d5970.zip}"
FACTORY_ZIP="/tmp/$(basename "$FACTORY_URL")"
BOOT_WORKDIR="/tmp/bootrepack"
MKBOOTIMG=$(find "/workspace/$CONFIG" -name "mkbootimg.py" -type f 2>/dev/null | head -1)
UNPACK_BOOT=$(find "/workspace/$CONFIG" -name "unpack_bootimg.py" -type f 2>/dev/null | head -1)
AVBTOOL=$(find "/workspace/$CONFIG" -name "avbtool.py" -o -name "avbtool" -type f 2>/dev/null | head -1)
# Pixel 7 (panther/cheetah) boot partition is 64 MiB; override via BOOT_PARTITION_SIZE if needed.
BOOT_PARTITION_SIZE="${BOOT_PARTITION_SIZE:-67108864}"

if [ -z "$MKBOOTIMG" ] || [ -z "$UNPACK_BOOT" ]; then
    echo "WARN: AOSP boot tools (mkbootimg.py / unpack_bootimg.py) not found in source tree - skipping boot.img repack"
else
    echo "Using mkbootimg: $MKBOOTIMG"
    echo "Using unpack_bootimg: $UNPACK_BOOT"
    echo "Building fastboot-flashable boot.img from stock factory image..."
    if [ ! -f "$FACTORY_ZIP" ]; then
        echo "Downloading $FACTORY_URL ..."
        curl -L -o "$FACTORY_ZIP" "$FACTORY_URL"
    else
        echo "Using cached $FACTORY_ZIP"
    fi
    rm -rf "$BOOT_WORKDIR" && mkdir -p "$BOOT_WORKDIR"
    cd "$BOOT_WORKDIR"
    # Factory zip contains a nested image-<device>-<build>.zip with boot.img inside
    unzip -o "$FACTORY_ZIP" >/dev/null
    INNER_ZIP=$(find . -name "image-*.zip" | head -1)
    [ -z "$INNER_ZIP" ] && { echo "FATAL: image-*.zip not found in factory zip"; exit 1; }
    unzip -o "$INNER_ZIP" boot.img >/dev/null
    [ ! -f boot.img ] && { echo "FATAL: boot.img missing inside $INNER_ZIP"; exit 1; }

    mkdir unpack
    python3 "$UNPACK_BOOT" --boot_img boot.img --out unpack >unpack.log 2>&1 || { echo "FATAL: unpack_bootimg failed:"; cat unpack.log; exit 1; }
    cat unpack.log
    # Replace kernel with our compiled Image
    cp /workspace/Image unpack/kernel

    # Pixel 7 boot.img is header v4, kernel-only (ramdisk lives in init_boot).
    # Build minimal mkbootimg command using info from unpack output.
    # Header version is fixed v4 for android14-6.1 era; preserve cmdline/os_version if exposed.
    HDR_VER=$(awk -F: '/header version/{gsub(/ /,"",$2);print $2}' unpack.log | head -1)
    HDR_VER="${HDR_VER:-4}"
    OS_VER=$(awk -F: '/os version/{print $2}' unpack.log | head -1 | xargs)
    OS_PATCH=$(awk -F: '/os patch level/{print $2}' unpack.log | head -1 | xargs)
    CMDLINE=$(awk -F: '/^command line args/{sub(/^[^:]*: /,"");print}' unpack.log | head -1 | xargs)

    # unpack_bootimg.py prints literal "None" when a field is unset; filter those out
    [ "$OS_VER" = "None" ]   && OS_VER=""
    [ "$OS_PATCH" = "None" ] && OS_PATCH=""
    [ "$CMDLINE" = "None" ]  && CMDLINE=""

    PY_ARGS=( --header_version "$HDR_VER" --kernel unpack/kernel --output boot-bakasu.img )
    [ -n "$OS_VER" ]   && PY_ARGS+=( --os_version "$OS_VER" )
    [ -n "$OS_PATCH" ] && PY_ARGS+=( --os_patch_level "$OS_PATCH" )
    [ -n "$CMDLINE" ]  && PY_ARGS+=( --cmdline "$CMDLINE" )
    [ -f unpack/ramdisk ] && [ -s unpack/ramdisk ] && PY_ARGS+=( --ramdisk unpack/ramdisk )
    [ -f unpack/dtb ]     && [ -s unpack/dtb ]     && PY_ARGS+=( --dtb unpack/dtb )

    echo "Repacking: python3 $MKBOOTIMG ${PY_ARGS[*]}"
    python3 "$MKBOOTIMG" "${PY_ARGS[@]}"

    # Add an AVB hash footer so the image has the partition structure the bootloader
    # expects. No key is used: the footer is unsigned (just the hash descriptor). An
    # unlocked Pixel won't trust a custom AVB key anyway, so the device must still be
    # flashed with vbmeta verification disabled (see vbmeta.img exported below).
    if [ -z "$AVBTOOL" ]; then
        echo "WARN: avbtool not found in source tree - boot.img will have no AVB footer"
    else
        echo "Adding AVB hash footer (partition_size=$BOOT_PARTITION_SIZE): $AVBTOOL"
        if python3 "$AVBTOOL" add_hash_footer \
                --image boot-bakasu.img \
                --partition_name boot \
                --partition_size "$BOOT_PARTITION_SIZE"; then
            echo "AVB hash footer added"
        else
            echo "WARN: avbtool add_hash_footer failed (wrong BOOT_PARTITION_SIZE?) - keeping unsigned image"
        fi
    fi

    cp boot-bakasu.img "/workspace/output/${FILENAME_PREFIX}-boot.img"
    echo "Created fastboot boot.img: ${FILENAME_PREFIX}-boot.img"

    # Export stock vbmeta.img so the user can disable verification when flashing:
    #   fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
    if unzip -o "$INNER_ZIP" vbmeta.img >/dev/null 2>&1 && [ -f vbmeta.img ]; then
        cp vbmeta.img "/workspace/output/vbmeta.img"
        echo "Exported vbmeta.img to output/ (flash with --disable-verity --disable-verification)"
    else
        echo "WARN: vbmeta.img not found in $INNER_ZIP - skipping vbmeta export"
    fi
    cd /workspace
fi

echo "Creating AnyKernel3 flashable ZIPs..."
cd ./AnyKernel3

# Create AnyKernel3 archive
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
