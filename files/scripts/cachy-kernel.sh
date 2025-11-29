#!/usr/bin/env bash

dnf -y remove \
    kernel \
    kernel-* &&
    rm -r -f /usr/lib/modules/*

# Enable repos
dnf -y copr enable bieszczaders/kernel-cachyos-lto
dnf -y copr enable bieszczaders/kernel-cachyos-addons

dnf -y install --setopt=install_weak_deps=False \
    kernel-cachyos-lto \
    libcap-ng \
    libcap-ng-devel \
    procps-ng \
    procps-ng-devel \
    uksmd

# Clean up repos from earlier
rm -f /etc/yum.repos.d/{*copr*}
