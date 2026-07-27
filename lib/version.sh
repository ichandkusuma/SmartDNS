#!/usr/bin/env bash

####################################
# SmartDNS Version
####################################

SMARTDNS_NAME="SmartDNS"

SMARTDNS_VERSION="unknown"

get_version() {

    local VERSION_PATH

    if [[ -n "${SMARTDNS_HOME:-}" ]]; then
        VERSION_PATH="${SMARTDNS_HOME}/VERSION"
    else
        VERSION_PATH="${BASE_DIR}/VERSION"
    fi

    if [[ -r "$VERSION_PATH" ]]; then
        SMARTDNS_VERSION="$(tr -d '\r\n' < "$VERSION_PATH")"
    fi

}
