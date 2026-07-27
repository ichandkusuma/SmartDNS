#!/usr/bin/env bash

####################################
# Replace Variable
####################################

render_variable(){

    local FILE="$1"
    local KEY="$2"
    local VALUE="$3"

    VALUE=$(printf '%s\n' "$VALUE" | sed 's/[\/&]/\\&/g')

    sed -i "s|{{$KEY}}|$VALUE|g" "$FILE"

}

####################################
# Replace Block
####################################

render_block(){

    local FILE="$1"
    local KEY="$2"
    local CONTENT="$3"

    awk -v block="$CONTENT" \
        "{gsub(\"{{$KEY}}\",block)}1" \
        "$FILE" > "${FILE}.tmp"

    mv "${FILE}.tmp" "$FILE"

}

