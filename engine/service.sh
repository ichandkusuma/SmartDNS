#!/usr/bin/env bash

#########################################
# Directory
#########################################

UNBOUND_DIR="/etc/unbound/unbound.conf.d"
DNSDIST_DIR="/etc/dnsdist"

BACKUP_DIR="/var/backups/smartdns"

#########################################
# Backup
#########################################

backup_config(){

    mkdir -p "$BACKUP_DIR"

	if [[ -f "$UNBOUND_DIR/smartdns.conf" ]]; then

		cp "$UNBOUND_DIR/smartdns.conf" \
		   "$BACKUP_DIR/smartdns.conf.$(date +%F-%H%M%S)"

	fi

    if [[ -f "$DNSDIST_DIR/dnsdist.conf" ]]; then

        cp "$DNSDIST_DIR/dnsdist.conf" \
           "$BACKUP_DIR/dnsdist.conf.$(date +%F-%H%M%S)"

    fi

    success "Configuration backup completed."

}

#########################################
# Install Config
#########################################

install_config(){

	cp output/recursive.conf "$UNBOUND_DIR/smartdns.conf"

	echo "===== INSTALLED ====="
	grep -n "auto-trust-anchor-file" "$UNBOUND_DIR/smartdns.conf"
	echo "====================="

    cp output/dnsdist.conf "$DNSDIST_DIR/dnsdist.conf"

    success "Configuration installed."

}

#########################################
# Validate Config
#########################################

validate_config(){

    info "Validating Unbound configuration..."

    if unbound-checkconf /etc/unbound/unbound.conf.d/smartdns.conf >/dev/null 2>&1; then
        success "Unbound configuration OK"
    else
        error "Unbound configuration FAILED"
        return 1
    fi

    info "Validating dnsdist configuration..."

    if dnsdist --check-config >/dev/null 2>&1; then
        success "dnsdist configuration OK"
    else
        error "dnsdist configuration FAILED"
        return 1
    fi

}

restart_services(){

    info "Restarting Unbound..."
    systemctl restart unbound || return 1
    success "Unbound restarted."

    info "Restarting dnsdist..."
    systemctl restart dnsdist || return 1
    success "dnsdist restarted."

}

health_check() {

    info "Running DNS Health Check..."

    local DNS_TARGET

    if [[ "$ENABLE_IPV6" == "yes" ]]; then
        DNS_TARGET="::1"
    else
        DNS_TARGET="127.0.0.1"
    fi

    for i in {1..15}; do

        if dig @"$DNS_TARGET" google.com +short 2>/dev/null | grep -q .; then
            success "DNS Resolver is working."
            return 0
        fi

        sleep 1
    done

    error "DNS Resolver failed."
    return 1
}

rollback_config(){

    warn "Rollback configuration..."

    LATEST_UNBOUND=$(ls -t /var/backups/smartdns/smartdns.conf* 2>/dev/null | head -1)

    if [[ -n "$LATEST_UNBOUND" ]]

    then

        cp "$LATEST_UNBOUND" \
           /etc/unbound/unbound.conf.d/smartdns.conf

    fi

    LATEST_DNSDIST=$(ls -t /var/backups/smartdns/dnsdist.conf* 2>/dev/null | head -1)

    if [[ -n "$LATEST_DNSDIST" ]]

    then

        cp "$LATEST_DNSDIST" \
           /etc/dnsdist/dnsdist.conf

    fi

    systemctl restart unbound

    systemctl restart dnsdist

}


