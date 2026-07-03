#!/usr/bin/env bash

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
