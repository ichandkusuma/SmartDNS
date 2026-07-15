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
# Install Swap
####################################

install_swap() {

    # shellcheck disable=SC2312
    if swapon --show | grep -q .; then
        success "Swap already enabled."
        return
    fi

    info "Configuring Swap..."

    local MEM_GB
    local DISK_GB
    local SWAP_SIZE

    MEM_GB=$(awk '/MemTotal/ {printf "%.0f",$2/1024/1024}' /proc/meminfo)

    # shellcheck disable=SC2312
    DISK_GB=$(df --output=size -BG / | tail -1 | tr -dc '0-9')

    ################################################
    # Smart Swap Size
    ################################################

    if (( DISK_GB < 15 )); then

        SWAP_SIZE="1G"

    elif (( MEM_GB <= 2 )); then

        SWAP_SIZE="2G"

    elif (( MEM_GB <= 8 )); then

        SWAP_SIZE="2G"

    elif (( MEM_GB <= 16 )); then

        SWAP_SIZE="4G"

    else

        SWAP_SIZE="8G"

    fi

    ################################################
    # Create Swap
    ################################################

    fallocate -l "${SWAP_SIZE}" /swapfile \
        || dd if=/dev/zero of=/swapfile bs=1M count=$(( ${SWAP_SIZE%G} * 1024 ))

    chmod 600 /swapfile

    mkswap /swapfile >/dev/null

    swapon /swapfile

    grep -q '^/swapfile' /etc/fstab \
        || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    success "Swap ${SWAP_SIZE} enabled."

}
