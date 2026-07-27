#!/usr/bin/env bash

####################################
# Generate ACL Block
####################################

generate_acl(){

    ACL_CONTENT=""

    while read -r NETWORK
    do

        ACL_CONTENT+="    access-control: ${NETWORK} allow"$'\n'

    done < cache/acl.list

}

####################################
# IPv6
####################################

generate_ipv6(){

    if [[ "$ENABLE_IPV6" == "yes" ]]; then

        DO_IPV6="yes"

        IPV6_INTERFACE="    interface: ::1"

    else

        DO_IPV6="no"

        IPV6_INTERFACE=""

    fi

}

####################################
# Query Log
####################################

generate_querylog(){

    if [[ "$ENABLE_QUERYLOG" == "yes" ]]; then

QUERYLOG_CONTENT='    log-queries: yes
    log-replies: yes'

    else

        QUERYLOG_CONTENT=""

    fi

}


####################################
# Recursive Template
####################################

generate_recursive_conf(){

    cp templates/recursive.conf.tpl output/recursive.conf

    render_variable output/recursive.conf RECURSIVE_PORT "$RECURSIVE_PORT"
    render_variable output/recursive.conf DO_IPV6 "$DO_IPV6"

    render_variable output/recursive.conf THREAD "$UNBOUND_THREADS"

    render_variable output/recursive.conf RRSET_CACHE "$RRSET_CACHE"
    render_variable output/recursive.conf MSG_CACHE "$MSG_CACHE"

    render_variable output/recursive.conf SLABS "$SLABS"

    render_variable output/recursive.conf OUTGOING_RANGE "$OUTGOING_RANGE"
    render_variable output/recursive.conf NUM_QUERIES "$NUM_QUERIES"
    render_variable output/recursive.conf INFRA_CACHE "$INFRA_CACHE"

    render_block output/recursive.conf ACL "$ACL_CONTENT"
    render_block output/recursive.conf QUERY_LOG "$QUERYLOG_CONTENT"

}

####################################
# dnsdist IPv6
####################################

build_dnsdist_ipv6(){

    if [[ "$ENABLE_IPV6" == "yes" ]]; then

        DNSDIST_IPV6_FRONTEND='setLocal("[::]:{{FRONTEND_PORT}}")'

        DNSDIST_IPV6_BACKEND='newServer({
    address="[::1]:{{RECURSIVE_PORT}}"
})'

    else

        DNSDIST_IPV6_FRONTEND=""

        DNSDIST_IPV6_BACKEND=""

    fi

}

####################################
# dnsdist ACL
####################################

build_dnsdist_acl(){

    DNSDIST_ACL="setACL({
"

    while read -r ACL
    do

        DNSDIST_ACL+="    \"$ACL\",
"

    done < cache/acl.list

    DNSDIST_ACL="${DNSDIST_ACL%,*$'\n'}"$'\n'

    DNSDIST_ACL+="})"

}

####################################
# dnsdist Web ACL
####################################

build_dnsdist_web_acl(){

    DNSDIST_WEB_ACL=""

    while read -r ACL
    do
        if [[ -z "$DNSDIST_WEB_ACL" ]]; then
            DNSDIST_WEB_ACL="$ACL"
        else
            DNSDIST_WEB_ACL+=",$ACL"
        fi
    done < cache/acl.list

}

####################################
# Rate Limit
####################################

build_ratelimit(){

    RATELIMIT_CONTENT=""

}

####################################
# Query Log
####################################

build_querylog(){

    if [[ "$ENABLE_QUERYLOG" == "yes" ]]; then

        QUERYLOG_CONTENT='addAction(AllRule(), LogAction("/var/log/dnsdist.log"))'

    else

        QUERYLOG_CONTENT=""

    fi

}

####################################
# Generate dnsdist.conf
####################################

generate_dnsdist_conf(){

    cp templates/dnsdist.conf.tpl output/dnsdist.conf

    render_variable output/dnsdist.conf FRONTEND_PORT "$FRONTEND_PORT"
    render_variable output/dnsdist.conf RECURSIVE_PORT "$RECURSIVE_PORT"

    render_variable output/dnsdist.conf PACKET_CACHE "$DNSDIST_CACHE"
    render_variable output/dnsdist.conf TCP_THREADS "$TCP_THREADS"
    render_variable output/dnsdist.conf TCP_QUEUE "$TCP_QUEUE"
    render_variable output/dnsdist.conf UDP_OUTSTANDING "$UDP_OUTSTANDING"

    render_variable output/dnsdist.conf DNSDIST_KEY "$DNSDIST_KEY"
    render_variable output/dnsdist.conf DNSDIST_API_KEY "$DNSDIST_API_KEY"
    render_variable output/dnsdist.conf DNSDIST_WEB_PASSWORD "$DNSDIST_WEB_PASSWORD"
	render_variable output/dnsdist.conf DNSDIST_WEB_ACL "$DNSDIST_WEB_ACL"

    render_variable output/dnsdist.conf SPOOF_IPV4 "$SPOOF_IPV4"
    render_variable output/dnsdist.conf SPOOF_IPV6 "$SPOOF_IPV6"

    render_block output/dnsdist.conf IPV6_FRONTEND "$DNSDIST_IPV6_FRONTEND"
    render_block output/dnsdist.conf IPV6_BACKEND "$DNSDIST_IPV6_BACKEND"

    render_block output/dnsdist.conf RATELIMIT "$RATELIMIT_CONTENT"
    render_block output/dnsdist.conf QUERYLOG "$QUERYLOG_CONTENT"

    render_block output/dnsdist.conf DNSDIST_ACL "$DNSDIST_ACL"

    render_variable output/dnsdist.conf FRONTEND_PORT "$FRONTEND_PORT"
    render_variable output/dnsdist.conf RECURSIVE_PORT "$RECURSIVE_PORT"

}


####################################
# Main
####################################

generate_templates(){

	generate_acl

	generate_ipv6

	generate_querylog

	build_dnsdist_ipv6
	
	build_dnsdist_acl
	
	build_dnsdist_web_acl

	build_ratelimit

	build_querylog

	generate_recursive_conf

	generate_dnsdist_conf

}


