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
# Generate Secret
####################################

generate_secret(){

    DNSDIST_KEY=$(openssl rand -base64 32)

    DNSDIST_API_KEY=$(openssl rand -hex 32)

    if [[ -z "${DNSDIST_WEB_PASSWORD:-}" ]]; then
        DNSDIST_WEB_PASSWORD=$(openssl rand -base64 18)
    fi

    ####################################
    # Save Secret
    ####################################

    mkdir -p cache

    cat > cache/secret.env <<EOF
DNSDIST_KEY=${DNSDIST_KEY}
DNSDIST_API_KEY=${DNSDIST_API_KEY}
DNSDIST_WEB_PASSWORD=${DNSDIST_WEB_PASSWORD}
SPOOF_IPV4=${SPOOF_IPV4}
SPOOF_IPV6=${SPOOF_IPV6}
EOF

}
