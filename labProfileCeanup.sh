#!/bin/bash

# ==============================================================================
# Remove Local User Profiles Inactive for > 30 Days
# ==============================================================================

# Days of inactivity required before profile deletion
INACTIVITY_DAYS=30

# Calculate cutoff threshold in seconds (30 days * 86400 seconds/day)
CUTOFF_SECONDS=$(( INACTIVITY_DAYS * 86400 ))
CURRENT_EPOCH=$(date +%s)

# 1. DEFINE PROTECTED ACCOUNTS
EXCLUDED_ADMINS=("admin" "administrator" "itadmin" "localadmin" "jamfadmin" "kandjiadmin")
CURRENT_USER=$(stat -f "%Su" /dev/console)
SYSTEM_EXCLUSIONS=("root" "daemon" "nobody" "Shared" "_kandji" "_jamf" "$CURRENT_USER")

ALL_PROTECTED=("${EXCLUDED_ADMINS[@]}" "${SYSTEM_EXCLUSIONS[@]}")

echo "=========================================="
echo "Starting inactive profile cleanup (> $INACTIVITY_DAYS days)..."
echo "=========================================="

# 2. QUERY ALL LOCAL USERS WITH UID >= 501
LOCAL_USERS=$(dscl . -list /Users UniqueID | awk '$2 >= 501 {print $1}')

if [ -z "$LOCAL_USERS" ]; then
    echo "No non-system user profiles found. Exiting."
    exit 0
fi

# 3. EVALUATE INACTIVITY AND DELETE
for USERNAME in $LOCAL_USERS; do
    
    # Check if account is protected
    IS_PROTECTED=false
    for PROTECTED in "${ALL_PROTECTED[@]}"; do
        if [[ "$USERNAME" == "$PROTECTED" ]]; then
            IS_PROTECTED=true
            break
        fi
    done

    if [ "$IS_PROTECTED" = true ]; then
        echo "SKIPPING: '$USERNAME' is protected or currently logged in."
        continue
    fi

    USER_HOME="/Users/$USERNAME"

    if [ ! -d "$USER_HOME" ]; then
        echo "SKIPPING: '$USERNAME' has no home directory at $USER_HOME."
        continue
    fi

    # Determine last activity timestamp.
    # Checks specific user preference file first; falls back to Home folder mod time.
    PREF_FILE="$USER_HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
    if [ -f "$PREF_FILE" ]; then
        LAST_LOGGED_EPOCH=$(stat -f %m "$PREF_FILE")
    else
        LAST_LOGGED_EPOCH=$(stat -f %m "$USER_HOME")
    fi

    # Calculate days inactive
    AGE_SECONDS=$(( CURRENT_EPOCH - LAST_LOGGED_EPOCH ))
    AGE_DAYS=$(( AGE_SECONDS / 86400 ))

    if [ "$AGE_SECONDS" -ge "$CUTOFF_SECONDS" ]; then
        echo "DELETING: '$USERNAME' has been inactive for $AGE_DAYS days (Threshold: $INACTIVITY_DAYS days)."
        
        sysadminctl -deleteUser "$USERNAME" -secure

        # Residual directory check
        if [ -d "$USER_HOME" ]; then
            rm -rf "$USER_HOME"
            echo "Cleaned residual folder at $USER_HOME."
        fi
        
        echo "SUCCESS: Profile '$USERNAME' removed."
    else
        echo "SKIPPING: '$USERNAME' was active $AGE_DAYS days ago (under $INACTIVITY_DAYS day threshold)."
    fi

done

echo "=========================================="
echo "Cleanup complete."
echo "=========================================="
exit 0
