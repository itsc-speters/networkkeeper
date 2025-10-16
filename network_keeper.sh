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
MAX_LOG_SIZE=1048576     # 1MB
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.networkkeeper.plist"
SERVICE_NAME="com.user.networkkeeper"

# Note: Credentials are automatically handled via macOS Keychain

# Helper functions
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
    local max_wait=10
    
    # Wait up to 10 seconds for the mount to complete
    while kill -0 "$mount_pid" 2>/dev/null && [[ $wait_time -lt $max_wait ]]; do
        sleep 1
        ((wait_time++))
    done
    
    # If still running, kill it (mount is taking too long)
    if kill -0 "$mount_pid" 2>/dev/null; then
        kill -9 "$mount_pid" 2>/dev/null
        rm -f /tmp/.nk_mount_$$ 2>/dev/null
        log_message "❌ Connection timeout: $share (took too long to respond)"
        log_message "   Will retry next cycle"
        return 1
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
    else
        log_message "❌ Error connecting: $share"
        return 1
    fi
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
    test              Tests the configuration
    add <share>       Adds a network drive
    remove <share>    Removes a network drive
    list              Shows configured drives
    logs              Shows recent log entries

EXAMPLES:
    nk add "smb://server.local/documents"
    nk status
    nk restart
    nk logs

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
    log_message "Network Keeper started in continuous mode (PID: $$)"
    
    while true; do
        load_config
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            sleep $CHECK_INTERVAL_SLOW
            continue
        fi
        
        local all_mounted=true
        
        # Check all shares
        for share in "${NETWORK_SHARES[@]}"; do
            if check_mount "$share"; then
                # Mounted - quick keepalive
                keep_alive_ping "$(get_mount_point "$share")" 2>/dev/null
            else
                # Not mounted - try to reconnect
                all_mounted=false
                if mount_share "$share" 2>/dev/null; then
                    all_mounted=true
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
case "${1:-start}" in
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
        
    logs)
        local log_file_path="$HOME/.network_keeper.log"
        if [[ -f "$log_file_path" ]]; then
            tail -20 "$log_file_path"
        else
            echo "No log file found at: $log_file_path"
        fi
        ;;
        
    restart)
        echo "🔄 Restarting Network Keeper..."
        $0 stop
        sleep 1
        $0 start
        ;;
        

    *)
        show_usage
        ;;
esac
