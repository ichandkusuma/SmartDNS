#!/usr/bin/env bash

set -uo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

####################################
# Libraries
####################################

source "$BASE_DIR/lib/colors.sh"
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/system.sh"
source "$BASE_DIR/lib/validate.sh"
source "$BASE_DIR/lib/detect.sh"

####################################
# Engine
####################################

source "$BASE_DIR/engine/tuning.sh"
source "$BASE_DIR/engine/template.sh"
source "$BASE_DIR/engine/runtime.sh"
source "$BASE_DIR/engine/render.sh"
source "$BASE_DIR/engine/package.sh"
source "$BASE_DIR/engine/service.sh"
source "$BASE_DIR/engine/wizard.sh"
source "$BASE_DIR/engine/acl.sh"
source "$BASE_DIR/engine/security.sh"
source "$BASE_DIR/engine/state.sh"
source "$BASE_DIR/engine/blocklist.sh"
source "$BASE_DIR/engine/secret.sh"
source "$BASE_DIR/engine/cron.sh"
source "$BASE_DIR/engine/swap.sh"
source "$BASE_DIR/engine/sysctl.sh"

####################################
# Banner
####################################

banner

####################################
# Hardware Detection
####################################

info "Checking root..."
check_root

info "Detecting OS..."
detect_os

info "Detecting virtualization..."
detect_virtualization

info "Detecting CPU..."
detect_cpu

info "Detecting memory..."
detect_memory

info "Detecting network..."
detect_network

info "Detecting Internet..."
detect_internet

info "Detecting NIC Speed..."
detect_nic_speed

info "Detecting Hostname..."
detect_hostname

info "Detecting Kernel..."
detect_kernel

info "Detecting Uptime..."
detect_uptime

info "Save Cache..."
save_detect_cache

save_state DETECT

####################################
# Smart Tuning
####################################

info "Calculating Smart Tuning..."
calculate_tuning
save_tuning

save_state TUNING

####################################
# Wizard
####################################

info "Running Installation Wizard..."
run_wizard

save_state WIZARD

####################################
# ACL
####################################

info "Generating Resolver ACL..."
run_acl

save_state ACL

####################################
# Runtime
####################################

info "Building Runtime..."
merge_runtime

save_state RUNTIME

####################################
# Generate Secret
####################################

generate_secret

####################################
# Generate Configuration
####################################

info "Generating Configuration..."
generate_templates

save_state TEMPLATE

show_tuning

####################################
# Install
####################################

echo
read -rp "Install required packages? [Y/n] : " INSTALL_PACKAGE

INSTALL_PACKAGE=${INSTALL_PACKAGE:-Y}

if [[ "$INSTALL_PACKAGE" =~ ^[Yy]$ ]]; then

	if command -v timedatectl >/dev/null 2>&1; then
		info "Setting Timezone..."
		timedatectl set-timezone Asia/Jakarta
		success "Timezone set to Asia/Jakarta."
	fi
	
	info "Setting Hostname..."
	hostnamectl set-hostname SmartDNS
	success "Hostname set to SmartDNS."

	install_swap
	
	install_sysctl
	
	temp_resolv
	
    install_packages || exit 1
    save_state PACKAGE

    info "Backup current configuration..."
    backup_config || exit 1

    info "Installing configuration..."
    install_config || exit 1
    save_state INSTALL

	info "Installing DNS Blocklist..."
	install_blocklist || exit 1

	info "Installing Scheduler Update..."
	install_scheduler || exit 1

	info "Installing Blocklist Scheduler..."
	install_blocklist_cron || exit 1

    info "Validating configuration..."
    validate_config || exit 1
    save_state VALIDATE

    info "Preparing DNS environment..."
    prepare_dns_environment

    info "Restarting services..."
    restart_services || exit 1
    save_state SERVICE

	if health_check; then

		save_state DONE

	else

		error "Health check failed."

		exit 1

	fi

    save_state DONE

fi

####################################
# Summary
####################################

summary

echo
echo "======================================"
echo "         DNSDIST WEB UI"
echo "======================================"
echo "URL       : http://${SERVER_IPV4}:8083"
echo "Username  : admin"
echo "Password  : ${DNSDIST_WEB_PASSWORD}"
echo "API Key   : ${DNSDIST_API_KEY}"
echo

