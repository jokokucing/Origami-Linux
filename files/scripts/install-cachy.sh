#!/usr/bin/env bash

# Remove Fedora kernel & remove leftover files
dnf -y remove \
    kernel \
    kernel-* &&
    rm -r -f /usr/lib/modules/*

# Install dnf-plugins-core just in case
#dnf -y install --setopt=install_weak_deps=False \
#    dnf-plugins-core \
#    dnf5-plugins

# Enable repos
dnf -y copr enable bieszczaders/kernel-cachyos-lto
dnf -y copr enable bieszczaders/kernel-cachyos-addons
#dnf -y copr enable ublue-os/akmods
#dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# Handles kernel post-transcaction scriptlet
# mv /usr/lib/kernel/install.d/05-rpmostree.install /usr/lib/kernel/install.d/05-rpmostree.install.bak
# mv /usr/lib/kernel/install.d/50-dracut.install /usr/lib/kernel/install.d/50-dracut.install.bak
# printf '%s\n' '#!/bin/sh' 'exit 0' > /usr/lib/kernel/install.d/05-rpmostree.install
# printf '%s\n' '#!/bin/sh' 'exit 0' > /usr/lib/kernel/install.d/50-dracut.install
# chmod +x \
#      /usr/lib/kernel/install.d/05-rpmostree.install \
#      /usr/lib/kernel/install.d/50-dracut.install

# Install CachyOS LTO kernel & akmods
dnf -y install --setopt=install_weak_deps=False \
    kernel-cachyos-lto \
    kernel-cachyos-lto-devel \
    scx-scheds-git \
    scx-manager
dnf -y swap zram-generator-defaults cachyos-settings

# Handles kernel post-transcaction scriptlet
# rm -f /usr/lib/kernel/install.d/05-rpmostree.install \
#       /usr/lib/kernel/install.d/50-dracut.install
# mv /usr/lib/kernel/install.d/05-rpmostree.install.bak /usr/lib/kernel/install.d/05-rpmostree.install
# mv /usr/lib/kernel/install.d/50-dracut.install.bak /usr/lib/kernel/install.d/50-dracut.install

# Manually build modules, run depmod & generate initramfs
VER=$(ls /lib/modules) &&
    depmod -a $VER &&
    dracut --kver $VER --force --add ostree --no-hostonly --reproducible /usr/lib/modules/$VER/initramfs.img

# Clean up repos from earlier
rm -f /etc/yum.repos.d/{*copr*}
