#!/usr/bin/env bash

set -euo pipefail

#########################################
# SmartDNS Blocklist Updater
#########################################

WORKDIR="/opt/blocklist"

SOURCE="$WORKDIR/sources.txt"

FINAL="$WORKDIR/domains.txt"

CDB_FILE="$WORKDIR/domains.cdb"

LOG="$WORKDIR/update.log"

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

command -v gzip >/dev/null || {
    echo "gzip not found"
    exit 1
}

#########################################
# Lock
#########################################

exec 9>"$LOCKFILE"

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

echo "======================================" | tee -a "$LOG"
echo "Updating DNS Blocklist" | tee -a "$LOG"
date | tee -a "$LOG"
echo "======================================" | tee -a "$LOG"

#########################################
# Download Sources
#########################################

SUCCESS=1
FALLBACK_URLS=()

> "$RAW"

download_source() {

    local URL="$1"
    local DOWNLOAD
    local CONTENT
    local IS_GZIP=0

    DOWNLOAD=$(mktemp)
    CONTENT=$(mktemp)

    cleanup_source_tmp() {
        rm -f "$DOWNLOAD" "$CONTENT"
    }

    if curl \
        -L \
        --retry 3 \
        --retry-delay 5 \
        --connect-timeout 10 \
        --max-time 120 \
        -fsSL \
        "$URL" \
        -o "$DOWNLOAD"
    then

        if [[ ! -s "$DOWNLOAD" ]]; then
            echo "Invalid content: $URL" | tee -a "$LOG"
            cleanup_source_tmp
            return 1
        fi

        # Prefer the URL extension, but also detect gzip by file magic.
        # This keeps compatibility with plain files and .txt files.
        if [[ "$URL" =~ \.gz([?#].*)?$ ]]; then
            IS_GZIP=1
        elif gzip -t "$DOWNLOAD" >/dev/null 2>&1; then
            IS_GZIP=1
        fi

        if (( IS_GZIP == 1 )); then

            echo "Detected gzip source: $URL" | tee -a "$LOG"

            if ! gzip -t "$DOWNLOAD" >/dev/null 2>&1; then
                echo "Invalid gzip: $URL" | tee -a "$LOG"
                cleanup_source_tmp
                return 1
            fi

            if ! gzip -dc "$DOWNLOAD" > "$CONTENT"; then
                echo "Gzip extraction failed: $URL" | tee -a "$LOG"
                cleanup_source_tmp
                return 1
            fi

        else

            echo "Detected plain source: $URL" | tee -a "$LOG"

            cat "$DOWNLOAD" > "$CONTENT"

        fi

        if [[ ! -s "$CONTENT" ]] || grep -qi "<html" "$CONTENT"; then
            echo "Invalid/HTML content: $URL" | tee -a "$LOG"
            cleanup_source_tmp
            return 1
        fi

        cat "$CONTENT" >> "$RAW"
        echo >> "$RAW"

        echo "Success: $URL" | tee -a "$LOG"

        cleanup_source_tmp
        return 0

    else

        echo "Failed: $URL" | tee -a "$LOG"

    fi

    cleanup_source_tmp
    return 1
}

while read -r TYPE URL
do

    [[ -z "${TYPE:-}" ]] && continue
    [[ "$TYPE" == \#* ]] && continue

    case "$TYPE" in

        merge)

            echo "Trying $URL" | tee -a "$LOG"

            if ! download_source "$URL"; then
                SUCCESS=0
            fi
            ;;

        fallback)

            FALLBACK_URLS+=( "$URL" )
            ;;

    esac

done < "$SOURCE"

#########################################
# Fallback
#########################################

if [[ $SUCCESS -eq 0 ]]; then

    echo "Merge source failed, using fallback..." | tee -a "$LOG"

    > "$RAW"

    if (( ${#FALLBACK_URLS[@]} == 0 )); then
        echo "No fallback source configured." | tee -a "$LOG"
        exit 1
    fi

    FALLBACK_SUCCESS=0

    for FALLBACK_URL in "${FALLBACK_URLS[@]}"; do
        [[ -z "$FALLBACK_URL" ]] && continue

        echo "Trying fallback $FALLBACK_URL" | tee -a "$LOG"

        if download_source "$FALLBACK_URL"; then
            FALLBACK_SUCCESS=1
            break
        fi

        echo "Fallback failed: $FALLBACK_URL" | tee -a "$LOG"
    done

    if (( FALLBACK_SUCCESS != 1 )); then
        echo "All fallback sources failed." | tee -a "$LOG"
        exit 1
    fi

fi

#########################################
# Validation
#########################################

if [[ ! -s "$RAW" ]]; then

    echo "Download failed." | tee -a "$LOG"

    exit 1

fi

if grep -qi "<html" "$RAW"; then

    echo "Downloaded HTML page." | tee -a "$LOG"

    exit 1

fi

#########################################
# Extract Domains
#########################################

echo "Extracting domains..." | tee -a "$LOG"

grep -Eo '([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$RAW" \
| sed 's/^\.//' \
| tr '[:upper:]' '[:lower:]' \
| sort -u \
> "$NEW"

COUNT=$(wc -l < "$NEW")

echo "Domains : $COUNT" | tee -a "$LOG"

if (( COUNT < 1000 )); then

    echo "Blocklist too small. Update cancelled." | tee -a "$LOG"

    exit 1

fi

#########################################
# Convert to CDB
#########################################

echo "Building CDB..." | tee -a "$LOG"

awk '{
    print "+" length($0) ",1:" $0 "->1"
}
END{
    print ""
}' "$NEW" > "$CDB_INPUT"

cdbmake "$CDB_TMP" "$WORKDIR/cdbmake.tmp" < "$CDB_INPUT"

if [[ ! -s "$CDB_TMP" ]]; then

    echo "CDB build failed." | tee -a "$LOG"

    exit 1

fi

#########################################
# Atomic Replace
#########################################

TOTAL=$(wc -l < "$NEW")

echo "Replacing blocklist ($TOTAL domains)" | tee -a "$LOG"

mv -f "$CDB_TMP" "$CDB_FILE"
mv -f "$NEW" "$FINAL"

echo "Blocklist and CDB replaced successfully." | tee -a "$LOG"

#########################################
# Reload dnsdist
#########################################

echo "Reloading dnsdist..." | tee -a "$LOG"

if systemctl is-active --quiet dnsdist; then

    if dnsdist -c -e "reloadConfig"; then

        echo "dnsdist reloaded." | tee -a "$LOG"

    else

        echo "dnsdist reload failed." | tee -a "$LOG"

        exit 1

    fi

else

    echo "dnsdist is not running. Reload skipped." | tee -a "$LOG"

fi

#########################################
# Finish
#########################################

echo "Update completed successfully." | tee -a "$LOG"

exit 0
