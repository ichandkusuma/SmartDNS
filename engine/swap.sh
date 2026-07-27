#!/usr/bin/env bash

####################################
# Install Swap
####################################

install_swap() {

    if swapon --show | grep -q .; then
        success "Swap already enabled."
        return
    fi

    info "Configuring Swap..."

    local MEM_GB
    local DISK_GB
    local SWAP_SIZE

    MEM_GB=$(awk '/MemTotal/ {printf "%.0f",$2/1024/1024}' /proc/meminfo)

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

    fallocate -l "$SWAP_SIZE" /swapfile \
        || dd if=/dev/zero of=/swapfile bs=1M count=$(( ${SWAP_SIZE%G} * 1024 ))

    chmod 600 /swapfile

    mkswap /swapfile >/dev/null

    swapon /swapfile

    grep -q '^/swapfile' /etc/fstab \
        || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    success "Swap $SWAP_SIZE enabled."

}
