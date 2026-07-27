#!/usr/bin/env bash

LOGFILE=/var/log/smartdns-installer.log

log(){

    echo "$(date '+%F %T') $1" >> "$LOGFILE"

}

