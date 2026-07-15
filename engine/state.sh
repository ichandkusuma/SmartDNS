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

STATE_FILE="cache/install.state"

####################################
# Save State
####################################

save_state(){

    mkdir -p cache

    echo "$1" > "${STATE_FILE}"

}

####################################
# Get State
####################################

get_state(){

    [[ -f "${STATE_FILE}" ]] || return

    cat "${STATE_FILE}"

}

