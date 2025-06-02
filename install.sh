#!/bin/zsh

# Installation and Setup Script for Network Keeper

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NETWORK_KEEPER_SCRIPT="$SCRIPT_DIR/network_keeper.sh"
LAUNCHD_PLIST="$SCRIPT_DIR/com.user.networkkeeper.plist"
USER_LAUNCHD_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$USER_LAUNCHD_DIR/com.user.networkkeeper.plist"

echo "🚀 Network Keeper Setup"
echo "======================"

# Make executable
chmod +x "$NETWORK_KEEPER_SCRIPT"

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$USER_LAUNCHD_DIR"

# Update plist file with correct paths and user information
sed -e "s|{{NETWORK_KEEPER_SCRIPT_PATH}}|$NETWORK_KEEPER_SCRIPT|g" \
    -e "s|{{USER_HOME}}|$HOME|g" \
    -e "s|{{USERNAME}}|$(whoami)|g" \
    "$LAUNCHD_PLIST" > "$INSTALLED_PLIST"

echo "✅ Files installed"

# Create example configuration
cat > "$HOME/.network_keeper_config" << 'EOF'
# Network Keeper Configuration
# Add your network drives here

# Mount points are automatically derived from share names
# Credentials are automatically handled via macOS Keychain

# Examples (remove the # to activate them):
# NETWORK_SHARES=(
#     "smb://server.local/documents"    # Will mount to /Volumes/documents
#     "smb://192.168.1.100/share"       # Will mount to /Volumes/share
#     "afp://server.local/backup"       # Will mount to /Volumes/backup
# )
EOF

echo "✅ Configuration file created: $HOME/.network_keeper_config"
echo ""
echo "⚠️ IMPORTANT: You must add at least one network drive before the service will work!"
echo "   Use: $NETWORK_KEEPER_SCRIPT add 'smb://your-server/share'"
echo ""
echo "💡 TIPS:"
echo "   - Mount points are automatically derived from share names"
echo "   - Credentials are handled automatically via macOS Keychain"
echo "   - Connect manually once via Finder to store credentials in Keychain"

# Register launchd service
if launchctl list | grep -q "com.user.networkkeeper"; then
    echo "⚠️ Service is already registered, reloading..."
    launchctl unload "$INSTALLED_PLIST" 2>/dev/null
fi

launchctl load "$INSTALLED_PLIST"

if launchctl list | grep -q "com.user.networkkeeper"; then
    echo "✅ Service successfully registered"
else
    echo "❌ Error registering service"
    exit 1
fi

echo ""
echo "📋 Next steps:"
echo "=============="
echo "1. Add your network drives:"
echo "   $NETWORK_KEEPER_SCRIPT add 'smb://your-server/share'"
echo ""
echo "2. Test the configuration:"
echo "   $NETWORK_KEEPER_SCRIPT test"
echo ""
echo "3. Check the status:"
echo "   $NETWORK_KEEPER_SCRIPT status"
echo ""
echo "4. View logs:"
echo "   $NETWORK_KEEPER_SCRIPT logs"
echo ""
echo "💡 Configuration is now automatic:"
echo "   - Mount points: Derived from share names (e.g., 'share' → '/Volumes/share')"
echo "   - Credentials: Via macOS Keychain (connect once manually in Finder)"
echo ""
echo "The service will start automatically on next login!"

# Create alias for easy usage
SHELL_RC="$HOME/.zshrc"
if [[ -f "$SHELL_RC" ]] && ! grep -q "network_keeper" "$SHELL_RC"; then
    {
        echo ""
        echo "# Network Keeper Alias"
        echo "alias nk='$NETWORK_KEEPER_SCRIPT'"
    } >> "$SHELL_RC"
    echo "✅ Alias 'nk' added to ~/.zshrc"
    echo "   Run 'source ~/.zshrc' or restart your terminal"
fi

echo ""
echo "🎉 Installation completed!"
