#!/bin/zsh

# Network Keeper - Uninstallation Script

USER_LAUNCHD_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$USER_LAUNCHD_DIR/com.user.networkkeeper.plist"
CONFIG_FILE="$HOME/.network_keeper_config"
LOG_FILE="$HOME/.network_keeper.log"
PID_FILE="$HOME/.network_keeper.pid"

echo "🗑️  Network Keeper Uninstaller"
echo "==============================="
echo ""

# Confirmation
confirm() {
    echo -n "$1 (Y/n): "
    read -r response
    [[ -z "$response" ]] || [[ "$response" =~ ^[Yy] ]]
}

# Stop service and processes
echo "1. Stopping service..."
if [[ -f "$INSTALLED_PLIST" ]] && launchctl list | grep -q "com.user.networkkeeper"; then
    launchctl unload "$INSTALLED_PLIST" 2>/dev/null
fi

# Kill any running processes
pkill -f "network_keeper.sh" 2>/dev/null
sleep 1
pkill -9 -f "network_keeper.sh" 2>/dev/null

# Clean up PID file
rm -f "$PID_FILE" 2>/dev/null
echo "   ✅ Service stopped"

# Remove service file
echo ""
echo "2. Removing service..."
if [[ -f "$INSTALLED_PLIST" ]]; then
    rm -f "$INSTALLED_PLIST"
    echo "   ✅ Service file removed"
fi

# Remove configuration and logs
echo ""
echo "3. Removing files..."
if confirm "Remove configuration (~/.network_keeper_config)?"; then
    rm -f "$CONFIG_FILE"
    rm -f "$HOME"/.network_keeper_config.bak.* 2>/dev/null
    echo "   ✅ Configuration removed"
fi

if confirm "Remove logs (~/.network_keeper.log)?"; then
    rm -f "$LOG_FILE" "${LOG_FILE}.old"
    # Clean up old log files from previous versions
    rm -f "$HOME/.network_keeper_out.log" "$HOME/.network_keeper_err.log" 2>/dev/null
    echo "   ✅ Logs removed"
fi

# Remove shell alias
echo ""
echo "4. Removing alias..."
if [[ -f "$HOME/.zshrc" ]] && grep -q "alias nk=" "$HOME/.zshrc"; then
    if confirm "Remove 'nk' alias from ~/.zshrc?"; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
        sed -i '' '/# Network Keeper/d' "$HOME/.zshrc"
        sed -i '' '/alias nk=.*network_keeper/d' "$HOME/.zshrc"
        echo "   ✅ Alias removed"
        echo "   💾 Backup: ~/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
    fi
fi

# Verification
echo ""
echo "🔍 Verification:"
echo "================"

# Check processes
if pgrep -f "network_keeper" >/dev/null 2>&1; then
    echo "⚠️  Warning: Some processes still running"
    echo "   Run: pkill -9 -f 'network_keeper'"
else
    echo "✅ No processes running"
fi

# Check service
if launchctl list | grep -q "com.user.networkkeeper"; then
    echo "⚠️  Warning: Service still registered"
else
    echo "✅ Service unregistered"
fi

# Check files
remaining=()
[[ -f "$CONFIG_FILE" ]] && remaining+=("config")
[[ -f "$LOG_FILE" ]] && remaining+=("logs")

if [[ ${#remaining[@]} -gt 0 ]]; then
    echo "ℹ️  Remaining: ${remaining[*]}"
else
    echo "✅ All files removed"
fi

echo ""
echo "🎉 Uninstallation complete!"
