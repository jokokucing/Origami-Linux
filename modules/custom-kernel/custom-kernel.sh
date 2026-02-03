#!/usr/bin/env bash
set -euo pipefail

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
CONFIG_JSON="${1:-{}}"

get_cfg() {
    local key="$1"
    local default="$2"

    if command -v jq >/dev/null 2>&1; then
        echo "$CONFIG_JSON" | jq -r --arg key "$key" --arg default "$default" 'try .[$key] // $default'
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$key" "$default" "$CONFIG_JSON" <<'PY'
import json, sys
key, default, raw = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.loads(raw)
except Exception:
    data = {}
val = data.get(key, default)
print(val)
PY
        return
    fi

    echo "$default"
}

KERNEL_TYPE="$(get_cfg "kernel" "cachyos-lto")"
REMOVE_DEFAULT_KERNEL="$(get_cfg "remove-default-kernel" "true")"
ENABLE_COPR="$(get_cfg "enable-copr" "true")"
INSTALL_WEAK_DEPS="$(get_cfg "install-weak-deps" "false")"
ADIOS_SCHEDULER="$(get_cfg "adios-scheduler" "false")"

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
    log "Ensuring COPR plugin is installed."
    dnf -y install dnf-plugins-core

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

# Allow kernel module loading (skip if setsebool isn't available in the build environment)
if command -v setsebool >/dev/null 2>&1; then
    setsebool -P domain_kernel_load_modules on
fi
