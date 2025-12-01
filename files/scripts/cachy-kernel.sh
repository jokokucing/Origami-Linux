#!/usr/bin/env bash

dnf -y remove \
    kernel \
    kernel-* &&
    rm -r -f /usr/lib/modules/*

# Enable repos
dnf -y copr enable bieszczaders/kernel-cachyos-lto

dnf -y install --setopt=install_weak_deps=False \
    kernel-cachyos-lto

# Clean up repos from earlier
rm -f /etc/yum.repos.d/{*copr*}

setsebool -P domain_kernel_load_modules on
