#!/usr/bin/env bash
#
# CHANGELOG:
# Standardized variable expansion by consistently using ${VAR} across all shell
# scripts to improve readability, consistency, and safety. This follows shell
# scripting best practices and helps prevent issues related to word splitting
# and pathname expansion (globbing). Additionally, fixed ShellCheck warnings,
# corrected Markdown formatting errors, added appropriate ShellCheck directives,
# removed unused color variables, improved shebang declarations, and performed
# general code quality and maintainability improvements.
#

####################################
# CPU
####################################
# shellcheck disable=SC2312
detect_cpu(){

    CPU_MODEL=$(lscpu | awk -F: '/Model name:/{
        gsub(/^[ \t]+/,"",$2)
        print $2
    }')
	
	CPU_PHYSICAL=$(lscpu | awk -F: '
	/Core\(s\) per socket/ {gsub(/ /,"",$2); c=$2}
	/Socket\(s\)/ {gsub(/ /,"",$2); s=$2}
	END {print c*s}')

    CPU_THREADS=$(nproc)

    CPU_ARCH=$(uname -m)

}

####################################
# MEMORY
####################################
detect_memory(){

    RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)

    RAM_GB=$((RAM_MB/1024))

}

####################################
# VIRTUALIZATION
####################################
detect_virtualization(){

    if command -v systemd-detect-virt >/dev/null 2>&1; then

        VIRT=$(systemd-detect-virt)

        case "${VIRT}" in
            kvm)         VIRT="KVM" ;;
            oracle)      VIRT="VirtualBox" ;;
            vmware)      VIRT="VMware" ;;
            microsoft)   VIRT="Hyper-V" ;;
            xen)         VIRT="Xen" ;;
            qemu)        VIRT="QEMU" ;;
            lxc)         VIRT="LXC Container" ;;
            docker)      VIRT="Docker" ;;
            openvz)      VIRT="OpenVZ" ;;
            none|"")     VIRT="Bare Metal" ;;
            *)           VIRT="${VIRT^^}" ;;
        esac

    else

        VIRT="Unknown"

    fi

}

####################################
# IPv4
####################################
# shellcheck disable=SC2312
detect_ipv4(){

    SERVER_IPV4=$(ip route get 1.1.1.1 \
        | awk '{print $7}' \
        | head -1)

}

####################################
# IPv6
####################################
detect_ipv6(){

    SERVER_IPV6=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null \
        | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' \
        | head -1) || true
}

####################################
# NETWORK
####################################
# shellcheck disable=SC2312
detect_network(){

    DEFAULT_IF=$(ip route \
        | awk '/default/ {print $5}' \
        | head -1)

    detect_ipv4

    detect_ipv6 || true

}

####################################
# NIC SPEED
####################################
detect_nic_speed(){

    if [[ -f /sys/class/net/${DEFAULT_IF}/speed ]]; then

        NIC_SPEED=$(cat /sys/class/net/"${DEFAULT_IF}"/speed 2>/dev/null)

        [[ "${NIC_SPEED}" == "-1" ]] && NIC_SPEED="Unknown"

    else

        NIC_SPEED="Unknown"

    fi

}

####################################
# INTERNET TEST
####################################
detect_internet(){

if ping -c1 1.1.1.1 >/dev/null 2>&1

then

ONLINE="Online"

else

ONLINE="Offline"

fi

}

####################################
# HOSTNAME
####################################
detect_hostname(){

    HOSTNAME=$(hostname)

}

####################################
# KERNEL
####################################

detect_kernel(){

KERNEL=$(uname -r)

}

####################################
# UPTIME
####################################
detect_uptime(){

UPTIME=$(uptime -p)

}

####################################
# SUMMARY
####################################
# shellcheck disable=SC2312
summary(){

echo
echo "======================================"
echo "      SERVER INFORMATION"
echo "======================================"

printf "%-20s : %s\n" "Hostname" "${HOSTNAME}"
printf "%-20s : %s\n" "OS" "${OS} ${VERSION}"
printf "%-20s : %s\n" "Kernel" "${KERNEL}"
printf "%-20s : %s\n" "Virtualization" "${VIRT}"

printf "%-20s : %s\n" "CPU Model" "${CPU_MODEL}"
printf "%-20s : %s\n" "CPU Core" "${CPU_PHYSICAL}"
printf "%-20s : %s\n" "CPU Threads" "${CPU_THREADS}"
printf "%-20s : %s\n" "Architecture" "${CPU_ARCH}"

printf "%-20s : %s GB\n" "RAM" "$(awk "BEGIN{printf \"%.1f\",${RAM_MB}/1024}")"

printf "%-20s : %s\n" "Interface" "${DEFAULT_IF}"
printf "%-20s : %s\n" "IPv4" "${SERVER_IPV4}"
printf "%-20s : %s\n" "IPv6" "${SERVER_IPV6:-Not Detected}"
printf "%-20s : %s\n" "NIC SPEED" "${NIC_SPEED}"
printf "%-20s : %s\n" "Internet" "${ONLINE}"

printf "%-20s : %s\n" "Up since" "${UPTIME}"

echo
}

####################################
# SAVE DETECT RESULT
####################################
save_detect_cache(){

mkdir -p /tmp/smartdns

cat > /tmp/smartdns/system.env <<EOF
HOSTNAME=${HOSTNAME}
OS=${OS}
VERSION=${VERSION}
VIRT=${VIRT}
CPU_MODEL=${CPU_MODEL}
CPU_THREADS=${CPU_THREADS}
CPU_ARCH=${CPU_ARCH}
RAM_MB=${RAM_MB}
RAM_GB=${RAM_GB}
DEFAULT_IF=${DEFAULT_IF}
SERVER_IPV4=${SERVER_IPV4}
SERVER_IPV6=${SERVER_IPV6}
NIC_SPEED=${NIC_SPEED}
ONLINE=${ONLINE}
KERNEL=${KERNEL}
UPTIME=${UPTIME}
EOF

}
