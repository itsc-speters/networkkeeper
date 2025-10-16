# Network Drive Keeper für macOS

Hält automatisch Verbindungen zu Netzlaufwerken aufrecht. Schnell, leicht, unsichtbar.

## ✨ Features

- ⚡ **Schnell** - Reconnect in ~5 Sekunden nach VPN-Verbindung
- 🪶 **Leicht** - ~0.1% CPU, adaptive Intervalle (5s/30s)
- 😌 **Entspannt** - Keine Error-Dialoge, kein Spam bei Offline
- 🔐 **Sicher** - Keychain-Integration, keine Passwörter im Script
- 🎯 **Einfach** - 3 Befehle: add, start, done

**Unterstützt:** SMB, AFP, NFS

## 🚀 Quick Start

```bash
./install.sh
nk add "smb://server.local/share"
nk start
```

Fertig! 🎉

## 📖 Befehle

```bash
nk add "smb://server/share"     # Share hinzufügen
nk start                        # Service starten
nk status                       # Status anzeigen
nk logs                         # Letzte 20 Log-Einträge
nk restart                      # Neustart
```

**Alles andere:**

```bash
nk                              # Zeigt alle Befehle
```

## 💡 Wie es funktioniert

**Intelligentes Monitoring:**

- ✅ Gemountet → Check alle **5 Sekunden** (nur \`mount\` grep, fast & leicht)
- ❌ Offline → Check alle **30 Sekunden** (Port-Check, entspannt)
- 🔌 VPN reconnect → Automatischer Mount innerhalb 30s

**Keine Error-Dialoge:**

- AppleScript try/catch fängt alle macOS-Fehler ab
- Läuft still im Hintergrund

## 🔍 Troubleshooting

**Logs ansehen:**

```bash
nk logs                         # Letzte Einträge
tail -f ~/.network_keeper.log   # Live ansehen
```

**Häufige Probleme:**

- **"Share not available"** → VPN getrennt oder Server offline
- **"Connection timeout"** → Server antwortet nicht, wird automatisch retried

**Service-Status:**

```bash
nk status                       # Zeigt alles Wichtige
```

## 🗑️ Deinstallation

```bash
./uninstall.sh
```

---

**Konfiguration:** \`~/.network_keeper_config\`  
**Log-Datei:** \`~/.network_keeper.log\` (auto-rotiert bei 1MB)  
**Service:** LaunchAgent (startet automatisch beim Login)
