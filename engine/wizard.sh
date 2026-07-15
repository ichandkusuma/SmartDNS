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

#########################################
# SMART INSTALLATION WIZARD
#########################################

run_wizard(){

    mkdir -p cache

    #################################
    # Default Configuration
    #################################

    ENABLE_DNSSEC="yes"
    ENABLE_RATELIMIT="yes"
    ENABLE_QUERYLOG="no"

    DNSSEC_STATUS="Enabled"
    RATELIMIT_STATUS="Enabled"
    QUERYLOG_STATUS="Disabled"

    if [[ -n "${SERVER_IPV6:-}" ]]; then
        ENABLE_IPV6="yes"
        IPV6_STATUS="${SERVER_IPV6}"
    else
        ENABLE_IPV6="no"
        IPV6_STATUS="Not Detected"
    fi
	
	SPOOF_IPV4="103.151.222.227"
	SPOOF_IPV6="2406:20c0::103:151:222:227"

    RECURSIVE_PORT=5300
    FRONTEND_PORT=53

    #################################
    # Show Summary
    #################################

    echo
    echo "======================================"
    echo "     SMART INSTALLATION WIZARD"
    echo "======================================"
    echo

    printf "%-20s : %s\n" "Hostname" "${HOSTNAME}"
    printf "%-20s : %s\n" "OS" "${OS} ${VERSION}"
    printf "%-20s : %s Core\n" "CPU" "${CPU_THREADS}"
    # shellcheck disable=SC2312
    printf "%-20s : %.1f GB\n" "RAM" "$(awk "BEGIN{printf \"%.1f\", ${RAM_MB}/1024}")"
    # shellcheck disable=SC2153
    printf "%-20s : %s\n" "IPv4" "${SERVER_IPV4}"
    printf "%-20s : %s\n" "IPv6" "${IPV6_STATUS}"

    echo
    echo "--------------------------------------"
    echo " Auto Configuration"
    echo "--------------------------------------"

    printf "%-20s : %s\n" "Unbound Threads" "${UNBOUND_THREADS}"
    printf "%-20s : %s\n" "DNSSEC" "${DNSSEC_STATUS}"
    printf "%-20s : %s\n" "Rate Limit" "${RATELIMIT_STATUS}"
    printf "%-20s : %s\n" "Query Log" "${QUERYLOG_STATUS}"
    printf "%-20s : %s\n" "Recursive Port" "${RECURSIVE_PORT}"
    printf "%-20s : %s\n" "Frontend Port" "${FRONTEND_PORT}"

    echo

    #################################
    # Continue / Customize
    #################################

    while true
    do

        read -rp "Press ENTER to continue or C to customize : " CUSTOM

        case "${CUSTOM^^}" in

            "")

                break
                ;;

            C)

                #################################
                # IPv6
                #################################

                if [[ -n "${SERVER_IPV6:-}" ]]; then

                    ENABLE_IPV6=$(ask_yes_no "Enable IPv6? [Y/n] :" "Y")

                fi

 
				#################################
				# Recursive Port
				#################################

				while true
				do

					RECURSIVE_PORT=$(ask_recursive_port "Recursive Port [${RECURSIVE_PORT}] :" "${RECURSIVE_PORT}")
					
					if (( RECURSIVE_PORT == 53 )); then
						warn "Recursive Port cannot use port 53."
						continue
					fi

					break

				done

				#################################
				# Frontend Port
				#################################

				while true
				do

					FRONTEND_PORT=$(ask_frontend_port "Frontend Port [${FRONTEND_PORT}] :" "${FRONTEND_PORT}")

					if [[ "${FRONTEND_PORT}" == "${RECURSIVE_PORT}" ]]; then
						warn "Frontend Port cannot be the same as Recursive Port (${RECURSIVE_PORT})."
						continue
					fi

					break

				done
				
				while true
				do
					read -rp "Spoof IPv4 [${SPOOF_IPV4}] : " TMP

					TMP=${TMP:-${SPOOF_IPV4}}

					if validate_ipv4 "${TMP}"; then
						SPOOF_IPV4="${TMP}"
						break
					fi

					warn "Invalid IPv4."

				done

				if [[ "${ENABLE_IPV6}" == "yes" ]]; then

					while true
					do
						read -rp "Spoof IPv6 [${SPOOF_IPV6}] : " TMP

						TMP=${TMP:-${SPOOF_IPV6}}

						if validate_ipv6 "${TMP}"; then
							SPOOF_IPV6="${TMP}"
							break
						fi

						warn "Invalid IPv6."

					done

				fi
				
				
				echo
				read -rsp "DNSDist Web Password (ENTER = Auto Generate) : " TMP
				echo

				# shellcheck disable=SC2034
				DNSDIST_WEB_PASSWORD="${TMP}"


                break
                ;;

            *)

                warn "Invalid choice. Press ENTER or C."
                ;;

        esac

    done

    #################################
    # Save Wizard
    #################################

    cat > cache/wizard.env <<EOF
ENABLE_IPV6=${ENABLE_IPV6}
ENABLE_DNSSEC=${ENABLE_DNSSEC}
ENABLE_RATELIMIT=${ENABLE_RATELIMIT}
ENABLE_QUERYLOG=${ENABLE_QUERYLOG}
RECURSIVE_PORT=${RECURSIVE_PORT}
FRONTEND_PORT=${FRONTEND_PORT}
SPOOF_IPV4=${SPOOF_IPV4}
SPOOF_IPV6=${SPOOF_IPV6}
EOF

    success "Wizard completed."

}
