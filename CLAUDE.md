# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Docker-based build configuration for educational Android kernel compilation for Google Pixel 7 devices (Pantah family). The project demonstrates how to build Android 14 (6.1.162) kernel with ReSukiSU, SUSFS, and Baseband Guard integration for educational and research purposes.

## Build Commands

### Docker Build Commands
- **Build Docker image**: `docker build -t pantah-kernel .` - Creates container with build environment
- **Rebuild after script changes**: Not needed! The build script is copied during image build but can be modified without rebuilding the container

### Running Builds
- **Start build**: `docker run --rm -v ./output:/workspace/output pantah-kernel`
- **Interactive build**: `docker run -it --rm -v ./output:/workspace/output pantah-kernel bash`
- **Custom build script**: `docker run --rm -v ./output:/workspace/output -v ./build_kernel.sh:/workspace/build_kernel.sh pantah-kernel`

### Modifying Build Logic
- Edit `build_kernel.sh` in the repository root to customize the build process
- No need to rebuild Docker image when changing build logic
- Simply run the Docker container again with updated script

### Output Management
- Built kernels are placed in `output/` directory (or `out-pantah/` during build)
- Boot image created as signed boot.img file
- AnyKernel3 flashable ZIP package generated for easy flashing

## Architecture

### Build Environment
- **Base**: Ubuntu 22.04 container with Android kernel build tools
- **Toolchain**: Uses Google's AOSP toolchain and Bazel build system
- **Caching**: ccache configured for faster rebuilds
- **User**: Non-root `builder` user for security

### Key Components
- **Kernel Source**: Android Generic Kernel Image (GKI) from `common-android14-6.1-2026-03` branch
- **ReSukiSU**: Root solution integrated from susfs-test branch with manual hooks
- **SUSFS**: Kernel-level hiding and security features (v2.0.0+)
- **KPM (Kernel Patch Module)**: Currently disabled (CONFIG_KPM=n) - causes system crash on boot
- **Baseband Guard**: Security enhancement for baseband protection
- **Packaging**: AnyKernel3 (gki-2.0 branch) for flashable ZIP creation
- **Boot Images**: Standard Android boot.img format with AVB test key signing

### Configuration Files
- **Dockerfile**: Docker image definition with build environment setup
- **build_kernel.sh**: Main build script containing kernel compilation logic (can be modified without rebuilding Docker image)
- **factory_default_config**: Factory configuration reference for kernel settings
- **.dockerignore**: Docker build exclusion patterns

### Build Process
The build process is defined in `build_kernel.sh` and includes:
1. Initialize kernel repository with Google's repo tool
2. Sync kernel source code from AOSP (common-android14-6.1 branch)
3. Apply ReSukiSU integration from susfs-test branch
4. Apply Baseband Guard patches
5. Apply SUSFS patches from gki-android14-6.1 branch
6. Apply new hooks patches and hide stuff patches
7. Configure kernel with KSU, SUSFS, and networking optimizations (KPM disabled)
8. Build using Bazel with --lto=thin and ccache
9. Package into signed boot.img and AnyKernel3 ZIP

**Note**: To modify the build process, edit `build_kernel.sh` directly - no Docker rebuild required!

### Key Configuration Changes
- **KernelSU Configuration**: CONFIG_KSU, CONFIG_KSU_MANUAL_HOOK enabled; CONFIG_KPM=n (disabled due to boot crashes)
- **SUSFS Features**: Comprehensive hiding capabilities including sus_path, sus_mount, sus_kstat, sus_map, spoof_uname, open_redirect
- **TCP BBR**: Advanced congestion control with CONFIG_TCP_CONG_BBR and CONFIG_DEFAULT_BBR
- **Networking**: Extended netfilter/iptables support (CONFIG_IP_SET_*, CONFIG_IP6_NF_*)
- **Baseband Guard**: CONFIG_BBG enabled for baseband security
- **Optimizations**: BPF stream parser, tmpfs extended attributes
- **Build Modifications**: Protected exports removed, defconfig check disabled, custom timestamp
- **Known Issues**: Kernel image patching (lines 324-331) commented out - causes system instability

## Output Artifacts
- **AnyKernel3 ZIP**: Flashable package for custom recovery or Horizon Kernel Flasher
  - Format: `SukiSU-{VERSION}-SUSFS-{VERSION}-Android14-{KERNEL_VERSION}-{PATCH}-AnyKernel3.zip`

## Additional Information

### Dependencies
- **ReSukiSU**: https://github.com/ReSukiSU/ReSukiSU (v4.1.0 tag)
- **SUSFS for KSU**: https://github.com/ShirkNeko/susfs4ksu (gki-android14-6.1 branch)
- **SukiSU Patches**: https://github.com/ReSukiSU/SukiSU_patch (syscall hooks, hide stuff)
- **Baseband Guard**: https://github.com/vc-teahouse/Baseband-guard
- **AnyKernel3**: https://github.com/MiRinChan/AnyKernel3 (gki-2.0 branch)

### Build Optimizations
- Bazel build with `--config=fast` and `--lto=thin`
- ccache enabled with 2GB cache, compression enabled
- Parallel repo sync with `-j$(nproc --all)`
- Non-root builder user for security