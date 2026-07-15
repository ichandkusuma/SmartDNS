#!/usr/bin/env bash
#
# CHANGELOG:
# Standardized variable expansion by consistently using ${VAR} across all shell
# scripts to improve readability, consistency, and safety. This follows shell
# scripting best practices and helps prevent issues related to word splitting
# and pathname expansion (globbing). Additionally, fixed ShellCheck warnings,
# corrected Markdown formatting errors, added appropriate ShellCheck directives,
# removed unused color variables, improved shebang declarations, and performed
# general code quality and maintainability improvements.
#

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

