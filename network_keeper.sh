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
CHECK_INTERVAL=30        # Check every 30 seconds
MAX_LOG_SIZE=1048576    # 1MB
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.networkkeeper.plist"
SERVICE_NAME="com.user.networkkeeper"

# Note: Credentials are automatically handled via macOS Keychain

# Helper functions
is_service_running() {
    launchctl list | grep -q "$SERVICE_NAME"
}

# Check if network is available before attempting mount operations
is_network_available() {
    # Simple ping test to check network connectivity
    # Use a reliable DNS server (Google's) with a short timeout
    ping -c 1 -W 2000 8.8.8.8 >/dev/null 2>&1
    return $?
}

get_mount_point() {
    local share="$1"
    local share_name=$(basename "$share")
    echo "/Volumes/$share_name"
}

get_fallback_mount_point() {
    local mount_point="$1"
    echo "$HOME/NetworkDrives/$(basename "$mount_point")"
}

# Functions
log_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file_path="$HOME/.network_keeper.log"
    
    # Ensure log directory exists (should always be $HOME)
    if [[ ! -d "$HOME" ]]; then
        echo "Error: Home directory does not exist!"
        return 1
    fi
    
    echo "[$timestamp] $message" | tee -a "$log_file_path"
    
    # Rotate log file if too large
    if [[ -f "$log_file_path" ]] && [[ $(stat -f%z "$log_file_path" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
        mv "$log_file_path" "${log_file_path}.old"
        touch "$log_file_path"
    fi
}

check_mount() {
    local share="$1"
    local mount_point="$2"
    
    # Check if mount point exists and is mounted
    if mount | grep -q "$mount_point"; then
        return 0  # Is mounted
    else
        # Also check fallback location if the original was in /Volumes/
        if [[ "$mount_point" == /Volumes/* ]]; then
            local fallback_point=$(get_fallback_mount_point "$mount_point")
            if mount | grep -q "$fallback_point"; then
                return 0  # Is mounted at fallback location
            fi
        fi
        return 1  # Is not mounted
    fi
}

mount_share() {
    local share="$1"
    local mount_point="$2"
    
    # Check if network is available before attempting to mount
    if ! is_network_available; then
        log_message "⚠️ Network not available - skipping mount attempt for $share"
        return 1
    fi
    
    log_message "Attempting to connect to $share..."
    
    # Create mount point if it doesn't exist
    if [[ ! -d "$mount_point" ]]; then
        if ! mkdir -p "$mount_point" 2>/dev/null; then
            # If we can't create the mount point in /Volumes/, try a fallback location
            if [[ "$mount_point" == /Volumes/* ]]; then
                local fallback_point=$(get_fallback_mount_point "$mount_point")
                mount_point="$fallback_point"
                mkdir -p "$mount_point" 2>/dev/null
            else
                log_message "❌ Cannot create mount point: $mount_point"
                return 1
            fi
        fi
    fi
    
    # Use osascript to mount volume - this always uses Keychain authentication
    local mount_error=""
    
    # Execute mount command using osascript and capture error
    if mount_error=$(osascript -e "mount volume \"$share\"" 2>&1); then
        log_message "✅ Successfully connected: $share (mounted via Keychain)"
        
        # Find where macOS actually mounted the share
        local actual_mount_point=""
        local expected_mount_point=$(get_mount_point "$share")
        
        # Check common mount locations
        if [[ -d "$expected_mount_point" ]]; then
            actual_mount_point="$expected_mount_point"
        else
            # Try to find the mount point by checking recent mount entries
            actual_mount_point=$(mount | grep "$share" | awk '{print $3}' | head -1)
        fi
        
        if [[ -n "$actual_mount_point" && "$actual_mount_point" != "$mount_point" ]]; then
            log_message "   Mounted at: $actual_mount_point"
            # Create a symlink if the expected mount point is different
            if [[ ! -e "$mount_point" ]]; then
                ln -sf "$actual_mount_point" "$mount_point" 2>/dev/null && \
                log_message "   Created symlink: $mount_point -> $actual_mount_point"
            fi
        fi
        
        return 0
    else
        # Log the specific error for debugging
        log_message "❌ Error connecting: $share"
        log_message "   Error details: $mount_error"
        log_message "   Will retry next cycle"
        
        # Clean up failed mount point if we created it
        if [[ -d "$mount_point" ]] && [[ -z "$(ls -A "$mount_point" 2>/dev/null)" ]]; then
            rmdir "$mount_point" 2>/dev/null
        fi
        return 1
    fi
}

keep_alive_ping() {
    local mount_point="$1"
    
    # Small activity on the network drive to keep connection alive
    if [[ -d "$mount_point" ]]; then
        ls "$mount_point" >/dev/null 2>&1
        touch "$mount_point/.network_keeper_keepalive" 2>/dev/null
        rm "$mount_point/.network_keeper_keepalive" 2>/dev/null
    fi
}

cleanup() {
    log_message "Network Keeper is shutting down..."
    rm -f "$HOME/.network_keeper.pid"
    exit 0
}

show_usage() {
    local script_name="${0##*/}"
    [[ -z "$script_name" ]] && script_name="network_keeper.sh"
    cat << EOF
Network Drive Keeper - Maintains connections to network drives

Usage: $script_name [OPTIONS]

OPTIONS:
    start             Starts the service if needed, or runs one check cycle
    daemon            Starts the daemon in infinite loop mode
    stop              Stops the service and all processes
    restart           Restarts the launchd service
    status            Shows the status
    test              Tests the configuration
    add <share>       Adds a network drive
    remove <share>    Removes a network drive
    list              Shows configured drives
    logs              Shows recent log entries
    service <cmd>     Manages the launchd service (start|stop|restart|status)

EXAMPLES:
    $script_name daemon
    $script_name add "smb://server.local/documents"
    $script_name status
    $script_name stop
    $script_name restart
    $script_name service status

EOF
}

add_network_share() {
    local new_share="$1"
    if [[ -z "$new_share" ]]; then
        echo "Error: No network share specified"
        return 1
    fi
    
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
    log_message "Network Keeper cycle started (PID: $$)"
    
    # Do one cycle of checks
    load_config
    if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
        log_message "No network shares configured. Cycle complete."
        return 0
    fi
    
    # Iterate through all shares
    for share in "${NETWORK_SHARES[@]}"; do
        # Always derive mount point from share name
        mount_point=$(get_mount_point "$share")
        
        # Check connection and restore if necessary
        if ! check_mount "$share" "$mount_point"; then
            log_message "⚠️ Connection lost: $share"
            mount_share "$share" "$mount_point"
        else
            # Send keep-alive signal - check both original and fallback locations
            if [[ -d "$mount_point" ]] && mount | grep -q "$mount_point"; then
                keep_alive_ping "$mount_point"
            elif [[ "$mount_point" == /Volumes/* ]]; then
                local fallback_point=$(get_fallback_mount_point "$mount_point")
                if [[ -d "$fallback_point" ]] && mount | grep -q "$fallback_point"; then
                    keep_alive_ping "$fallback_point"
                fi
            fi
        fi
    done
    
    log_message "Network Keeper cycle completed"
}

# Main program
case "${1:-start}" in
    start)
        # Check if launchd service is running first
        if [[ -f "$PLIST_PATH" ]] && ! is_service_running; then
            echo "📡 Starting Network Keeper service..."
            launchctl load "$PLIST_PATH"
            if is_service_running; then
                echo "✅ Service started - monitoring will begin automatically"
                exit 0
            else
                echo "❌ Failed to start service"
                exit 1
            fi
        fi
        
        load_config
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            echo "⚠️ No network drives configured!"
            echo "Use '$0 add <share>' to add drives."
            echo "Starting anyway - will monitor for configuration changes..."
        fi
        
        if [[ -f "$HOME/.network_keeper.pid" ]] && kill -0 "$(cat "$HOME/.network_keeper.pid")" 2>/dev/null; then
            echo "Network Keeper is already running (PID: $(cat "$HOME/.network_keeper.pid"))"
            exit 1
        fi
        
        echo "Starting Network Keeper..."
        if [[ ${#NETWORK_SHARES[@]} -gt 0 ]]; then
            echo "Monitoring ${#NETWORK_SHARES[@]} network drive(s):"
            for share in "${NETWORK_SHARES[@]}"; do
                echo "  - $share"
            done
        else
            echo "No network drives configured - running cycle anyway..."
        fi
        
        # Run one cycle and exit (launchd will restart us)
        main_loop
        echo "Network Keeper cycle completed"
        ;;
        
    daemon)
        # This is the old infinite loop mode for manual usage
        load_config
        if [[ ${#NETWORK_SHARES[@]} -eq 0 ]]; then
            echo "⚠️ No network drives configured!"
            echo "Use '$0 add <share>' to add drives."
            echo "Starting anyway - will monitor for configuration changes..."
        fi
        
        if [[ -f "$HOME/.network_keeper.pid" ]] && kill -0 "$(cat "$HOME/.network_keeper.pid")" 2>/dev/null; then
            echo "Network Keeper is already running (PID: $(cat "$HOME/.network_keeper.pid"))"
            exit 1
        fi
        
        echo "Starting Network Keeper daemon..."
        if [[ ${#NETWORK_SHARES[@]} -gt 0 ]]; then
            echo "Monitoring ${#NETWORK_SHARES[@]} network drive(s):"
            for share in "${NETWORK_SHARES[@]}"; do
                echo "  - $share"
            done
        else
            echo "No network drives configured - waiting for configuration..."
        fi
        
        # Signal handler for clean shutdown
        trap cleanup SIGTERM SIGINT
        
        echo $$ > "$HOME/.network_keeper.pid"
        
        while true; do
            main_loop
            # Use shorter sleeps to avoid issues
            for ((i=0; i<CHECK_INTERVAL; i++)); do
                sleep 1
            done
        done
        ;;
        
    stop)
        stopped_any=false
        
        # First, unload the launchd service to prevent it from restarting processes
        if [[ -f "$PLIST_PATH" ]]; then
            if is_service_running; then
                echo "Unloading launchd service..."
                launchctl unload "$PLIST_PATH" 2>/dev/null
                sleep 1
                
                if is_service_running; then
                    echo "⚠️ Service still active, force unloading..."
                    launchctl remove "$SERVICE_NAME" 2>/dev/null
                fi
                stopped_any=true
                echo "✅ Service unloaded from launchd"
            else
                echo "ℹ️ Service not currently loaded in launchd"
            fi
        else
            echo "ℹ️ Service plist not found"
        fi
        
        # Then stop any currently running processes
        if [[ -f "$HOME/.network_keeper.pid" ]]; then
            pid=$(cat "$HOME/.network_keeper.pid")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                sleep 1
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Force killing PID: $pid"
                    kill -9 "$pid" 2>/dev/null
                fi
                echo "✅ Stopped process (PID: $pid)"
                stopped_any=true
            fi
            rm -f "$HOME/.network_keeper.pid"
        fi
        
        # Also check for and stop any other running Network Keeper processes
        other_pids=$(pgrep -f "network_keeper.sh.*start" 2>/dev/null)
        if [[ -n "$other_pids" ]]; then
            echo "Stopping additional Network Keeper processes..."
            for pid in $other_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    sleep 1
                    if kill -0 "$pid" 2>/dev/null; then
                        echo "  Force killing PID: $pid"
                        kill -9 "$pid" 2>/dev/null
                    else
                        echo "  Stopped PID: $pid"
                    fi
                    stopped_any=true
                fi
            done
        fi
        
        # Final verification and cleanup
        sleep 1
        remaining_pids=$(pgrep -f "network_keeper.sh.*start" 2>/dev/null)
        if [[ -n "$remaining_pids" ]]; then
            echo "Force killing remaining processes..."
            for pid in $remaining_pids; do
                kill -9 "$pid" 2>/dev/null
                echo "  Force killed PID: $pid"
            done
            stopped_any=true
        fi
        
        # Final status check
        if is_service_running; then
            echo "⚠️ Warning: Service may still be loaded in launchd"
        fi
        
        if [[ "$stopped_any" == "false" ]]; then
            echo "❌ Network Keeper was not running"
        else
            echo "✅ Network Keeper completely stopped"
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
                echo "   Service runs every $CHECK_INTERVAL seconds via launchd"
                
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
                echo "   Use './network_keeper.sh start' or './network_keeper.sh service start' to start it"
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
        
        local test_counter=1
        for share in "${NETWORK_SHARES[@]}"; do
            echo "Testing: $share"
            
            # Always derive mount point from share name
            mount_point=$(get_mount_point "$share")
            
            # Check if already mounted at the expected location
            actual_mount_point=""
            
            # First check original location
            if mount | grep -q "$mount_point"; then
                actual_mount_point="$mount_point"
            elif [[ "$mount_point" == /Volumes/* ]]; then
                # Check fallback location
                local fallback_point=$(get_fallback_mount_point "$mount_point")
                if mount | grep -q "$fallback_point"; then
                    actual_mount_point="$fallback_point"
                fi
            fi
            
            if [[ -n "$actual_mount_point" ]]; then
                echo "✅ Already connected at: $actual_mount_point"
                # Test read access
                if ls "$actual_mount_point" >/dev/null 2>&1; then
                    echo "✅ Read access confirmed"
                else
                    echo "⚠️ Mount exists but read access failed"
                fi
            else
                echo "❌ Not mounted at expected location: $mount_point"
                # Also check fallback location
                if [[ "$mount_point" == /Volumes/* ]]; then
                    local fallback_point=$(get_fallback_mount_point "$mount_point")
                    echo "❌ Not mounted at fallback location: $fallback_point"
                fi
                echo "   Attempting test connection..."
                # Try to mount to a temporary location for testing
                test_mount="/tmp/nk_test_$$_$test_counter"
                if mount_share "$share" "$test_mount"; then
                    echo "✅ Test connection successful"
                    sleep 1
                    umount "$test_mount" 2>/dev/null
                    rmdir "$test_mount" 2>/dev/null
                else
                    echo "❌ Test connection failed"
                fi
            fi
            echo ""
            ((test_counter++))
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
        echo "Restarting Network Keeper..."
        # Stop the service first
        echo "Stopping service..."
        $0 stop
        sleep 2
        
        # Start the service again
        echo "Starting service..."
        if [[ -f "$PLIST_PATH" ]]; then
            launchctl load "$PLIST_PATH"
            if is_service_running; then
                echo "✅ Network Keeper service restarted"
            else
                echo "❌ Failed to restart service"
                exit 1
            fi
        else
            echo "❌ Service not installed. Run './install.sh' first."
            exit 1
        fi
        ;;
        
    service)
        # Subcommand for service management
        subcommand="${2:-}"
        case "$subcommand" in
            start)
                if [[ -f "$PLIST_PATH" ]]; then
                    if is_service_running; then
                        echo "✅ Service is already running"
                    else
                        launchctl load "$PLIST_PATH"
                        if is_service_running; then
                            echo "✅ Service started"
                        else
                            echo "❌ Failed to start service"
                            exit 1
                        fi
                    fi
                else
                    echo "❌ Service not installed. Run './install.sh' first."
                    exit 1
                fi
                ;;
            stop)
                if is_service_running; then
                    launchctl unload "$PLIST_PATH" 2>/dev/null
                    if is_service_running; then
                        launchctl remove "$SERVICE_NAME" 2>/dev/null
                    fi
                    echo "✅ Service stopped"
                else
                    echo "ℹ️ Service is not running"
                fi
                ;;
            restart)
                $0 service stop
                sleep 1
                $0 service start
                ;;
            status)
                if is_service_running; then
                    echo "✅ Service is running"
                else
                    echo "❌ Service is stopped"
                fi
                ;;
            *)
                echo "Usage: $0 service {start|stop|restart|status}"
                echo ""
                echo "Service commands:"
                echo "  start    - Load the launchd service"
                echo "  stop     - Unload the launchd service"  
                echo "  restart  - Restart the launchd service"
                echo "  status   - Check if service is loaded"
                ;;
        esac
        ;;
        
    *)
        show_usage
        ;;
esac
