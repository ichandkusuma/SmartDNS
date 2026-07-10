#!/usr/bin/env bash

####################################
# SmartDNS Version
####################################

SMARTDNS_NAME="SmartDNS"

SMARTDNS_VERSION="unknown"

get_version() {

    if [[ -r "$SMARTDNS_HOME/VERSION" ]]; then
        SMARTDNS_VERSION="$(tr -d '\r\n' < "$SMARTDNS_HOME/VERSION")"
    else
        SMARTDNS_VERSION="unknown"
    fi

}
