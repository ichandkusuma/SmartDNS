#!/usr/bin/env bash

STATE_FILE="cache/install.state"

####################################
# Save State
####################################

save_state(){

    mkdir -p cache

    echo "$1" > "$STATE_FILE"

}

####################################
# Get State
####################################

get_state(){

    [[ -f "$STATE_FILE" ]] || return

    cat "$STATE_FILE"

}

