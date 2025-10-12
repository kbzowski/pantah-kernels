# Dockerfile for Android 14 6.1.124 Kernel Build
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# PATH additions (similar to GitHub runner)
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create non-root user for builds
RUN groupadd -r builder && useradd -r -g builder -m -d /home/builder -s /bin/bash builder

# Install system dependencies to match GitHub Actions Ubuntu runner
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    gcc \
    g++ \
    clang \
    llvm \
    make \
    cmake \
    ninja-build \
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
    # Additional tools
    jq \
    software-properties-common \
    apt-transport-https \
    gnupg \
    lsb-release \
    locales \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
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
RUN mkdir -p /workspace /output && \
    chown -R builder:builder /workspace /output

# Switch to non-root user
USER builder
WORKDIR /workspace

# Ensure Git configuration is set for builder user
RUN git config --global user.name "Kernel Builder" && \
    git config --global user.email "builder@localhost" && \
    git config --global color.ui false && \
    git config --global init.defaultBranch main


# Install Google's repo tool
RUN mkdir -p ./git-repo && \
    curl https://storage.googleapis.com/git-repo-downloads/repo > ./git-repo/repo && \
    chmod a+rx ./git-repo/repo
ENV REPO="/workspace/git-repo/repo"

# Clone AnyKernel3 for packaging
RUN ANYKERNEL_BRANCH="gki-2.0" && \
    git clone https://github.com/MiRinChan/AnyKernel3 -b "$ANYKERNEL_BRANCH"

# Copy build script from host
COPY --chown=builder:builder build_kernel.sh /workspace/build_kernel.sh

# Copy factory Pixel 7 config
COPY --chown=builder:builder factory_default_config /workspace/factory_default_config

# Make build script executable
RUN chmod +x /workspace/build_kernel.sh

# Create output directory
RUN mkdir -p /workspace/output

# Set the default command
CMD ["/workspace/build_kernel.sh"]

# Expose output directory as volume
VOLUME ["/workspace/output"]