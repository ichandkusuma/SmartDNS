#!/usr/bin/env bash

detect_os(){

if [[ ! -f /etc/os-release ]]; then

    fatal "Unsupported OS"

fi

source /etc/os-release

OS="$NAME"
VERSION="$VERSION_ID"

case "$ID" in

ubuntu|debian)
;;

*)
fatal "Only Ubuntu/Debian Supported"
;;

esac

}

ask_yes_no(){

    local PROMPT="$1"
    local DEFAULT="$2"

    while true
    do
        read -rp "$PROMPT " ANSWER

        ANSWER=${ANSWER:-$DEFAULT}

        case "${ANSWER^^}" in
            Y|YES)
                echo "yes"
                return
                ;;

            N|NO)
                echo "no"
                return
                ;;

            *)
                warn "Please enter Y or N."
                ;;
        esac

    done

}

ask_number(){

    local PROMPT="$1"
    local DEFAULT="$2"

    while true
    do

        read -rp "$PROMPT " ANSWER

        ANSWER=${ANSWER:-$DEFAULT}

        [[ "$ANSWER" =~ ^[0-9]+$ ]] && {

            echo "$ANSWER"
            return

        }

        warn "Please enter numbers only."

    done

}

ask_recursive_port(){

    local PROMPT="$1"
    local DEFAULT="$2"
    local PORT

    while true
    do
        PORT=$(ask_number "$PROMPT" "$DEFAULT")

        if (( PORT >= 1024 && PORT <= 65535 )); then
            echo "$PORT"
            return
        fi

        warn "Recursive Port must be between 1024 and 65535."

    done

}

ask_frontend_port(){

    local PROMPT="$1"
    local DEFAULT="$2"
    local PORT

    while true
    do
        PORT=$(ask_number "$PROMPT" "$DEFAULT")

        if (( PORT == 53 )); then
            echo "$PORT"
            return
        fi

        if (( PORT >= 1024 && PORT <= 65535 )); then
            echo "$PORT"
            return
        fi

        warn "Frontend Port must be 53 or between 1024 and 65535."

    done

}

validate_ports(){

    local RECURSIVE="$1"
    local FRONTEND="$2"

    [[ "$RECURSIVE" != "$FRONTEND" ]]

}

####################################
# CIDR
####################################

ask_cidr(){

    local PROMPT="$1"

    while true
    do

        read -rp "$PROMPT " CIDR

        [[ -z "$CIDR" ]] && {
            echo ""
            return
        }

        ################################
        # IPv4
        ################################

        if [[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then

            echo "$CIDR"

            return

        fi

        ################################
        # IPv6
        ################################

        if [[ "$CIDR" =~ : ]] && [[ "$CIDR" =~ /([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8])$ ]]; then

            echo "$CIDR"

            return

        fi

        warn "Invalid CIDR."

    done

}
####################################
# IPv4
####################################

validate_ipv4(){

    local ip="$1"

    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS=. read -r a b c d <<<"$ip"

    for i in "$a" "$b" "$c" "$d"
    do
        ((i>=0 && i<=255)) || return 1
    done

    return 0

}

####################################
# IPv6
####################################

validate_ipv6(){

    local ip="$1"

    if command -v python3 >/dev/null 2>&1; then

        python3 - <<EOF >/dev/null 2>&1
import ipaddress
ipaddress.IPv6Address("$ip")
EOF

        return $?

    fi

    [[ "$ip" == *:* ]]

}

####################################
# To LUA Array
####################################

to_lua_array() {

    local list="$1"
    local out="{"
    local first=1

    IFS=',' read -ra IPS <<< "$list"

    for ip in "${IPS[@]}"; do

        ip="$(echo "$ip" | xargs)"

        [[ $first -eq 0 ]] && out+=","

        out+="\"$ip\""

        first=0

    done

    out+="}"

    printf '%s' "$out"
}
