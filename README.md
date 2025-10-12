# Pixel 7 Kernel builds with ROOT

> This repository demonstrates Android kernel compilation techniques for Google Pixel 7 (Pantah) devices using Docker containerization with SukiSU-Ultra, SUSFS, and Baseband Guard.

[![Android](https://img.shields.io/badge/Android-14-green)](https://developer.android.com/)
[![Kernel](https://img.shields.io/badge/Kernel-6.1.145-blue)](https://www.kernel.org/)
[![Security Patch](https://img.shields.io/badge/Patch-2025--09-orange)](https://source.android.com/security/bulletin)
[![License](https://img.shields.io/badge/license-WTFPL-red)](https://en.wikipedia.org/wiki/WTFPL)

## ✨ Features

### Root & Security
- **SukiSU-Ultra**: Advanced root solution with manual hooks
- **SUSFS**: Comprehensive kernel-level hiding system
  - sus_path, sus_mount, sus_kstat
  - Spoof uname and cmdline/bootconfig
  - Open redirect and magic mount support
- **KPM (Kernel Patch Module)**: ⚠️ Currently disabled - causes system crash on boot
- **Baseband Guard**: Enhanced baseband security protection

### Networking
- **TCP BBR**: Advanced congestion control algorithm (default)
- **Extended iptables/netfilter**: Full IP_SET support
- **IPv6 NAT & Masquerade**: Complete IPv6 networking support

### Optimizations
- **LTO (Link Time Optimization)**: Thin LTO for better performance
- **BPF Stream Parser**: Enhanced network packet processing
- **tmpfs Extended Attributes**: POSIX ACL support

## 📋 Requirements

- Docker installed and running
- At least 50GB free disk space
- 8GB+ RAM allocated to Docker
- Stable internet connection (for downloading kernel source)
- Compatible devices:
  - Google Pixel 7 (Panther)

## 🏗️ Building the Kernel

```bash
# Clone the repository
git clone https://github.com/kbzowski/pantah-kernels.git
cd pantah-kernels

# Build kernel image
docker build -t pantah-kernel .

# Run the build process
docker run --rm -v ./output:/workspace/output pantah-kernel

# Or run interactively
docker run -it --rm -v ./output:/workspace/output pantah-kernel bash
```

## 📱 Flashing the Kernel

Follow these steps to flash the custom kernel to your device:

### Prerequisites
1. **Install SukiSU App**: Download and install the latest SukiSU app on your device

### Step-by-Step Installation

#### 1. Prepare init_boot Partition
- Extract `init_boot.img` from your device's factory image
- Open SukiSU Ultra app and patch the `init_boot.img` using LKM (Loadable Kernel Module) method
- The app will create a patched file named `kernelsu_patched_XXXXXXXX_YYYYYY.img`

#### 2. Flash Patched init_boot
```bash
# Reboot device to bootloader
adb reboot bootloader

# Flash the patched init_boot
fastboot flash init_boot .\kernelsu_patched_XXXXXXXX_YYYYYY.img

# Reboot device
fastboot reboot
```
Now you should have root.

#### 3. Install Custom Kernel
- Open SukiSU app on your device
- Navigate to kernel installation section
- Select **AnyKernel3** installation method
- Choose the AnyKernel3 ZIP file from your kernel build (`output/` directory)
- Follow the app instructions to complete the installation
- Reboot when prompted


## 🙏 Credits and Acknowledgments

This project builds upon the excellent work of:

- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) - Root solution with advanced features
- [SUSFS for KSU](https://github.com/ShirkNeko/susfs4ksu) - Kernel-level hiding and security
- [SukiSU Patches](https://github.com/SukiSU-Ultra/SukiSU_patch) - Additional kernel patches
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) - Baseband security enhancement
- [AnyKernel3](https://github.com/MiRinChan/AnyKernel3) - Universal kernel flasher
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) - Original KernelSU development
- [Google AOSP](https://source.android.com/) - Kernel source and build tools

## 🔧 Troubleshooting

### Known Issues

#### KPM (Kernel Patch Module) Disabled
**Problem**: KPM support is currently disabled (`CONFIG_KPM=n`) in the build configuration.

**Reason**: Enabling KPM causes the system to crash immediately after boot. The kernel image patching process (commented out in Dockerfile lines 324-331) destabilizes the system.

**Status**: No solution available at this time. KPM will remain disabled until a stable implementation is found.

**Impact**: The kernel builds and boots successfully without KPM. All other features (SukiSU-Ultra, SUSFS, Baseband Guard) work normally.

### Factory Images and Recovery

If you encounter any issues or need to restore your device to a working state, you can download factory images (including stock kernel) from Google Pixel Factory Images:
- [Pixel 7 (panther)](https://developers.google.com/android/images#panther)
- [Pixel 7 Pro (cheetah)](https://developers.google.com/android/images#cheetah)

For easy installation of factory images, use [PixelFlasher](https://github.com/badabing2005/PixelFlasher)

### Build Issues

If you encounter build issues:
1. Ensure Docker has sufficient disk space (at least 50GB free)
2. Check Docker memory allocation (recommended 8GB+)
3. Try cleaning Docker cache: `docker system prune -a`
4. For networking issues, check your internet connection during repo sync

## ⚠️ Educational Disclaimer
- This is for educational and research purposes only
- I am NOT responsible for any damage to devices or your data
- Flashing custom kernels may void your warranty
- Always backup your data before flashing
