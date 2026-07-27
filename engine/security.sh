#!/usr/bin/env bash

####################################
# Disable systemd-resolved
####################################
disable_systemd_resolved(){

    if systemctl is-active --quiet systemd-resolved; then

        info "Disabling systemd-resolved..."

        systemctl disable --now systemd-resolved

        success "systemd-resolved disabled."

    fi

}

####################################
# Backup resolv.conf
####################################
backup_resolv(){

    if [[ -f /etc/resolv.conf ]] && [[ ! -f /etc/resolv.conf.smartdns.bak ]]; then

        cp /etc/resolv.conf /etc/resolv.conf.smartdns.bak

        success "resolv.conf backup created."

    fi

}

####################################
# Temporary resolv.conf
####################################
temp_resolv(){

cat >/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
options edns0 trust-ad
EOF

    success "resolv.conf generated."

}

####################################
# Generate resolv.conf
####################################
generate_resolv(){

cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
options edns0 trust-ad
EOF

    success "resolv.conf generated."

}

####################################
# Secure Permission
####################################
secure_permissions(){

    chmod 640 /etc/unbound/*.conf 2>/dev/null

    chmod 640 /etc/dnsdist/*.conf 2>/dev/null

    chmod 700 cache output 2>/dev/null

}

####################################
# Prepare DNS Environment
####################################
prepare_dns_environment(){

    backup_resolv

    disable_systemd_resolved

    generate_resolv

    secure_permissions

}

