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
# SmartDNS Version
####################################

# shellcheck disable=SC2034
SMARTDNS_NAME="SmartDNS"

# shellcheck disable=SC2034
SMARTDNS_VERSION="unknown"

get_version() {

    local VERSION_PATH

    if [[ -n "${SMARTDNS_HOME:-}" ]]; then
        VERSION_PATH="${SMARTDNS_HOME}/VERSION"
    else
        VERSION_PATH="${BASE_DIR}/VERSION"
    fi

    if [[ -r "${VERSION_PATH}" ]]; then
        SMARTDNS_VERSION="$(tr -d '\r\n' < "${VERSION_PATH}")"
    fi

}
