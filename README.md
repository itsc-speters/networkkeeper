# Network Drive Keeper für macOS

Hält automatisch Verbindungen zu Netzlaufwerken aufrecht und stellt sie bei Unterbrechung wieder her.

**Key Features:**

- Automatische Wiederverbindung
- Keine störenden Fehlerdialoge
- Startet automatisch beim Login
- Unterstützt SMB, AFP, NFS
- macOS Keychain Integration

## 🚀 Installation & Setup

```bash
# Installation
./install.sh

# Netzlaufwerk hinzufügen
nk add "smb://server.local/share"

# Service starten
nk start
```

## 📖 Verwendung

```bash
nk start                         # Service starten
nk stop                          # Service stoppen
nk status                        # Status prüfen
nk add "smb://server/share"      # Share hinzufügen
nk remove "smb://server/share"   # Share entfernen
nk list                          # Alle Shares anzeigen
nk logs                          # Logs anzeigen
nk test                          # Konfiguration testen
```

**Logs live ansehen:**

```bash
tail -f ~/.network_keeper.log
```

## ⚙️ Konfiguration

Shares werden über Befehle verwaltet oder direkt in `~/.network_keeper_config` eingetragen:

```bash
NETWORK_SHARES=(
    "smb://server.local/documents"
    "afp://192.168.1.100/share"
)
```

**Unterstützte Protokolle:** SMB, AFP, NFS

**Wichtig:**

- Anmeldedaten werden automatisch über macOS Keychain verwaltet
- Mount-Punkte werden automatisch erstellt (z.B. `smb://server/docs` → `/Volumes/docs`)
- Beim ersten Verbinden Anmeldedaten im Finder eingeben

## 🔧 Einstellungen

Bearbeiten Sie `network_keeper.sh` für erweiterte Konfiguration:

```bash
CHECK_INTERVAL=30        # Überprüfungsintervall (Sekunden)
MAX_LOG_SIZE=1048576    # Log-Rotation bei 1MB
```

**Log-Datei:**

- `~/.network_keeper.log` - Alle Aktivitäten und Ereignisse

## 🔍 Problembehandlung

**Verbindung schlägt fehl:**

1. Prüfen Sie die Logs: `nk logs` oder `tail -f ~/.network_keeper.log`
2. Testen Sie manuelle Verbindung im Finder
3. Überprüfen Sie Netzwerkkonnektivität: `ping <hostname>`
4. Stellen Sie sicher, dass Keychain-Einträge vorhanden sind

**Service läuft nicht:**

```bash
nk status                        # Status prüfen
launchctl list | grep network    # LaunchD Service prüfen
```

**Debug-Modus:**

```bash
zsh -x ./network_keeper.sh start  # Mit Debug-Output ausführen
```

## 🔄 Deinstallation

```bash
./uninstall.sh
```

Das Script stoppt den Service, entfernt alle Dateien und bereinigt die Konfiguration.
