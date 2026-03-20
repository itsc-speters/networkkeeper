#!/bin/zsh

# Network Drive Keeper - Maintains connections to network drives
# Date: May 28, 2025

# Configuration - Adjust these values to your needs
NETWORK_SHARES=(
    # Examples - replace these with your actual network drives
    # "smb://server.local/share1"
    # "smb://192.168.1.100/documents"
    # "afp://server.local/share2"
)

# Settings
CHECK_INTERVAL_FAST=5    # Fast check when mounted (seconds)
CHECK_INTERVAL_SLOW=30   # Slow check when disconnected (seconds)
MOUNT_TIMEOUT=60         # Max seconds to wait for a mount to complete (needs headroom for slow reconnects after VPN)
AUTH_ERROR_FAST_THRESHOLD=10  # If mount fails within this many seconds, it's likely a real auth error
MAX_LOG_SIZE=1048576     # 1MB
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.networkkeeper.plist"
SERVICE_NAME="com.user.networkkeeper"
MAX_AUTH_FAILURES=2      # Pause after this many consecutive auth failures
AUTH_PAUSED_FILE="$HOME/.network_keeper_auth_paused"

# Note: Credentials are automatically handled via macOS Keychain

# Helper functions
send_notification() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Basso\"" 2>/dev/null
}

is_auth_paused() {
    [[ -f "$AUTH_PAUSED_FILE" ]]
}

pause_auth_retries() {
    local share="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $share" > "$AUTH_PAUSED_FILE"
    log_message "🔒 Auth retries paused after $MAX_AUTH_FAILURES consecutive failures on: $share"
    send_notification "Network Keeper: Login-Fehler" \
        "Zu viele fehlgeschlagene Anmeldeversuche. Keychain-Passwort aktualisieren, dann 'nk resume' ausführen."
}

is_service_running() {
    launchctl list | grep -q "$SERVICE_NAME"
}

get_mount_point() {
    local share="$1"
    local share_name=$(basename "$share")
    echo "/Volumes/$share_name"
}

# Check if a network share is actually available
is_share_available() {
    local share="$1"
    local protocol=""
    local host=""
    local port=""
    
    # Parse: protocol://host/path or protocol://host:port/path
    if [[ "$share" =~ ^([a-z]+)://([a-zA-Z0-9._-]+)(:([0-9]+))?(/.*)?$ ]]; then
        # Zsh style - use match array
        protocol="${match[1]}"
        host="${match[2]}"
        port="${match[4]}"
        
        # Remove username if present (user@host -> host)
        host="${host##*@}"
    else
        log_message "⚠️ Cannot parse share URL: $share"
        return 1
    fi
    
    # Check if the service port is open
    case "$protocol" in
        smb|cifs)
            local smb_port="${port:-445}"
            nc -z -w 2 "$host" "$smb_port" 2>/dev/null || \
            nc -z -w 2 "$host" 139 2>/dev/null
            ;;
        afp)
            nc -z -w 2 "$host" "${port:-548}" 2>/dev/null
            ;;
        nfs)
            nc -z -w 2 "$host" "${port:-2049}" 2>/dev/null
            ;;
        *)
            # Unknown protocol - assume available
            return 0
            ;;
    esac
}

