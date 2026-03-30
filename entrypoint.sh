#!/bin/bash
set -e

# Run the build script
/workspace/build_kernel.sh

# Ensure output is synced to mounted volume on Windows Docker Desktop
# sync flushes filesystem buffers before container exits
sync
echo "Output files synced."
