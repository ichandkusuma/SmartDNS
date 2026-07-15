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

set -euo pipefail

#########################################
# SmartDNS Blocklist Updater
#########################################

WORKDIR="/opt/blocklist"

SOURCE="${WORKDIR}/sources.txt"

FINAL="${WORKDIR}/domains.txt"

CDB_FILE="${WORKDIR}/domains.cdb"

LOG="${WORKDIR}/update.log"

LOCKFILE="/var/run/blocklist-update.lock"

#########################################
# Dependency Check
#########################################

command -v curl >/dev/null || {
    echo "curl not found"
    exit 1
}

command -v cdbmake >/dev/null || {
    echo "cdbmake not found"
    exit 1
}

command -v dnsdist >/dev/null || {
    echo "dnsdist not found"
    exit 1
}

#########################################
# Lock
#########################################

exec 9>"${LOCKFILE}"

flock -n 9 || {
    echo "Another update is already running."
    exit 0
}

#########################################
# Temporary Files
#########################################

RAW=$(mktemp)
NEW=$(mktemp)
TMP=$(mktemp)
CDB_INPUT=$(mktemp)
CDB_TMP=$(mktemp)

trap 'rm -f "$RAW" "$NEW" "$TMP" "$CDB_INPUT" "$CDB_TMP"' EXIT

#########################################
# Header
#########################################

echo "======================================" | tee -a "${LOG}"
echo "Updating DNS Blocklist" | tee -a "${LOG}"
date | tee -a "${LOG}"
echo "======================================" | tee -a "${LOG}"

#########################################
# Download Sources
#########################################

SUCCESS=0

while read -r URL
do
    [[ -z "${URL}" || "${URL}" =~ ^# ]] && continue

    echo "Trying ${URL}" | tee -a "${LOG}"

    DOWNLOAD=$(mktemp)

    if curl \
        -L \
        --retry 3 \
        --retry-delay 5 \
        --connect-timeout 10 \
        --max-time 120 \
        -fsSL \
        "${URL}" \
        -o "${DOWNLOAD}"
    then

        # Pastikan file tidak kosong
        if [[ -s "${DOWNLOAD}" ]] && ! grep -qi "<html" "${DOWNLOAD}"; then
            cp "${DOWNLOAD}" "${RAW}"
            SUCCESS=1
            echo "Success: ${URL}" | tee -a "${LOG}"
            rm -f "${DOWNLOAD}"
            break
        fi

        echo "Invalid content: ${URL}" | tee -a "${LOG}"
    else
        echo "Failed: ${URL}" | tee -a "${LOG}"
    fi

    rm -f "${DOWNLOAD}"

done < "${SOURCE}"

if [[ ${SUCCESS} -eq 0 ]]; then
    echo "All sources failed." | tee -a "${LOG}"
    exit 1
fi

#########################################
# Validation
#########################################

if [[ ! -s "${RAW}" ]]; then

    echo "Download failed." | tee -a "${LOG}"

    exit 1

fi

if grep -qi "<html" "${RAW}"; then

    echo "Downloaded HTML page." | tee -a "${LOG}"

    exit 1

fi

#########################################
# Extract Domains
#########################################

echo "Extracting domains..." | tee -a "${LOG}"

grep -Eo '([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "${RAW}" \
| sed 's/^\.//' \
| tr '[:upper:]' '[:lower:]' \
| sort -u \
> "${NEW}"

COUNT=$(wc -l < "${NEW}")

echo "Domains : ${COUNT}" | tee -a "${LOG}"

if (( COUNT < 1000 )); then

    echo "Blocklist too small. Update cancelled." | tee -a "${LOG}"

    exit 1

fi

#########################################
# Replace Blocklist
#########################################

mv "${NEW}" "${TMP}"

TOTAL=$(wc -l < "${TMP}")

echo "Replacing blocklist (${TOTAL} domains)" | tee -a "${LOG}"

mv "${TMP}" "${FINAL}"

#########################################
# Convert to CDB
#########################################

echo "Building CDB..." | tee -a "${LOG}"

awk '{
    print "+" length($0) ",1:" $0 "->1"
}
END{
    print ""
}' "${FINAL}" > "${CDB_INPUT}"

cdbmake "${CDB_TMP}" "${WORKDIR}/cdbmake.tmp" < "${CDB_INPUT}"

if [[ ! -s "${CDB_TMP}" ]]; then

    echo "CDB build failed." | tee -a "${LOG}"

    exit 1

fi

mv "${CDB_TMP}" "${CDB_FILE}"

echo "CDB build completed." | tee -a "${LOG}"

#########################################
# Reload dnsdist
#########################################

echo "Reloading dnsdist..." | tee -a "${LOG}"

if dnsdist -c -e "reloadConfig"
then

    echo "dnsdist reloaded." | tee -a "${LOG}"

else

    echo "dnsdist reload failed." | tee -a "${LOG}"

    exit 1

fi

#########################################
# Finish
#########################################

echo "Update completed successfully." | tee -a "${LOG}"

exit 0

