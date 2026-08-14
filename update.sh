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

        ####################################
        # Update Repository
        ####################################

        info "Update Repositories..."

        git fetch origin || exit 1

        OLD_COMMIT=$(git rev-parse HEAD)
        NEW_COMMIT=$(git rev-parse origin/main)

        REPO_UPDATED=false

		if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]]; then

			REPO_UPDATED=false

			success "Repository already up to date."

		else

			git reset --hard origin/main || exit 1

			success "Repository updated."

			info "Reloading updated updater..."

			exec "$BASE_DIR/update.sh" --patch

		fi

        ####################################
        # Update Telemetry Heartbeat
        ####################################

        info "Updating Telemetry Heartbeat..."

        if [[ -f "$BASE_DIR/scripts/smartdns-heartbeat" ]]; then

            install -m 755 \
                "$BASE_DIR/scripts/smartdns-heartbeat" \
                /usr/local/bin/smartdns-heartbeat

            success "Telemetry heartbeat updated."

        else

            warn "Telemetry heartbeat script not found."

        fi

        ####################################
        # Update Blocklist
        ####################################

        if [[ "$REPO_UPDATED" == true ]]; then

            info "Updating Blocklist..."

            install_blocklist || exit 1

        else

            info "Repository unchanged. Skipping Blocklist update."

        fi

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

                sed -i \
                    "s/^ENABLE_AUTO_UPDATE=.*/ENABLE_AUTO_UPDATE=$ENABLE_AUTO_UPDATE/" \
                    cache/wizard.env

            else

                echo "ENABLE_AUTO_UPDATE=$ENABLE_AUTO_UPDATE" >> cache/wizard.env

            fi

        fi

        ####################################
        # Restart Services
        ####################################

        if [[ "$REPO_UPDATED" == true ]]; then

            info "Restarting Services..."

            restart_services || exit 1

        else

            info "Repository unchanged. Skipping service restart."

        fi

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
    --patch    Update SmartDNS
EOF
        ;;

    *)

        usage
        exit 1

        ;;

esac
