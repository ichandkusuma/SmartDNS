#!/usr/bin/env bash

set -uo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR" || exit 1

####################################
# Load Libraries & Engine
####################################

load_modules() {

    ####################################
    # Libraries
    ####################################

    source "$BASE_DIR/lib/colors.sh"
    source "$BASE_DIR/lib/logger.sh"
    source "$BASE_DIR/lib/system.sh"
    source "$BASE_DIR/lib/validate.sh"
    source "$BASE_DIR/lib/detect.sh"
    source "$BASE_DIR/lib/version.sh"
    source "$BASE_DIR/lib/telemetry.sh"

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
}

load_modules

####################################
# Menu
####################################

usage() {
cat <<EOF
Usage:
    $0 --patch
    $0 --help

Options:
    --patch    Update SmartDNS
EOF
}

case "${1:-}" in
    --patch)

        banner

		info "Update Repositories..."

		git fetch origin || exit 1

		OLD_COMMIT=$(git rev-parse HEAD)
		NEW_COMMIT=$(git rev-parse origin/main)

		if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]]; then
			success "Already up to date."
			exit 0
		fi

		git reset --hard origin/main || exit 1

		success "Repository updated."

        ####################################
        # Update Telemetry
        ####################################

        info "Updating Telemetry..."

        if [[ -x "$BASE_DIR/scripts/smartdns-heartbeat" ]]; then
            install -m 755 \
                "$BASE_DIR/scripts/smartdns-heartbeat" \
                /usr/local/bin/smartdns-heartbeat

            success "Telemetry heartbeat updated."
        else
            warn "Telemetry heartbeat script not found."
        fi
		
        ####################################
        # Migrate Telemetry UUID
        ####################################

        info "Migrating Telemetry UUID..."

        # Reload updated telemetry library
        source "$BASE_DIR/lib/telemetry.sh"

        if generate_uuid && update_install_uuid; then
            success "Telemetry UUID synchronized."
        else
            warn "Telemetry UUID migration skipped."
        fi
		
        ####################################
        # Reload Updated Scripts
        ####################################

        #load_modules

        ####################################
        # Update Blocklist
        ####################################

        info "Updating Blocklist..."
        install_blocklist || exit 1

        ####################################
        # Automatic Update Scheduler
        ####################################

        if [[ -r cache/wizard.env ]]; then
            source cache/wizard.env
        fi

        ENABLE_AUTO_UPDATE="${ENABLE_AUTO_UPDATE:-yes}"

        info "Check Automatic Update..."
        automatic_update_scheduler || exit 1

        if [[ -f cache/wizard.env ]]; then
            if grep -q '^ENABLE_AUTO_UPDATE=' cache/wizard.env; then
                sed -i "s/^ENABLE_AUTO_UPDATE=.*/ENABLE_AUTO_UPDATE=$ENABLE_AUTO_UPDATE/" cache/wizard.env
            else
                echo "ENABLE_AUTO_UPDATE=$ENABLE_AUTO_UPDATE" >> cache/wizard.env
            fi
        fi

        ####################################
        # Restart Services
        ####################################

        info "Restarting Services..."
        restart_services || exit 1

        ####################################
        # Save State
        ####################################

        save_state SERVICE

        success "Update completed."

        ;;
    --help)
        cat <<EOF
Usage:
    $0 --patch
    $0 --help

Options:
    --patch    Update patch
EOF
        ;;
    *)

        usage
        exit 1

        ;;
esac
