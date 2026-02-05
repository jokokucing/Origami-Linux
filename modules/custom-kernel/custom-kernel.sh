#!/usr/bin/env bash
set -euo pipefail

# The blue-build environment provides helper functions like get_json_array.
# This log function helps track progress in the build logs.
log() {
    echo "[custom-kernel] $*"
}

error() {
    echo "[custom-kernel] Error: $*"
}

log "Starting custom kernel installation..."

# 1. Environment Check: Ensure we are on a Fedora-based image
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID_LIKE:-}" != *"fedora"* && "${ID:-}" != "fedora" ]]; then
        error "This module is intended for Fedora-based images. Detected ID=${ID:-unknown}."
        exit 1
    fi
fi

# 2. Read configuration from the first argument ($1) using jq
# We use 'try' and default values to prevent the script from crashing if options are missing.
KERNEL_TYPE=$(echo "$1" | jq -r 'try .["kernel"] // "cachyos-lto"')
NVIDIA=$(echo "$1" | jq -r 'try .["nvidia"] // "false"')
SIGNING_KEY=$(echo "$1" | jq -r 'try .sign["key"] // ""')
MOK_PASSWORD=$(echo "$1" | jq -r 'try .sign["mok-password"] // ""')

# Check key, cert and password
if [[ -z "$SIGNING_KEY" && -z "$MOK_PASSWORD" ]]; then
    :
elif [[ -f "$SIGNING_KEY" && -n "$MOK_PASSWORD" ]]; then
    :
else
    error "Invalid signing config:"
    error "  SIGNING_KEY:  ${SIGNING_KEY:-<empty>}"
    error "  MOK_PASSWORD: ${MOK_PASSWORD:+<set>}${MOK_PASSWORD:-<empty>}"
    exit 1
fi

# 3. Resolve kernel settings based on the kernel type
COPR_REPOS=()
KERNEL_PACKAGES=()
EXTRA_PACKAGES=(
    akmods
)

case "${KERNEL_TYPE}" in
cachyos-lto)
    COPR_REPOS=(
        bieszczaders/kernel-cachyos-lto
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
    )
    KERNEL_PACKAGES=(
        kernel-cachyos-lts
        kernel-cachyos-lts-core
        kernel-cachyos-lts-modules
        kernel-cachyos-lts-devel-matched
    )
    ;;
*)
    error "Unsupported kernel type: ${KERNEL_TYPE}"
    exit 1
    ;;
esac

KERNEL_RPM_QUERY="${KERNEL_PACKAGES[0]}"

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
    kernel-devel-matched || true
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

if [[ "${NVIDIA}" == "true" ]]; then
    log "Enabling Nvidia repositories."
    curl -fsSL -o /etc/yum.repos.d/nvidia-container-toolkit.repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
    curl -fsSL -o /etc/yum.repos.d/fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo

    log "Building and installing Nvidia kernel module packages."
    cp /usr/sbin/akmodsbuild /usr/sbin/akmodsbuild.backup
    sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' /usr/sbin/akmodsbuild
    dnf install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts akmod-nvidia nvidia-kmod-common nvidia-modprobe
    akmods --force --verbose --kernels "$(rpm -q "${KERNEL_RPM_QUERY}" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" --kmod "nvidia"
    mv /usr/sbin/akmodsbuild.backup /usr/sbin/akmodsbuild

    log "Installing Nvidia userspace packages."
    dnf install -y --setopt=skip_unavailable=1 \
        libva-nvidia-driver \
        nvidia-driver \
        nvidia-persistenced \
        nvidia-settings \
        nvidia-driver-cuda \
        libnvidia-cfg \
        libnvidia-fbc \
        libnvidia-ml \
        libnvidia-gpucomp \
        nvidia-driver-libs.i686 \
        nvidia-driver-cuda-libs.i686 \
        libnvidia-fbc.i686 \
        libnvidia-ml.i686 \
        libnvidia-gpucomp.i686 \
        nvidia-container-toolkit
    rm -f /etc/yum.repos.d/fedora-nvidia.repo
    rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo

    log "Installing various Nvidia configs"

    # SELinux policy
    curl -fsSL -o nvidia-container.pp https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp
    semodule -i nvidia-container.pp
    rm -f nvidia-container.pp

    # Container toolkit
    install -D /dev/stdin /usr/lib/systemd/system/nvctk-cdi.service <<'EOF'
[Unit]
Description=NVIDIA Container Toolkit CDI auto-generation
ConditionFileIsExecutable=/usr/bin/nvidia-ctk
ConditionPathExists=!/etc/cdi/nvidia.yaml
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

[Install]
WantedBy=multi-user.target
EOF

    install -D /dev/stdin /usr/lib/systemd/system-preset/70-nvctk-cdi.preset <<'EOF'
enable nvctk-cdi.service
EOF

    # Kernel modules
    install -D /dev/stdin /etc/modprobe.d/nvidia.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
EOF

    # Initramfs
    install -D /dev/stdin /usr/lib/dracut/dracut.conf.d/99-nvidia.conf <<'EOF'
