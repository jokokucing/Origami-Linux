#!/usr/bin/env bash
set -euo pipefail

log() {
    echo "[custom-kernel] $*"
}

error() {
    echo "[custom-kernel] Error: $*"
}

log "Starting custom-kernel module..."

# 1. Environment Check: Ensure we are on a Fedora-based image
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID_LIKE:-}" != *"fedora"* && "${ID:-}" != "fedora" ]]; then
        error "This module is intended for Fedora-based images. Detected ID=${ID:-unknown}."
        exit 1
    fi
fi

# 2. Read configuration from the first argument ($1) using jq
KERNEL_TYPE=$(echo "$1" | jq -r '.kernel // "cachyos-lto"')

INITRAMFS=$(echo "$1" | jq -r '.initramfs // false')

NVIDIA=$(echo "$1" | jq -r '.nvidia // false')

SIGNING_KEY=$(echo "$1" | jq -r '.sign.key // ""')

MOK_PASSWORD=$(echo "$1" | jq -r '.sign["mok-password"] // ""')

MOK_ISSUER=$(echo "$1" | jq -r '(.sign["mok-issuer"] // "" | select(length>0)) // "MOK"')

# Checking key, cert and password. Can't continue without them
if [[ -z "$SIGNING_KEY" && -z "$MOK_PASSWORD" ]]; then
    log "SecureBoot signing disabled."
elif [[ -f "$SIGNING_KEY" && -n "$MOK_PASSWORD" ]]; then
    log "SecureBoot signing enabled."
else
    error "Invalid signing config:"
    error "  sign.key:  ${SIGNING_KEY:-<empty>}"
    error "  sign.mok-password: ${MOK_PASSWORD:+<set>}${MOK_PASSWORD:-<empty>}"
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
    fi

    if [[ -f "${dracut}" ]]; then
        mv "${dracut}" "${dracut}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' >"${dracut}"
        chmod +x "${dracut}"
    fi
}

# 4. Installing custom kernel
log "Temporarily disabling kernel install scripts."
disable_kernel_install_hooks

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

for repo in "${COPR_REPOS[@]}"; do
    log "Enabling COPR repo: ${repo}"
    dnf -y copr enable "${repo}"
done

log "Installing kernel packages: ${KERNEL_PACKAGES[*]}"
dnf -y install \
    "${KERNEL_PACKAGES[@]}" \
    "${EXTRA_PACKAGES[@]}"

KERNEL_VERSION="$(rpm -q "${KERNEL_PACKAGES[0]}" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" || exit 1
log "Detected kernel version: $KERNEL_VERSION"

log "Restoring kernel install scripts."
restore_kernel_install_hooks

log "Cleaning up custom kernel repos."
rm -f "/etc/yum.repos.d/"*copr* 2>/dev/null || true

# 5. Install Nvidia if needed
disable_akmodsbuild() {
    local ak="/usr/sbin/akmodsbuild"
    local bak="${ak}.backup"

    if [[ ! -f "$ak" ]]; then
        error "akmodsbuild not found: $ak"
        return 1
    fi

    cp -a "$ak" "$bak" || return 1

    # remove the problematic block
    sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' "$ak" || return 1
}

restore_akmodsbuild() {
    local ak="/usr/sbin/akmodsbuild"
    local bak="${ak}.backup"

    if [[ -f "$bak" ]]; then
        mv -f "$bak" "$ak"
    fi
}

if [[ ${NVIDIA} == true ]]; then
    log "Enabling Nvidia repositories."
    curl -fsSL -o /etc/yum.repos.d/nvidia-container-toolkit.repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
    curl -fsSL -o /etc/yum.repos.d/fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo

    log "Temporarily disabling akmodsbuild script."
    disable_akmodsbuild || exit 1

    log "Building and installing Nvidia kernel module packages."
    dnf install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts \
        akmod-nvidia \
        nvidia-kmod-common \
        nvidia-modprobe
    akmods --force --verbose --kernels "${KERNEL_VERSION}" --kmod "nvidia"

    log "Restoring akmodsbuild script."
    restore_akmodsbuild

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

    log "Cleaning Nvidia repositories."
    rm -f /etc/yum.repos.d/fedora-nvidia.repo
    rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo

    log "Installing Nvidia SELinux policy."
    curl -fsSL -o nvidia-container.pp https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp
    semodule -i nvidia-container.pp
    rm -f nvidia-container.pp

    log "Installing Nvidia container toolkit service and preset."
    install -D -m 0644 /dev/stdin /usr/lib/systemd/system/nvctk-cdi.service <<'EOF'
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

    install -D -m 0644 /dev/stdin /usr/lib/systemd/system-preset/70-nvctk-cdi.preset <<'EOF'
enable nvctk-cdi.service
EOF

    log "Setting up Nvidia modules."
    install -D -m 0644 /dev/stdin /etc/modprobe.d/nvidia.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
EOF

    log "Setting up GPU modules for initramfs."
    install -D -m 0644 /dev/stdin /usr/lib/dracut/dracut.conf.d/99-nvidia.conf <<'EOF'
# Force the i915 amdgpu nvidia drivers to the ramdisk
force_drivers+=" i915 amdgpu nvidia nvidia_drm nvidia_modeset nvidia_peermem nvidia_uvm "
EOF

    log "Injecting Nvidia kernel args"
    install -D -m 0644 /dev/stdin /usr/lib/bootc/kargs.d/90-nvidia.toml <<'EOF'
kargs = [
"rd.driver.blacklist=nouveau",
"modprobe.blacklist=nouveau",
"rd.driver.pre=nvidia",
"nvidia-drm.modeset=1",
"nvidia-drm.fbdev=1"
]
EOF
fi

# 6. Sign the kernel and modules
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
        -subj "/CN=$(printf '%s' "$MOK_ISSUER")/" || return 1

    local MODULE_ROOT="/usr/lib/modules/$KERNEL_VERSION"
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

    log "Recursively signing modules."
    while IFS= read -r -d '' mod; do
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
    done < <(find "$MODULE_ROOT" -type f \( -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" -o -name "*.ko.gz" \) -print0)

    rm -f "$CERT"
    log "Done signing kernel + modules for $KERNEL_VERSION"
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
    local CERT
    CERT="$(mktemp)"

    openssl req \
        -new -x509 \
        -key "$KEY" \
        -outform DER \
        -out "$CERT" \
        -days 36500 \
        -subj "/CN=$(printf '%s' "$MOK_ISSUER")/" || return 1

    install -D -m 0644 "$CERT" "$DER_PATH/MOK.der"
    rm -f "$CERT"

    install -D -m 0644 /dev/stdin "$UNIT_FILE" <<EOF
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

# 7. Initramfs
if [[ ${INITRAMFS} == true ]]; then
    log "Generating initramfs."
    tmp_initramfs="$(mktemp)"
    DRACUT_NO_XATTR=1 /usr/bin/dracut \
        --no-hostonly \
        --kver "${KERNEL_VERSION}" \
        --reproducible \
        --add ostree \
        -f "$tmp_initramfs" \
        -v || return 1

    install -D -m 0600 "$tmp_initramfs" "/lib/modules/${KERNEL_VERSION}/initramfs.img"
    rm -f "$tmp_initramfs"
fi

log "Custom kernel installation complete."
