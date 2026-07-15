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
# ACL Wizard
####################################

run_acl(){

    mkdir -p cache

    ACL_FILE="cache/acl.list"

    cat > "${ACL_FILE}" <<EOF
127.0.0.0/8
::1/128
EOF

    echo
    echo "======================================"
    echo "         RESOLVER ACL"
    echo "======================================"

    echo
    echo "Default ACL"
    echo "  - 127.0.0.0/8"
    echo "  - ::1/128"
    echo

    while true
    do

        CIDR=$(ask_cidr "Add Resolver CIDR (ENTER = Finish) :")

        [[ -z "${CIDR}" ]] && break

        if grep -qx "${CIDR}" "${ACL_FILE}"; then

            warn "ACL already exists."

            continue

        fi

        echo "${CIDR}" >> "${ACL_FILE}"

        success "Added ${CIDR}"

    done

}