# Force the i915 amdgpu nvidia drivers to the ramdisk
force_drivers+=" i915 amdgpu nvidia nvidia_drm nvidia_modeset nvidia_peermem nvidia_uvm "
EOF

    # Bootloader
    if command -v rpm-ostree >/dev/null 2>&1 && [[ -f /run/ostree-booted ]]; then
        rpm-ostree kargs \
            --append=rd.driver.blacklist=nouveau \
            --append=modprobe.blacklist=nouveau \
            --append=nvidia-drm.modeset=1 \
            --append=nvidia-drm.fbdev=1
    fi
fi

# 8. Restore kernel install scripts and cleanup extras
log "Restoring kernel install scripts."
restore_kernel_install_hooks
HOOKS_DISABLED=false

# 9. Sign the kernel and modules
sign_kernel_modules() {
    local KEY="$1"

    if [ -z "$KEY" ]; then
        error "Wrong arguments for sign_kernel_modules <signing-key>: $KEY"
        return 1
    fi

    # Create the public key from private key
    local CERT
    CERT="$(mktemp)"

    openssl req -new -x509 \
        -key "$KEY" \
        -out "$CERT" \
        -days 36500 \
        -subj "/CN=Module Signing/" || return 1

    # Detect kernel
    local KVER
    KVER="$(rpm -q --queryformat="%{evr}.%{arch}" "${KERNEL_RPM_QUERY}")" || return 1
    if [ -z "$KVER" ]; then
        error "kernel-cachyos-lto not found in RPM DB"
        return 1
    fi
    log "Detected kernel version: $KVER"

    local MODULE_ROOT="/usr/lib/modules/$KVER"
    local VMLINUZ="$MODULE_ROOT/vmlinuz"
    local SIGN_FILE="$MODULE_ROOT/build/scripts/sign-file"

    # Sign kernel image
    if [ -f "$VMLINUZ" ]; then
        log "Signing kernel image: $VMLINUZ"
        sbsign --key "$KEY" --cert "$CERT" --output "$VMLINUZ" "$VMLINUZ"
    else
        error "Can't find kernel image: $VMLINUZ"
        return 1
    fi

    log "Recursively signing modules..."
    find "$MODULE_ROOT" -type f \( \
        -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" -o -name "*.ko.gz" \
        \) -print0 | while IFS= read -r -d '' mod; do
        case "$mod" in
        *.ko)
            "$SIGN_FILE" sha256 "$KEY" "$CERT" "$mod" || return 1
            ;;
        *.ko.xz)
            xz -d "$mod"
            raw="${mod%.xz}"
            "$SIGN_FILE" sha256 "$KEY" "$CERT" "$raw" || return 1
            xz -z "$raw"
            ;;
        *.ko.zst)
            zstd -d --rm "$mod"
            raw="${mod%.zst}"
            "$SIGN_FILE" sha256 "$KEY" "$CERT" "$raw" || return 1
            zstd -q "$raw"
            ;;
        *.ko.gz)
            gunzip "$mod"
            raw="${mod%.gz}"
            "$SIGN_FILE" sha256 "$KEY" "$CERT" "$raw" || return 1
            gzip "$raw"
            ;;
        esac
    done

    log "Done signing kernel + modules for $KVER"
}

create_mok_enroll_unit() {
    local KEY="$1"
    local PASSWORD="$2"
    local UNIT_NAME="mok-enroll.service"
    local UNIT_FILE="/usr/lib/systemd/system/$UNIT_NAME"
    local DER_PATH="/usr/share/cert"

    if [ -z "$KEY" ] || [ -z "$PASSWORD" ]; then
        error "Wrong arguments for create_mok_enroll_unit <signing-key> <mok-password>: $KEY $PASSWORD"
        return 1
    fi

    # Create the DER file for MOK enrollment
    tmp="$(mktemp)"

    openssl req \
        -new -x509 \
        -key "$KEY" \
        -outform DER \
        -out "$tmp" \
        -days 36500 \
        -subj "/CN=MOK/"

    install -D -m 0644 "$tmp" "$DER_PATH/MOK.der"
    rm -f "$tmp"

    install -D /dev/stdin "$UNIT_FILE" <<EOF
[Unit]
Description=Enroll MOK key on first boot
ConditionPathExists=$DER_PATH/MOK.der
ConditionPathExists=!/var/.mok-enrolled

[Service]
Type=oneshot
ExecStart=/bin/sh -c '(echo "$PASSWORD"; echo "$PASSWORD") | mokutil --import "$DER_PATH/MOK.der"'
ExecStartPost=/usr/bin/touch /var/.mok-enrolled
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl -f enable "$UNIT_NAME"
    log "Created and enabled $UNIT_NAME"
}

if [[ -f "$SIGNING_KEY" && -n "$MOK_PASSWORD" ]]; then
    sign_kernel_modules "$SIGNING_KEY" || exit 1
    create_mok_enroll_unit "$SIGNING_KEY" "$MOK_PASSWORD" || exit 1
fi

# 10. Cleanup and System Configuration
rm -f /etc/yum.repos.d/*copr* || true

log "Custom kernel installation complete."
