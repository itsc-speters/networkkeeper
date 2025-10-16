#!/bin/zsh

# Network Keeper - Installation Script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NETWORK_KEEPER_SCRIPT="$SCRIPT_DIR/network_keeper.sh"
LAUNCHD_PLIST="$SCRIPT_DIR/com.user.networkkeeper.plist"
USER_LAUNCHD_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$USER_LAUNCHD_DIR/com.user.networkkeeper.plist"

echo "🚀 Network Keeper Installation"
echo "==============================="
echo ""

# Make script executable
chmod +x "$NETWORK_KEEPER_SCRIPT"

# Create LaunchAgents directory
mkdir -p "$USER_LAUNCHD_DIR"

# Install plist with correct paths
sed -e "s|{{NETWORK_KEEPER_SCRIPT_PATH}}|$NETWORK_KEEPER_SCRIPT|g" \
    -e "s|{{USER_HOME}}|$HOME|g" \
    -e "s|{{USERNAME}}|$(whoami)|g" \
    "$LAUNCHD_PLIST" > "$INSTALLED_PLIST"

# Create default configuration if needed
if [[ ! -f "$HOME/.network_keeper_config" ]]; then
    cat > "$HOME/.network_keeper_config" << 'EOF'
# Network Keeper Configuration

# Example (remove # to activate):
# NETWORK_SHARES=(
#     "smb://server.local/share"
# )
EOF
    echo "✅ Configuration created: ~/.network_keeper_config"
else
    echo "✅ Configuration exists: ~/.network_keeper_config"
fi

# Register service
if launchctl list | grep -q "com.user.networkkeeper"; then
    launchctl unload "$INSTALLED_PLIST" 2>/dev/null
fi

launchctl load "$INSTALLED_PLIST"

if launchctl list | grep -q "com.user.networkkeeper"; then
    echo "✅ Service registered"
else
    echo "❌ Service registration failed"
    exit 1
fi

# Add shell alias
if [[ -f "$HOME/.zshrc" ]] && ! grep -q "alias nk=" "$HOME/.zshrc"; then
    {
        echo ""
        echo "# Network Keeper"
        echo "alias nk='$NETWORK_KEEPER_SCRIPT'"
    } >> "$HOME/.zshrc"
    echo "✅ Alias 'nk' added to ~/.zshrc"
fi

echo ""
echo "📝 Quick Start:"
echo "   nk add 'smb://server/share'   # Add a share"
echo "   nk status                      # Check status"
echo "   nk logs                        # View logs"
echo ""
echo "💡 Tip: Connect manually once in Finder to save credentials to Keychain"
echo ""
echo "🎉 Installation complete!"
