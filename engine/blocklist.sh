#!/usr/bin/env bash

#########################################
# Blocklist
#########################################

BLOCKLIST_DIR="/opt/blocklist"

#########################################
# Install
#########################################

install_blocklist(){

    mkdir -p "$BLOCKLIST_DIR"

    command -v cdbmake >/dev/null 2>&1 || fatal "tinycdb not installed"

    cp data/sources.txt \
       "$BLOCKLIST_DIR/sources.txt"

    cp data/update-blocklist.sh \
       "$BLOCKLIST_DIR/update-blocklist.sh"

    chmod +x "$BLOCKLIST_DIR/update-blocklist.sh"

    info "Generating initial blocklist..."

    "$BLOCKLIST_DIR/update-blocklist.sh"

    success "Blocklist installed."

}

#########################################
# OLD Cron Remove
#########################################

install_blocklist_cron(){

cat >/etc/cron.d/smartdns-blocklist <<EOF

EOF
	rm /etc/cron.d/smartdns-blocklist
}
