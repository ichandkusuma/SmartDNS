#!/usr/bin/env bash

####################################
# Runtime Configuration
####################################

write_runtime() {
    local key="$1"
    local value="$2"

    printf '%s="%s"\n' "$key" "$value"
}

merge_runtime() {

    mkdir -p cache

    {

cat <<EOF
####################################
# System
####################################
EOF

        write_runtime HOSTNAME "$HOSTNAME"
        write_runtime OS "$OS"
        write_runtime VERSION "$VERSION"
        write_runtime KERNEL "$KERNEL"
        write_runtime CPU_ARCH "$CPU_ARCH"
        write_runtime CPU_MODEL "$CPU_MODEL"
        write_runtime CPU_THREADS "$CPU_THREADS"
        write_runtime RAM_MB "$RAM_MB"

        echo

cat <<EOF
####################################
# Network
####################################
EOF

        write_runtime DEFAULT_IF "$DEFAULT_IF"
        write_runtime SERVER_IPV4 "$SERVER_IPV4"
        write_runtime SERVER_IPV6 "${SERVER_IPV6:-}"
        write_runtime ONLINE "${ONLINE:-Unknown}"

        echo

cat <<EOF
####################################
# Wizard
####################################
EOF

        write_runtime ENABLE_IPV6 "$ENABLE_IPV6"
        write_runtime ENABLE_DNSSEC "$ENABLE_DNSSEC"
        write_runtime ENABLE_RATELIMIT "$ENABLE_RATELIMIT"
        write_runtime ENABLE_QUERYLOG "$ENABLE_QUERYLOG"

        write_runtime RECURSIVE_PORT "$RECURSIVE_PORT"
        write_runtime FRONTEND_PORT "$FRONTEND_PORT"

        write_runtime SPOOF_IPV4 "$SPOOF_IPV4"
        write_runtime SPOOF_IPV6 "$SPOOF_IPV6"

        echo

cat <<EOF
####################################
# Tuning
####################################
EOF

        write_runtime UNBOUND_THREADS "$UNBOUND_THREADS"
        write_runtime RRSET_CACHE "$RRSET_CACHE"
        write_runtime MSG_CACHE "$MSG_CACHE"
        write_runtime SLABS "$SLABS"
        write_runtime OUTGOING_RANGE "$OUTGOING_RANGE"
        write_runtime NUM_QUERIES "$NUM_QUERIES"
        write_runtime INFRA_CACHE "$INFRA_CACHE"

        write_runtime DNSDIST_CACHE "$DNSDIST_CACHE"
        write_runtime TCP_THREADS "$TCP_THREADS"
        write_runtime TCP_QUEUE "$TCP_QUEUE"
        write_runtime UDP_OUTSTANDING "$UDP_OUTSTANDING"

        write_runtime IPV6_AVAILABLE "$IPV6_AVAILABLE"

    } > cache/runtime.env

    success "Runtime cache generated."

}