# Functions
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file_path="$HOME/.network_keeper.log"
    
    # Write to log file
    echo "[$timestamp] $message" >> "$log_file_path"
    
    # Rotate log file if too large
    if [[ -f "$log_file_path" ]] && [[ $(stat -f%z "$log_file_path" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
        mv "$log_file_path" "${log_file_path}.old"
        touch "$log_file_path"
    fi
}

check_mount() {
    local share="$1"
    mount | grep -q "$(get_mount_point "$share")"
}

mount_share() {
    local share="$1"

    # Check if the share is available (port check)
    if ! is_share_available "$share"; then
        log_message "⚠️ Share not available: $share"
        return 1
    fi

    log_message "Attempting to connect to $share..."

    # Mount using osascript (macOS creates mount point automatically)
    local mount_output=""
    local mount_status=0

    # Execute mount command using osascript with timeout and background execution
    # This prevents system error dialogs from appearing
    (
        # Run in subshell with timeout to prevent dialogs and hanging
        osascript <<EOF 2>&1
try
    mount volume "$share"
    return "success"
on error errMsg
    return "error: " & errMsg
end try
EOF
    ) > /tmp/.nk_mount_$$ 2>&1 &

    local mount_pid=$!
    local wait_time=0

    # Wait for the mount to complete
    while kill -0 "$mount_pid" 2>/dev/null && [[ $wait_time -lt $MOUNT_TIMEOUT ]]; do
        sleep 1
        ((wait_time++))
    done

    # If still running after timeout, kill it
    if kill -0 "$mount_pid" 2>/dev/null; then
        kill -9 "$mount_pid" 2>/dev/null
        rm -f /tmp/.nk_mount_$$ 2>/dev/null
        log_message "⏱️ Mount timeout after ${MOUNT_TIMEOUT}s: $share (will retry next cycle)"
        return 3
    fi

    # Wait for process to fully terminate
    wait "$mount_pid" 2>/dev/null

    # Check result
    if [[ -f /tmp/.nk_mount_$$ ]]; then
        mount_output=$(cat /tmp/.nk_mount_$$ 2>/dev/null)
        rm -f /tmp/.nk_mount_$$ 2>/dev/null

        if [[ "$mount_output" == "success" ]]; then
            mount_status=0
        else
            mount_status=1
        fi
    else
        mount_status=1
    fi

    if [[ $mount_status -eq 0 ]]; then
        log_message "✅ Successfully connected: $share"
        return 0
    fi

    # --- Auth error detection based on response time ---
    # A real auth error returns FAST (server reachable, credentials rejected immediately).
    # After VPN reconnect, the first mount attempt is slow and macOS often returns
    # auth-like error messages even though the password is correct.
    # Therefore: only classify as auth error if the server responded quickly.
    local has_auth_keywords=false
    if [[ "$mount_output" =~ ([Aa]uthentication|[Uu]ser.name|[Pp]assword|[Cc]redential|-2096|access.denied|[Nn]ot.authoriz) ]]; then
        has_auth_keywords=true
    fi

    if [[ "$has_auth_keywords" == "true" ]]; then
        if [[ $wait_time -lt $AUTH_ERROR_FAST_THRESHOLD ]]; then
            # Fast failure with auth keywords = genuine authentication error
            log_message "🔑 Authentication error connecting (responded in ${wait_time}s): $share"
            return 2
        else
            # Slow failure with auth keywords = likely slow reconnect, NOT wrong password
            log_message "⏱️ Slow response (${wait_time}s) with auth-like error - treating as slow connection, not wrong password: $share"
            return 3
        fi
    fi

    log_message "❌ Error connecting: $share"
    return 1
}

keep_alive_ping() {
    local mount_point="$1"
    
    # Small activity to keep connection alive
    if [[ -d "$mount_point" ]]; then
        ls "$mount_point" >/dev/null 2>&1
        touch "$mount_point/.network_keeper_keepalive" 2>/dev/null
        rm "$mount_point/.network_keeper_keepalive" 2>/dev/null
    fi
}

show_usage() {
    cat << EOF
Network Drive Keeper - Maintains connections to network drives

Usage: nk [OPTIONS]

OPTIONS:
    start             Starts the service
    stop              Stops the service
    restart           Restarts the service
    status            Shows the status
    resume            Resumes auth retries after a password change
    test              Tests the configuration
    add <share>       Adds a network drive
    remove <share>    Removes a network drive
    list              Shows configured drives

EXAMPLES:
    nk add "smb://server.local/documents"
    nk status
    nk restart
    tail -f ~/.network_keeper.log

EOF
}

add_network_share() {
    local new_share="$1"
    [[ -z "$new_share" ]] && echo "❌ Error: No network share specified" && return 1
    
    # Create configuration file with proper header if it doesn't exist
    if [[ ! -f "$HOME/.network_keeper_config" ]]; then
        {
            echo "# Network Keeper Configuration"
            echo "# Add your network drives here"
            echo ""
            echo "# Network shares"
            echo "NETWORK_SHARES=("
            echo "    \"$new_share\""
            echo ")"
        } > "$HOME/.network_keeper_config"
    else
        # Append to existing configuration file
        echo "NETWORK_SHARES+=(\"$new_share\")" >> "$HOME/.network_keeper_config"
    fi
    
    log_message "Network share added: $new_share"
}

# Function to remove a network share from configuration
remove_network_share() {
    local share_to_remove="$1"
    
    if [[ -z "$share_to_remove" ]]; then
        echo "❌ Error: No share specified"
        echo "Usage: $0 remove <share>"
        return 1
    fi
    
    if [[ ! -f "$HOME/.network_keeper_config" ]]; then
        echo "❌ Error: Configuration file not found"
        return 1
    fi
    
    # Load current configuration
    load_config
    
    # Check if share exists
    local found=false
    local index=-1
    for i in {1..${#NETWORK_SHARES[@]}}; do
        if [[ "${NETWORK_SHARES[$i]}" == "$share_to_remove" ]]; then
            found=true
            index=$i
            break
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        echo "❌ Error: Share '$share_to_remove' not found in configuration"
        echo ""
        echo "Current shares:"
        for share in "${NETWORK_SHARES[@]}"; do
            echo "  - $share"
        done
        return 1
    fi
    
    # Create backup of configuration
    cp "$HOME/.network_keeper_config" "$HOME/.network_keeper_config.bak.$(date +%Y%m%d_%H%M%S)"
    
    # Remove the share from the arrays
    local temp_file=$(mktemp)
    
    # Read the config file and rebuild it without the specified share
    {
        echo "# Network Keeper Configuration"
        echo "# Add your network drives here"
        echo ""
        echo "# Network shares"
        echo "NETWORK_SHARES=("
        for i in {1..${#NETWORK_SHARES[@]}}; do
            if [[ $i -ne $index ]]; then
                echo "    \"${NETWORK_SHARES[$i]}\""
            fi
        done
        echo ")"
        echo ""
        
        # Other configuration settings can be added here if needed in the future
    } > "$temp_file"
    
    # Replace the configuration file
    mv "$temp_file" "$HOME/.network_keeper_config"
    
    echo "✅ Successfully removed: $share_to_remove"
    echo "💾 Backup created: ~/.network_keeper_config.bak.$(date +%Y%m%d_%H%M%S)"
    echo ""
    echo "Remaining shares:"
    load_config
    if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for share in "${NETWORK_SHARES[@]}"; do
            echo "  - $share"
        done
    fi
}

load_config() {
    # Reset array to avoid duplicates
    NETWORK_SHARES=()
    
    # Load additional configuration if available
    if [[ -f "$HOME/.network_keeper_config" ]]; then
        source "$HOME/.network_keeper_config"
    fi
}

main_loop() {
    # Clear auth pause from previous run on fresh start
    if is_auth_paused; then
        rm -f "$AUTH_PAUSED_FILE"
        log_message "🔓 Auth pause cleared on service restart"
    fi

    log_message "Network Keeper started in continuous mode (PID: $$)"

    local auth_failure_count=0

    while true; do
        load_config
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            sleep $CHECK_INTERVAL_SLOW
            continue
        fi

        # If auth is paused, skip all mount attempts
        if is_auth_paused; then
            sleep $CHECK_INTERVAL_SLOW
            continue
        fi

        local all_mounted=true

        # Check all shares
        for share in "${NETWORK_SHARES[@]}"; do
            if check_mount "$share"; then
                # Mounted - quick keepalive, reset auth failure counter on success
                keep_alive_ping "$(get_mount_point "$share")" 2>/dev/null
                auth_failure_count=0
            else
                # Not mounted - try to reconnect
                all_mounted=false
                mount_share "$share" 2>/dev/null
                local mount_result=$?
                if [[ $mount_result -eq 0 ]]; then
                    all_mounted=true
                    auth_failure_count=0
                elif [[ $mount_result -eq 2 ]]; then
                    # Authentication error - count towards pause threshold
                    (( auth_failure_count++ ))
                    log_message "⚠️ Auth failure $auth_failure_count/$MAX_AUTH_FAILURES for: $share"
                    if [[ $auth_failure_count -ge $MAX_AUTH_FAILURES ]]; then
                        pause_auth_retries "$share"
                        break
                    fi
                elif [[ $mount_result -eq 3 ]]; then
                    # Timeout or slow connection - do NOT count as auth failure
                    :
                fi
            fi
        done

        # Adaptive sleep: fast when all mounted, slow when disconnected
        if [[ "$all_mounted" == "true" ]]; then
            sleep $CHECK_INTERVAL_FAST
        else
            sleep $CHECK_INTERVAL_SLOW
        fi
    done
}

# Main program
case "${1:-}" in
    start)
        # Check if launchd service is running first
        if [[ -f "$PLIST_PATH" ]] && ! is_service_running; then
            echo "📡 Starting Network Keeper service..."
            launchctl load "$PLIST_PATH"
            if is_service_running; then
                echo "✅ Service started - continuous monitoring active"
                exit 0
            else
                echo "❌ Failed to start service"
                exit 1
            fi
        fi
        
        load_config
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            echo "⚠️ No network drives configured!"
            echo "Use 'nk add <share>' to add drives."
            exit 0
        fi
        
        # Run continuous monitoring loop (launchd keeps us alive)
        main_loop
        ;;
        
    stop)
        if [[ -f "$PLIST_PATH" ]] && is_service_running; then
            echo "🛑 Stopping Network Keeper service..."
            launchctl unload "$PLIST_PATH" 2>/dev/null
            echo "✅ Service stopped"
            exit 0
        else
            echo "ℹ️ Service is not running"
            exit 0
        fi
        ;;
        
    status)
        # Check if service is installed first
        if [[ ! -f "$PLIST_PATH" ]]; then
            echo "❌ Network Keeper service is not installed"
            echo "   Run './install.sh' to install the service"
        else
            # Check for auth pause state
            if is_auth_paused; then
                echo "🔒 Auth retries are PAUSED due to repeated login failures"
                echo "   Paused since: $(cat "$AUTH_PAUSED_FILE")"
                echo "   → Update your Keychain password, then run: nk resume"
                echo ""
            fi

            # Service is installed, check if it's running
            if is_service_running; then
                service_status=$(launchctl list | grep "$SERVICE_NAME" | awk '{print $1}')
                echo "✅ Network Keeper service is active"
                echo "   Last execution status: $service_status"
                echo "   Monitoring: continuous with adaptive intervals"
                echo "   - Fast check: ${CHECK_INTERVAL_FAST}s (when mounted)"
                echo "   - Slow check: ${CHECK_INTERVAL_SLOW}s (when disconnected)"
                
                # Show recent log entries
                echo ""
                echo "Recent activity:"
                if [[ -f "$HOME/.network_keeper.log" ]]; then
                    tail -3 "$HOME/.network_keeper.log" | sed 's/^/   /'
                else
                    echo "   No log file found"
                fi
            else
                echo "⚠️ Network Keeper service is installed but not running"
                echo "   Use 'nk start' to start it"
            fi
            
            echo ""
            echo "Monitored drives:"
            load_config
            if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
                echo "   (none configured)"
            else
                for share in "${NETWORK_SHARES[@]}"; do
                    echo "   - $share"
                done
            fi
        fi
        ;;
        
    test)
        load_config
        echo "Testing configuration..."
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            echo "❌ No network shares configured"
            echo "Use '$0 add <share>' to add shares"
            exit 1
        fi
        
        for share in "${NETWORK_SHARES[@]}"; do
            echo "Testing: $share"
            
            if check_mount "$share"; then
                echo "✅ Already connected at: $(get_mount_point "$share")"
                if ls "$(get_mount_point "$share")" >/dev/null 2>&1; then
                    echo "✅ Read access confirmed"
                else
                    echo "⚠️ Mount exists but read access failed"
                fi
            else
                echo "❌ Not mounted"
                if is_share_available "$share"; then
                    echo "✅ Share is available"
                    echo "   Attempting test connection..."
                    if mount_share "$share"; then
                        echo "✅ Test connection successful"
                    else
                        echo "❌ Test connection failed"
                    fi
                else
                    echo "❌ Share is not available"
                fi
            fi
            echo ""
        done
        ;;
        
    add)
        add_network_share "$2"
        ;;
        
    remove)
        remove_network_share "$2"
        ;;
        
    list)
        load_config
        echo "Configured network drives:"
        for share in "${NETWORK_SHARES[@]}"; do
            echo "  - $share"
        done
        ;;
        
    resume)
        if is_auth_paused; then
            rm -f "$AUTH_PAUSED_FILE"
            log_message "🔓 Auth retries resumed manually"
            echo "✅ Auth retries resumed"
            echo "   Make sure the Keychain password is up to date before retrying"
        else
            echo "ℹ️ Auth retries are not paused"
        fi
        ;;

    restart)
        if ! is_service_running; then
            echo "ℹ️ Service is not running. Starting..."
            $0 start
            exit $?
        fi
        echo "🔄 Restarting Network Keeper..."
        # KeepAlive=true means launchd automatically restarts after stop
        launchctl stop "$SERVICE_NAME"
        # Wait for launchd to restart the process
        tries=0
        while [[ $tries -lt 10 ]]; do
            sleep 1
            ((tries++))
            if is_service_running; then
                new_pid=$(launchctl list | grep "$SERVICE_NAME" | awk '{print $1}')
                echo "✅ Service restarted (PID: $new_pid)"
                # Clear auth pause on restart so reconnection is attempted immediately
                if is_auth_paused; then
                    rm -f "$AUTH_PAUSED_FILE"
                    echo "🔓 Auth pause cleared"
                fi
                exit 0
            fi
        done
        echo "❌ Service did not restart within 10s"
        exit 1
        ;;
        

    *)
        show_usage
        ;;
esac
