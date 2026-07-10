#!/usr/bin/env bash

####################################
# SmartDNS Telemetry
####################################

readonly TELEMETRY_DIR="/var/lib/smartdns"
readonly UUID_FILE="${TELEMETRY_DIR}/uuid"
readonly INSTALL_FILE="${TELEMETRY_DIR}/install.json"

readonly TELEMETRY_URL="https://smartdns.mynoc.id/api/v1/heartbeat.php"

readonly INSTALL_ENV="${TELEMETRY_DIR}/install.env"

UUID=""
PAYLOAD=""

####################################
# Generate UUID
####################################

generate_uuid() {

    mkdir -p "$TELEMETRY_DIR"

    if [[ -s "$UUID_FILE" ]]; then
        UUID="$(<"$UUID_FILE")"
    else
        UUID="$(uuidgen)"
        printf '%s\n' "$UUID" > "$UUID_FILE"
        chmod 600 "$UUID_FILE"
    fi

}

####################################
# Installation Metadata
####################################

init_install_metadata() {

    mkdir -p "$TELEMETRY_DIR"

    if [[ ! -f "$INSTALL_FILE" ]]; then

        cat > "$INSTALL_FILE" <<EOF
{
    "uuid":"$UUID",
    "product":"$SMARTDNS_NAME",
    "version":"$SMARTDNS_VERSION",
    "installed_at":"$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "telemetry":true
}
EOF

        chmod 600 "$INSTALL_FILE"

    fi

}

####################################
# Build Payload
####################################

build_telemetry_payload() {

    local DEFAULT_SPOOF_IPV4="103.151.222.227"
    local DEFAULT_SPOOF_IPV6="2406:20c0::103:151:222:227"

    local SPOOF_IPV4_DEFAULT=false
    local SPOOF_IPV6_DEFAULT=false

    [[ "${SPOOF_IPV4:-}" == "$DEFAULT_SPOOF_IPV4" ]] && SPOOF_IPV4_DEFAULT=true
    [[ "${SPOOF_IPV6:-}" == "$DEFAULT_SPOOF_IPV6" ]] && SPOOF_IPV6_DEFAULT=true

    PAYLOAD=$(cat <<EOF
{
  "uuid":"$UUID",
  "product":"${SMARTDNS_NAME:-SmartDNS}",
  "version":"${SMARTDNS_VERSION:-unknown}",

  "system":{
    "hostname":"${HOSTNAME:-}",
    "os":"${OS:-}",
    "version":"${VERSION:-}",
    "kernel":"${KERNEL:-}",
    "arch":"${CPU_ARCH:-}",
    "cpu_model":"${CPU_MODEL:-}",
    "cpu_threads":${CPU_THREADS:-0},
    "memory_mb":${RAM_MB:-0},
    "virtualization":"${VIRT:-Unknown}"
  },

  "network":{
    "ipv4":"${SERVER_IPV4:-}",
    "ipv6":"${SERVER_IPV6:-}",
    "ipv6_available":"${IPV6_AVAILABLE:-no}"
  },

  "features":{
	"ipv6":$( [[ "${ENABLE_IPV6:-no}" == "yes" ]] && echo true || echo false ),
	"dnssec":$( [[ "${ENABLE_DNSSEC:-no}" == "yes" ]] && echo true || echo false ),
	"ratelimit":$( [[ "${ENABLE_RATELIMIT:-no}" == "yes" ]] && echo true || echo false ),
	"querylog":$( [[ "${ENABLE_QUERYLOG:-no}" == "yes" ]] && echo true || echo false )
  },

  "spoof":{
    "ipv4_default":${SPOOF_IPV4_DEFAULT},
    "ipv6_default":${SPOOF_IPV6_DEFAULT}
  },

  "tuning":{
    "threads":${UNBOUND_THREADS:-0},
    "rrset_cache":"${RRSET_CACHE:-}",
    "msg_cache":"${MSG_CACHE:-}",
    "slabs":${SLABS:-0},
    "outgoing_range":${OUTGOING_RANGE:-0},
    "num_queries":${NUM_QUERIES:-0},
    "infra_cache":${INFRA_CACHE:-0},

    "dnsdist_cache":${DNSDIST_CACHE:-0},
    "tcp_threads":${TCP_THREADS:-0},
    "tcp_queue":${TCP_QUEUE:-0},
    "udp_outstanding":${UDP_OUTSTANDING:-0}
  }
}
EOF
)

}

####################################
# Send Heartbeat
####################################

send_heartbeat() {

    build_telemetry_payload

    curl \
        --silent \
        --show-error \
        --user-agent "SmartDNS/${SMARTDNS_VERSION}" \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 2 \
        --retry-delay 2 \
        --header "Content-Type: application/json" \
        --data "$PAYLOAD" \
        "$TELEMETRY_URL" \
        >/dev/null 2>&1 || return 1

    return 0

}

####################################
# Installation Environment
####################################

save_install_env() {

    mkdir -p "$TELEMETRY_DIR"

    cat > "$INSTALL_ENV" <<EOF
SMARTDNS_HOME="$BASE_DIR"
EOF

    chmod 600 "$INSTALL_ENV"

}
