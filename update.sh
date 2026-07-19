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

####################################
# Banner
####################################

banner

####################################
# Menu Options
####################################

usage() {
cat <<EOF
Usage:
    $0 --blocklist
    $0 --all

Options:
    --blocklist    Update blocklist
EOF
}

case "${1:-}" in
    --blocklist)
        update_blocklist
        ;;
    --all)
        update_all
        ;;
    *)
        usage
        exit 1
        ;;
esac


