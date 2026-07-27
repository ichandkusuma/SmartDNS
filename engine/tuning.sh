#!/usr/bin/env bash

############################################################
# SMART DNS TUNING ENGINE
############################################################

#########################################
# Utility
#########################################

next_power_of_two() {

    local n=$1
    local p=1

    while (( p < n ))
    do
        p=$((p*2))
    done

    echo "$p"

}

#########################################
# Unbound
#########################################

tuning_unbound(){

    #################################
    # THREAD
    #################################

    if (( CPU_THREADS <= 2 )); then

        UNBOUND_THREADS=2

    elif (( CPU_THREADS <=4 )); then

        UNBOUND_THREADS=4

    elif (( CPU_THREADS <=8 )); then

        UNBOUND_THREADS=8

    elif (( CPU_THREADS <=16 )); then

        UNBOUND_THREADS=12

    elif (( CPU_THREADS <=24 )); then

        UNBOUND_THREADS=16

    elif (( CPU_THREADS <=32 )); then

        UNBOUND_THREADS=20

    elif (( CPU_THREADS <=48 )); then

        UNBOUND_THREADS=24

    else

        UNBOUND_THREADS=32

    fi

#################################
# CACHE
#################################

if (( RAM_MB <= 2048 )); then

    RRSET_CACHE="64m"
    MSG_CACHE="32m"

elif (( RAM_MB <= 4096 )); then

    RRSET_CACHE="128m"
    MSG_CACHE="64m"

elif (( RAM_MB <= 8192 )); then

    RRSET_CACHE="256m"
    MSG_CACHE="128m"

elif (( RAM_MB <= 16384 )); then

    RRSET_CACHE="512m"
    MSG_CACHE="256m"

elif (( RAM_MB <= 32768 )); then

    RRSET_CACHE="1024m"
    MSG_CACHE="512m"

elif (( RAM_MB <= 65536 )); then

    RRSET_CACHE="2048m"
    MSG_CACHE="1024m"

else

    RRSET_CACHE="4096m"
    MSG_CACHE="2048m"

fi

    #################################
    # SLABS
    #################################

    SLABS=$(next_power_of_two "$UNBOUND_THREADS")

    ((SLABS>32)) && SLABS=32

    #################################
    # QUERY
    #################################

    OUTGOING_RANGE=$((UNBOUND_THREADS*1024))

    ((OUTGOING_RANGE<4096)) && OUTGOING_RANGE=4096
    ((OUTGOING_RANGE>65535)) && OUTGOING_RANGE=65535

    NUM_QUERIES=$((UNBOUND_THREADS*512))

if (( RAM_MB <= 4096 )); then

    INFRA_CACHE=100000

elif (( RAM_MB <= 8192 )); then

    INFRA_CACHE=200000

elif (( RAM_MB <= 16384 )); then

    INFRA_CACHE=400000

elif (( RAM_MB <= 32768 )); then

    INFRA_CACHE=800000

else

    INFRA_CACHE=1000000

fi

}

#########################################
# dnsdist
#########################################

tuning_dnsdist(){

    #################################
    # PACKET CACHE
    #################################

    if (( RAM_MB <2048 ))

    then

        DNSDIST_CACHE=100000

    elif (( RAM_MB <4096 ))

    then

        DNSDIST_CACHE=300000

    elif (( RAM_MB <8192 ))

    then

        DNSDIST_CACHE=500000

    elif (( RAM_MB <16384 ))

    then

        DNSDIST_CACHE=1000000

    elif (( RAM_MB <32768 ))

    then

        DNSDIST_CACHE=2000000

    else

        DNSDIST_CACHE=5000000

    fi

    #################################
    # TCP
    #################################

    TCP_THREADS=$((CPU_THREADS*8))

    ((TCP_THREADS<32)) && TCP_THREADS=32

if (( CPU_THREADS <= 4 )); then

    TCP_QUEUE=1024

elif (( CPU_THREADS <= 8 )); then

    TCP_QUEUE=2048

elif (( CPU_THREADS <= 16 )); then

    TCP_QUEUE=4096

else

    TCP_QUEUE=8192

fi

    #################################
    # UDP
    #################################

    if (( RAM_MB <4096 ))

    then

        UDP_OUTSTANDING=16384

    elif (( RAM_MB <8192 ))

    then

        UDP_OUTSTANDING=32768

    else

        UDP_OUTSTANDING=65535

    fi

}

#########################################
# Network
#########################################

tuning_network(){

    if [[ -n "$SERVER_IPV6" ]]

    then

        IPV6_AVAILABLE=yes

    else

        IPV6_AVAILABLE=no

    fi

}

#########################################
# Main
#########################################

calculate_tuning(){

    tuning_unbound

    tuning_dnsdist

    tuning_network

}

#########################################
# Save
#########################################

save_tuning(){

mkdir -p /tmp/smartdns

cat > /tmp/smartdns/tuning.env <<EOF
UNBOUND_THREADS=$UNBOUND_THREADS
RRSET_CACHE=$RRSET_CACHE
MSG_CACHE=$MSG_CACHE
SLABS=$SLABS
OUTGOING_RANGE=$OUTGOING_RANGE
NUM_QUERIES=$NUM_QUERIES
INFRA_CACHE=$INFRA_CACHE

DNSDIST_CACHE=$DNSDIST_CACHE
TCP_THREADS=$TCP_THREADS
TCP_QUEUE=$TCP_QUEUE
UDP_OUTSTANDING=$UDP_OUTSTANDING

IPV6_AVAILABLE=$IPV6_AVAILABLE
EOF

}

#########################################
# Show Result
#########################################

show_tuning(){

echo
echo "======================================"
echo " SMART TUNING RESULT"
echo "======================================"

printf "%-25s : %s\n" "Threads" "$UNBOUND_THREADS"
printf "%-25s : %s\n" "RRSET Cache" "$RRSET_CACHE"
printf "%-25s : %s\n" "MSG Cache" "$MSG_CACHE"
printf "%-25s : %s\n" "Slabs" "$SLABS"
printf "%-25s : %s\n" "Outgoing Range" "$OUTGOING_RANGE"
printf "%-25s : %s\n" "Queries / Thread" "$NUM_QUERIES"
printf "%-25s : %s\n" "Infra Cache" "$INFRA_CACHE"

echo

printf "%-25s : %s\n" "Packet Cache" "$DNSDIST_CACHE"
printf "%-25s : %s\n" "TCP Threads" "$TCP_THREADS"
printf "%-25s : %s\n" "TCP Queue" "$TCP_QUEUE"
printf "%-25s : %s\n" "UDP Outstanding" "$UDP_OUTSTANDING"

echo

printf "%-25s : %s\n" "IPv6 Available" "$IPV6_AVAILABLE"

echo

}