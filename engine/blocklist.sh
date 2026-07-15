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

#########################################
# Blocklist
#########################################

BLOCKLIST_DIR="/opt/blocklist"

#########################################
# Install
#########################################

install_blocklist(){

    mkdir -p "${BLOCKLIST_DIR}"

    command -v cdbmake >/dev/null 2>&1 || fatal "tinycdb not installed"

    cp data/sources.txt \
       "${BLOCKLIST_DIR}/sources.txt"

    cp data/update-blocklist.sh \
       "${BLOCKLIST_DIR}/update-blocklist.sh"

    chmod +x "${BLOCKLIST_DIR}/update-blocklist.sh"

    info "Generating initial blocklist..."

    "${BLOCKLIST_DIR}/update-blocklist.sh"

    success "Blocklist installed."

}

#########################################
# OLD Cron Remove
#########################################

install_blocklist_cron(){

cat >/etc/cron.d/smartdns-blocklist <<EOF

EOF
	rm /etc/cron.d/smartdns-blocklist
}
