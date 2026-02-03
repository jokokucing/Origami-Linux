#!/usr/bin/env bash
set -euo pipefail

# The blue-build environment provides helper functions like get_json_array.
# This log function helps track progress in the build logs.
log() {
    echo "[custom-kernel] $*"
}

log "Starting custom kernel installation..."

# 1. Environment Check: Ensure we are on a Fedora-based image
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID_LIKE:-}" != *"fedora"* && "${ID:-}" != "fedora" ]]; then
        echo "[custom-kernel] Error: This module is intended for Fedora-based images. Detected ID=${ID:-unknown}."
        exit 1
    fi
fi

# 2. Read configuration from the first argument ($1) using jq
# We use 'try' and default values to prevent the script from crashing if options are missing.
KERNEL_TYPE=$(echo "$1" | jq -r 'try .["kernel"] // "cachyos-lto"')
REMOVE_DEFAULT_KERNEL=$(echo "$1" | jq -r 'try .["remove-default-kernel"] // "true"')
ENABLE_COPR=$(echo "$1" | jq -r 'try .["enable-copr"] // "true"')
INSTALL_WEAK_DEPS=$(echo "$1" | jq -r 'try .["install-weak-deps"] // "false"')
ADIOS_SCHEDULER=$(echo "$1" | jq -r 'try .["adios-scheduler"] // "false"')

# 3. Resolve kernel settings based on the kernel type
COPR_REPO=""
KERNEL_PACKAGE=""

case "${KERNEL_TYPE}" in
cachyos-lto)
    COPR_REPO="bieszczaders/kernel-cachyos-lto"
    KERNEL_PACKAGE="kernel-cachyos-lto"
    ;;
cachyos-lts-lto)
    COPR_REPO="bieszczaders/kernel-cachyos-lto"
    KERNEL_PACKAGE="kernel-cachyos-lts-lto"
    ;;
cachyos)
    COPR_REPO="bieszczaders/kernel-cachyos"
    KERNEL_PACKAGE="kernel-cachyos"
    ;;
cachyos-rt)
    COPR_REPO="bieszczaders/kernel-cachyos"
    KERNEL_PACKAGE="kernel-cachyos-rt"
    ;;
cachyos-lts)
    COPR_REPO="bieszczaders/kernel-cachyos"
    KERNEL_PACKAGE="kernel-cachyos-lts"
    ;;
*)
    echo "[custom-kernel] Unsupported kernel type: ${KERNEL_TYPE}"
    exit 1
    ;;
esac

# 4. Remove default kernel if requested
if [[ "${REMOVE_DEFAULT_KERNEL}" == "true" ]]; then
    log "Removing default kernel packages."
    dnf -y remove kernel kernel-* || true
    rm -rf /usr/lib/modules/* || true
fi

# 5. Enable COPR repository
if [[ "${ENABLE_COPR}" == "true" ]]; then
    log "Enabling COPR repo: ${COPR_REPO}"
    dnf -y copr enable "${COPR_REPO}"
fi

# 6. Install the new kernel
log "Installing kernel package: ${KERNEL_PACKAGE}"
dnf -y install --setopt=install_weak_deps="${INSTALL_WEAK_DEPS}" "${KERNEL_PACKAGE}"

# 7. Apply IO Scheduler udev rules (CachyOS specific)
if [[ "${ADIOS_SCHEDULER}" == "true" ]]; then
    log "Writing IO scheduler udev rules (adios)."
    mkdir -p /etc/udev/rules.d
    cat >/etc/udev/rules.d/60-ioschedulers.rules <<'EOF'
# HDD
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
    ATTR{queue/scheduler}="bfq"

# SSD
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="adios"

# NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="adios"
EOF
fi

# 8. Cleanup and System Configuration
rm -f /etc/yum.repos.d/*copr* || true

if command -v setsebool >/dev/null 2>&1; then
    log "Updating SELinux policies for kernel modules."
    setsebool -P domain_kernel_load_modules on
fi

log "Custom kernel installation complete."
