#!/usr/bin/env bash

#########################################
# Package List
#########################################

PACKAGES=(
    unbound
    dnsdist
    dnsutils
    curl
    wget
    unzip
    jq
    ca-certificates
    freecdb
)

#########################################
# Check Package
#########################################

is_installed(){

    dpkg -s "$1" >/dev/null 2>&1

}

#########################################
# Install Missing Package
#########################################

install_packages(){

    local MISSING_PACKAGES=()

    for PKG in "${PACKAGES[@]}"
    do

        if is_installed "$PKG"; then

            success "$PKG already installed"

        else

            warn "$PKG missing"

            MISSING_PACKAGES+=("$PKG")

        fi

    done

    if (( ${#MISSING_PACKAGES[@]} > 0 )); then

        info "Updating package repository..."

        apt-get update || return 1

		if ! apt-get -f install -y; then
			error "Package manager is not healthy."
			exit 1
		fi

        info "Installing missing packages..."

        apt-get install -y "${MISSING_PACKAGES[@]}" || return 1

        command -v unbound >/dev/null || {
            error "Unbound installation failed"
            return 1
        }

        command -v dnsdist >/dev/null || {
            error "dnsdist installation failed"
            return 1
        }

        success "All required packages installed."

    else

        success "All required packages already installed."

    fi

}

