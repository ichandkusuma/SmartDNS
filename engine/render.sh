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
# Replace Variable
####################################

render_variable(){

    local FILE="$1"
    local KEY="$2"
    local VALUE="$3"

    VALUE=$(printf '%s\n' "${VALUE}" | sed 's/[\/&]/\\&/g')

    sed -i "s|{{${KEY}}}|${VALUE}|g" "${FILE}"

}

####################################
# Replace Block
####################################

render_block(){

    local FILE="$1"
    local KEY="$2"
    local CONTENT="$3"

    awk -v block="${CONTENT}" \
        "{gsub(\"{{${KEY}}}\",block)}1" \
        "${FILE}" > "${FILE}.tmp"

    mv "${FILE}.tmp" "${FILE}"

}

