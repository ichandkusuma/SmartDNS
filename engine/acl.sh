#!/usr/bin/env bash

####################################
# ACL Wizard
####################################

run_acl(){

    mkdir -p cache

    ACL_FILE="cache/acl.list"

    cat > "$ACL_FILE" <<EOF
127.0.0.0/8
::1/128
EOF

    echo
    echo "======================================"
    echo "         RESOLVER ACL"
    echo "======================================"

    echo
    echo "Default ACL"
    echo "  - 127.0.0.0/8"
    echo "  - ::1/128"
    echo

    while true
    do

        CIDR=$(ask_cidr "Add Resolver CIDR (ENTER = Finish) :")

        [[ -z "$CIDR" ]] && break

        if grep -qx "$CIDR" "$ACL_FILE"; then

            warn "ACL already exists."

            continue

        fi

        echo "$CIDR" >> "$ACL_FILE"

        success "Added $CIDR"

    done

}

