#!/usr/bin/env bash
set -euo pipefail
set -x

trap 'echo "[custom-kernel] Error on line $LINENO. Last command: $BASH_COMMAND" >&2' ERR

log() {
    echo "[custom-kernel] $*"
}

# Ensure we are on a Fedora-based image
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID_LIKE:-}" != *"fedora"* && "${ID:-}" != "fedora" ]]; then
        echo "[custom-kernel] This module is intended for Fedora-based images. Detected ID=${ID:-unknown} ID_LIKE=${ID_LIKE:-unknown}."
        exit 1
    fi
fi

# Read configuration
KERNEL_TYPE="$(echo "${1:-{}}" | jq -r 'try .["kernel"] // "cachyos-lto"')"
REMOVE_DEFAULT_KERNEL="$(echo "${1:-{}}" | jq -r 'try .["remove-default-kernel"] // "true"')"
ENABLE_COPR="$(echo "${1:-{}}" | jq -r 'try .["enable-copr"] // "true"')"
INSTALL_WEAK_DEPS="$(echo "${1:-{}}" | jq -r 'try .["install-weak-deps"] // "false"')"
ADIOS_SCHEDULER="$(echo "${1:-{}}" | jq -r 'try .["adios-scheduler"] // "false"')"

# Resolve kernel settings
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
    echo "[custom-kernel] Supported values: cachyos-lto, cachyos-lts-lto, cachyos, cachyos-rt, cachyos-lts"
    exit 1
    ;;
esac

if [[ "${REMOVE_DEFAULT_KERNEL}" == "true" ]]; then
    log "Removing default kernel packages."
    dnf -y remove \
        kernel \
        kernel-* || true

    rm -rf /usr/lib/modules/* || true
fi

if [[ "${ENABLE_COPR}" == "true" ]]; then
    log "Enabling COPR repo: ${COPR_REPO}"
    dnf -y copr enable "${COPR_REPO}"
fi

log "Installing kernel package: ${KERNEL_PACKAGE}"
dnf -y install --setopt=install_weak_deps="${INSTALL_WEAK_DEPS}" \
    "${KERNEL_PACKAGE}"

if [[ ("${KERNEL_TYPE}" == "cachyos-lto" || "${KERNEL_TYPE}" == "cachyos-lts-lto" || "${KERNEL_TYPE}" == "cachyos" || "${KERNEL_TYPE}" == "cachyos-rt" || "${KERNEL_TYPE}" == "cachyos-lts") && "${ADIOS_SCHEDULER}" == "true" ]]; then
    log "Writing IO scheduler udev rules (adios) for CachyOS kernel."
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

# Clean up repo files added by COPR
rm -f /etc/yum.repos.d/*copr* || true

# Allow kernel module loading
setsebool -P domain_kernel_load_modules on
