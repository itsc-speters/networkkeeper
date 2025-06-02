#!/bin/zsh

# Uninstall script for Network Keeper

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_LAUNCHD_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$USER_LAUNCHD_DIR/com.user.networkkeeper.plist"
CONFIG_FILE="$HOME/.network_keeper_config"
LOG_FILE="$HOME/.network_keeper.log"
PID_FILE="$HOME/.network_keeper.pid"
OUT_LOG="$HOME/.network_keeper_out.log"
ERR_LOG="$HOME/.network_keeper_err.log"

echo "🗑️  Network Keeper Uninstaller"
echo "==============================="

# Function to ask for confirmation
confirm() {
    local message="$1"
    echo -n "$message (y/N): "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Function to kill processes by pattern
kill_processes_by_pattern() {
    local pattern="$1"
    local description="$2"
    
    local pids=$(pgrep -f "$pattern" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        echo "   Found $description processes:"
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "     - PID: $pid"
            fi
        done
        
        # Try graceful termination first
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
            fi
        done
        
        sleep 2
        
        # Force kill any remaining
        local remaining=$(pgrep -f "$pattern" 2>/dev/null)
        if [[ -n "$remaining" ]]; then
            echo "     Force killing remaining $description processes..."
            for pid in $remaining; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null
                fi
            done
        fi
        
        return 0
    else
        return 1
    fi
}

# Stop the service if running
echo "1. Stopping all Network Keeper processes..."

# First, try the standard stop method
echo "   Attempting graceful shutdown..."
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "   Stopping main process (PID: $pid)..."
        kill "$pid" 2>/dev/null
        sleep 2
    fi
fi

# Kill all processes related to Network Keeper
echo "   Terminating all Network Keeper related processes..."

# Function to recursively kill process tree
kill_process_tree() {
    local pid="$1"
    local signal="$2"
    
    if [[ -z "$signal" ]]; then
        signal="TERM"
    fi
    
    # Find all children first
    local children=$(pgrep -P "$pid" 2>/dev/null)
    
    # Recursively kill children
    for child in $children; do
        kill_process_tree "$child" "$signal"
    done
    
    # Kill the parent process
    if kill -0 "$pid" 2>/dev/null; then
        kill -s "$signal" "$pid" 2>/dev/null
    fi
}

# First approach: Use pattern-based killing with process tree termination
echo "   Step 1: Pattern-based process termination..."

# Kill by script name and their entire process trees
pattern_pids=$(pgrep -f "network_keeper.sh" 2>/dev/null)
if [[ -n "$pattern_pids" ]]; then
    echo "     Found network_keeper.sh processes, terminating process trees..."
    for pid in $pattern_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "       - Terminating process tree for PID: $pid"
            kill_process_tree "$pid" "TERM"
        fi
    done
fi

# Kill by main_loop function
main_loop_pids=$(pgrep -f "main_loop" 2>/dev/null)
if [[ -n "$main_loop_pids" ]]; then
    echo "     Found main_loop processes, terminating..."
    for pid in $main_loop_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "       - Terminating PID: $pid"
            kill_process_tree "$pid" "TERM"
        fi
    done
fi

# Kill by configuration file usage
config_pids=$(pgrep -f "\.network_keeper" 2>/dev/null)
if [[ -n "$config_pids" ]]; then
    echo "     Found configuration-related processes, terminating..."
    for pid in $config_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "       - Terminating PID: $pid"
            kill_process_tree "$pid" "TERM"
        fi
    done
fi

# Wait for graceful termination
sleep 3

# Second approach: Force kill any remaining processes
echo "   Step 2: Force killing any remaining processes..."
final_patterns=("network_keeper" "\.network_keeper" "main_loop")
any_remaining=false

for pattern in "${final_patterns[@]}"; do
    remaining=$(pgrep -f "$pattern" 2>/dev/null)
    if [[ -n "$remaining" ]]; then
        any_remaining=true
        echo "     Force killing remaining processes matching '$pattern':"
        for pid in $remaining; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "       - Force killing process tree for PID: $pid"
                kill_process_tree "$pid" "KILL"
            fi
        done
    fi
done

# Third approach: Nuclear option - kill by process name patterns
echo "   Step 3: Final cleanup using pkill..."
for pattern in "network_keeper" "main_loop"; do
    if pkill -f "$pattern" 2>/dev/null; then
        echo "     ✅ Killed remaining processes matching '$pattern'"
    fi
done

# Wait a moment and force kill anything still remaining
sleep 1
for pattern in "network_keeper" "main_loop"; do
    if pkill -9 -f "$pattern" 2>/dev/null; then
        echo "     ✅ Force killed stubborn processes matching '$pattern'"
    fi
done

# Clean up any orphaned sleep processes that might have been spawned by Network Keeper
echo "   Step 4: Cleaning up potential orphaned processes..."
orphaned_sleep=$(ps aux | grep "sleep [0-9]" | grep -v grep | awk '{print $2}')
if [[ -n "$orphaned_sleep" ]]; then
    echo "     Found potential orphaned sleep processes, checking parent processes..."
    for sleep_pid in $orphaned_sleep; do
        # Check if the parent process no longer exists (indicating orphan)
        parent_pid=$(ps -o ppid= -p "$sleep_pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$parent_pid" ]] && [[ "$parent_pid" != "1" ]]; then
            # Check if parent is still a shell process in our terminal session
            parent_cmd=$(ps -o command= -p "$parent_pid" 2>/dev/null)
            if [[ "$parent_cmd" =~ "zsh" ]] && [[ "$parent_cmd" =~ "./network_keeper.sh" ]]; then
                echo "       - Killing orphaned sleep process: $sleep_pid (parent: $parent_pid)"
                kill -9 "$sleep_pid" 2>/dev/null
            fi
        fi
    done
fi

if [[ "$any_remaining" == "false" ]]; then
    echo "   ✅ All Network Keeper processes successfully terminated"
else
    echo "   ✅ Process termination completed"
fi

# Clean up PID file
if [[ -f "$PID_FILE" ]]; then
    rm -f "$PID_FILE" 2>/dev/null
    echo "   ✅ PID file removed"
fi

# Unload and remove launchd service
echo "2. Removing launchd service..."
if [[ -f "$INSTALLED_PLIST" ]]; then
    if launchctl list | grep -q "com.user.networkkeeper"; then
        echo "   Unloading service from launchd..."
        launchctl unload "$INSTALLED_PLIST" 2>/dev/null
    fi
    
    echo "   Removing plist file..."
    rm -f "$INSTALLED_PLIST"
    echo "   ✅ Service removed"
else
    echo "   ⚠️  No launchd service found"
fi

# Remove configuration and log files
echo "3. Removing configuration and log files..."

removed_files=()

# Handle configuration files
config_files=("$CONFIG_FILE" "$PID_FILE")
existing_config_files=()
for file in "${config_files[@]}"; do
    if [[ -f "$file" ]]; then
        existing_config_files+=("$file")
    fi
done

if [[ ${#existing_config_files[@]} -gt 0 ]]; then
    echo "   Found ${#existing_config_files[@]} configuration file(s):"
    for file in "${existing_config_files[@]}"; do
        echo "     - $(basename "$file")"
    done
    
    if confirm "   Remove configuration files?"; then
        for file in "${existing_config_files[@]}"; do
            rm -f "$file"
            removed_files+=("$file")
            echo "     ✅ Removed: $(basename "$file")"
        done
    else
        echo "     ⏭️  Configuration files skipped"
    fi
else
    echo "   ℹ️  No configuration files found"
fi

# Handle log files
log_files=("$LOG_FILE" "${LOG_FILE}.old" "$OUT_LOG" "$ERR_LOG")
existing_log_files=()
for file in "${log_files[@]}"; do
    if [[ -f "$file" ]]; then
        existing_log_files+=("$file")
    fi
done

if [[ ${#existing_log_files[@]} -gt 0 ]]; then
    echo "   Found ${#existing_log_files[@]} log file(s):"
    for file in "${existing_log_files[@]}"; do
        echo "     - $(basename "$file")"
    done
    
    if confirm "   Remove all log files?"; then
        for file in "${existing_log_files[@]}"; do
            rm -f "$file"
            removed_files+=("$file")
            echo "     ✅ Removed: $(basename "$file")"
        done
    else
        echo "     ⏭️  Log files skipped"
    fi
else
    echo "   ℹ️  No log files found"
fi

# Remove alias from shell configuration
echo "4. Removing shell alias..."
SHELL_RC="$HOME/.zshrc"
if [[ -f "$SHELL_RC" ]] && grep -q "network_keeper" "$SHELL_RC"; then
    if confirm "   Remove 'nk' alias from ~/.zshrc?"; then
        # Create backup
        cp "$SHELL_RC" "${SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)"
        
        # Remove network keeper related lines
        sed -i '' '/# Network Keeper Alias/d' "$SHELL_RC"
        sed -i '' '/alias nk=.*network_keeper/d' "$SHELL_RC"
        
        # Remove empty lines that might be left
        sed -i '' '/^$/N;/^\n$/d' "$SHELL_RC"
        
        echo "     ✅ Alias removed from ~/.zshrc"
        echo "     💾 Backup created: ~/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
    else
        echo "     ⏭️  Alias kept in ~/.zshrc"
    fi
else
    echo "     ⚠️  No alias found in ~/.zshrc"
fi

# Remove backup files
echo "5. Backup files cleanup..."

# Use a more robust method to find backup files
found_backups=()
if ls "$HOME"/.network_keeper_config.bak.* >/dev/null 2>&1; then
    for file in "$HOME"/.network_keeper_config.bak.*; do
        if [[ -f "$file" ]]; then
            found_backups+=("$file")
        fi
    done
fi

if [[ ${#found_backups[@]} -gt 0 ]]; then
    echo "   Found ${#found_backups[@]} backup file(s):"
    for backup in "${found_backups[@]}"; do
        echo "     - $(basename "$backup")"
    done
    
    if confirm "   Remove all backup files?"; then
        for backup in "${found_backups[@]}"; do
            rm -f "$backup"
            echo "     ✅ Removed: $(basename "$backup")"
        done
    else
        echo "     ⏭️  Backup files kept"
    fi
else
    echo "     ℹ️  No backup files found"
fi

# Verify uninstallation
echo ""
echo "🔍 Verification:"
echo "================"

# Check if service is still running
echo "Checking for remaining Network Keeper processes..."
check_patterns=("network_keeper" "\.network_keeper" "main_loop")
any_found=false

for pattern in "${check_patterns[@]}"; do
    remaining_processes=$(pgrep -f "$pattern" 2>/dev/null)
    if [[ -n "$remaining_processes" ]]; then
        if [[ "$any_found" == "false" ]]; then
            echo "❌ Warning: Network Keeper related processes still running:"
            any_found=true
        fi
        echo "   Pattern '$pattern':"
        for pid in $remaining_processes; do
            echo "     - PID: $pid"
            ps -p "$pid" -o pid,ppid,command 2>/dev/null | tail -n +2 | sed 's/^/       /'
        done
    fi
done

if [[ "$any_found" == "true" ]]; then
    echo ""
    echo "   To manually kill remaining processes, run one of:"
    echo "   pkill -f 'network_keeper'"
    echo "   pkill -9 -f 'network_keeper'  # (force kill)"
    echo "   pkill -f '\.network_keeper'"
else
    echo "✅ No Network Keeper related processes found"
fi

# Check if launchd service is removed
if launchctl list | grep -q "com.user.networkkeeper"; then
    echo "❌ Warning: LaunchD service still registered"
else
    echo "✅ LaunchD service removed"
fi

# Check remaining files
all_files_to_check=("$CONFIG_FILE" "$LOG_FILE" "${LOG_FILE}.old" "$PID_FILE" "$OUT_LOG" "$ERR_LOG")
remaining_files=()
for file in "${all_files_to_check[@]}"; do
    if [[ -f "$file" ]]; then
        remaining_files+=("$file")
    fi
done

# Check remaining backup files
remaining_backups=()
if ls "$HOME"/.network_keeper_config.bak.* >/dev/null 2>&1; then
    for file in "$HOME"/.network_keeper_config.bak.*; do
        if [[ -f "$file" ]]; then
            remaining_backups+=("$file")
        fi
    done
fi

if [[ ${#remaining_files[@]} -gt 0 ]]; then
    echo "⚠️  Remaining files:"
    for file in "${remaining_files[@]}"; do
        echo "   - $file"
    done
else
    echo "✅ All configuration and log files removed"
fi

if [[ ${#remaining_backups[@]} -gt 0 ]]; then
    echo "ℹ️  Remaining backup files (${#remaining_backups[@]}):"
    for backup in "${remaining_backups[@]}"; do
        echo "   - $(basename "$backup")"
    done
fi

echo ""
echo "📋 Uninstallation Summary:"
echo "=========================="
echo "✅ Service stopped and removed from launchd"
if [[ ${#removed_files[@]} -gt 0 ]]; then
    echo "✅ Removed ${#removed_files[@]} configuration/log files"
fi
echo "✅ Shell alias handling completed"
echo "✅ Backup files cleanup completed"

echo ""
echo "🎯 Manual cleanup (if needed):"
echo "==============================="
echo "• Remove any remaining mounted network drives manually"
echo "• Check ~/Library/LaunchAgents/ for any remaining plist files"
echo "• Review ~/.zshrc for any remaining aliases"
if [[ ${#remaining_files[@]} -gt 0 ]]; then
    echo "• Remove remaining files listed above if desired"
fi

echo ""
echo "🎉 Network Keeper uninstallation completed!"
echo ""
echo "Thank you for using Network Keeper! 👋"
