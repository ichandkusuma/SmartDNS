#!/usr/bin/env bash

####################################
# Install Scheduler
####################################

install_scheduler() {

    info "Installing Scheduler..."

    # Pastikan cron aktif
    systemctl enable --now cron >/dev/null 2>&1 || true

    # Random schedule (sekali saat install)
    HOUR=$(( RANDOM % 6 ))      # 00-05
    MINUTE=$(( RANDOM % 60 ))   # 00-59

    cat >/etc/cron.d/smartdns <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# SmartDNS Auto Update
${MINUTE} ${HOUR} * * * root ${BASE_DIR}/data/update-blocklist.sh >>/var/log/smartdns-blocklist.log 2>&1
EOF

    chmod 644 /etc/cron.d/smartdns

    # Reload cron
    systemctl reload cron >/dev/null 2>&1 || \
    systemctl restart cron >/dev/null 2>&1

    success "Scheduler installed."
    info "Daily update scheduled at $(printf "%02d:%02d" "$HOUR" "$MINUTE") + random delay (0-30 minutes)."

}

####################################
# Heartbeat Scheduler
####################################

install_heartbeat_scheduler() {

    info "Installing Heartbeat Scheduler..."

    install -Dm755 \
        "$BASE_DIR/scripts/smartdns-heartbeat" \
        /usr/local/bin/smartdns-heartbeat

    install -Dm644 \
        "$BASE_DIR/templates/smartdns-heartbeat.cron" \
        /etc/cron.d/smartdns-heartbeat

    success "Heartbeat scheduler installed."

}

