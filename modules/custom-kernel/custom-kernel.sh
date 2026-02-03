#!/usr/bin/env bash
#set -euo pipefail

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
ADIOS_SCHEDULER=$(echo "$1" | jq -r 'try .["adios-scheduler"] // "false"')

# 3. Resolve kernel settings based on the kernel type
COPR_REPOS=()
KERNEL_PACKAGES=()
EXTRA_PACKAGES=(
    akmods
    cachyos-settings
    scx-scheds
    scx-tools
)

case "${KERNEL_TYPE}" in
cachyos-lto)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos-lto
        bieszczaders/kernel-cachyos-addons
    )
    KERNEL_PACKAGES=(
        kernel-cachyos-lto
        kernel-cachyos-lto-core
        kernel-cachyos-lto-modules
        kernel-cachyos-lto-devel-matched
    )
    ;;
cachyos-lts-lto)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos-lto
        bieszczaders/kernel-cachyos-addons
    )
    KERNEL_PACKAGES=(
        kernel-cachyos-lts-lto
        kernel-cachyos-lts-lto-core
        kernel-cachyos-lts-lto-modules
        kernel-cachyos-lts-lto-devel-matched
    )
    ;;
cachyos)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos
        bieszczaders/kernel-cachyos-addons
    )
    KERNEL_PACKAGES=(
        kernel-cachyos
        kernel-cachyos-core
        kernel-cachyos-modules
        kernel-cachyos-devel-matched
    )
    ;;
cachyos-rt)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos
        bieszczaders/kernel-cachyos-addons
    )
    KERNEL_PACKAGES=(
        kernel-cachyos-rt
        kernel-cachyos-rt-core
        kernel-cachyos-rt-modules
        kernel-cachyos-rt-devel-matched
    )
    ;;
cachyos-lts)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos
        bieszczaders/kernel-cachyos-addons
    )
    KERNEL_PACKAGES=(
        kernel-cachyos-lts
        kernel-cachyos-lts-core
        kernel-cachyos-lts-modules
        kernel-cachyos-lts-devel-matched
    )
    ;;
*)
    echo "[custom-kernel] Unsupported kernel type: ${KERNEL_TYPE}"
    exit 1
    ;;
esac

HOOKS_DISABLED=false

restore_kernel_install_hooks() {
    local rpmostree=/usr/lib/kernel/install.d/05-rpmostree.install
    local dracut=/usr/lib/kernel/install.d/50-dracut.install

    if [[ -f "${rpmostree}.bak" ]]; then
        mv -f "${rpmostree}.bak" "${rpmostree}"
    fi
    if [[ -f "${dracut}.bak" ]]; then
        mv -f "${dracut}.bak" "${dracut}"
    fi
}

disable_kernel_install_hooks() {
    local rpmostree=/usr/lib/kernel/install.d/05-rpmostree.install
    local dracut=/usr/lib/kernel/install.d/50-dracut.install

    if [[ -f "${rpmostree}" ]]; then
        mv "${rpmostree}" "${rpmostree}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' >"${rpmostree}"
        chmod +x "${rpmostree}"
        HOOKS_DISABLED=true
    fi

    if [[ -f "${dracut}" ]]; then
        mv "${dracut}" "${dracut}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' >"${dracut}"
        chmod +x "${dracut}"
        HOOKS_DISABLED=true
    fi
}

# 4. Temporarily disable kernel install scripts (rpmostree/dracut)
log "Temporarily disabling kernel install scripts."
disable_kernel_install_hooks
trap 'if [[ "${HOOKS_DISABLED}" == "true" ]]; then restore_kernel_install_hooks; fi' EXIT

# 5. Remove default kernel packages.
log "Removing default kernel packages."
dnf -y remove \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    kernel-devel \
    kernel-devel-matched \
    zram-generator-defaults || true
rm -rf /usr/lib/modules/* || true

# 6. Enable COPR repositories (required for custom kernels)
for repo in "${COPR_REPOS[@]}"; do
    log "Enabling COPR repo: ${repo}"
    dnf -y copr enable "${repo}"
done

# 7. Install the new kernel
log "Installing kernel packages: ${KERNEL_PACKAGES[*]}"
dnf -y install \
    "${KERNEL_PACKAGES[@]}" \
    "${EXTRA_PACKAGES[@]}"

# 8. Restore kernel install scripts and cleanup extras
log "Restoring kernel install scripts."
restore_kernel_install_hooks
HOOKS_DISABLED=false
rm -f /usr/bin/game-performance

# 9. Apply IO Scheduler udev rules (CachyOS specific)
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

# 10. Cleanup and System Configuration
rm -f /etc/yum.repos.d/*copr* || true

if command -v setsebool >/dev/null 2>&1; then
    log "Updating SELinux policies for kernel modules."
    setsebool -P domain_kernel_load_modules on
fi

log "Custom kernel installation complete."
