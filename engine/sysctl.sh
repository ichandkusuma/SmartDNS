#!/usr/bin/env bash

####################################
# Kernel Tuning
####################################

install_sysctl(){

    info "Optimizing Kernel..."

    cat >/etc/sysctl.d/99-smartdns.conf <<EOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=8192

vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

    sysctl --system >/dev/null 2>&1

    success "Kernel optimized."
}


####################################
# System Journal Tuning
####################################

install_journald(){

    info "Optimizing System Journal..."

    mkdir -p /etc/systemd/journald.conf.d

    cat >/etc/systemd/journald.conf.d/99-smartdns.conf <<EOF
[Journal]
SystemMaxUse=200M
SystemKeepFree=1G
MaxRetentionSec=7day
EOF

    systemctl restart systemd-journald >/dev/null 2>&1

    journalctl --vacuum-size=200M >/dev/null 2>&1 || true

    success "System journal optimized."
}
