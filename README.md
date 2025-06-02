# Network Drive Keeper für macOS

Ein automatisches Skript-System, das Verbindungen zu Netzlaufwerken auf macOS aufrechterhält und automatisch wiederherstellt, wenn sie getrennt werden.

## ✨ Features

- **Automatische Wiederverbindung**: Stellt getrennte Netzlaufwerke automatisch wieder her
- **Keep-Alive**: Sendet regelmäßige Aktivitätssignale um Verbindungen aufrecht zu erhalten
- **Launchd Integration**: Startet automatisch beim Login
- **Flexible Konfiguration**: Unterstützt SMB, AFP und andere Protokolle
- **Logging**: Detaillierte Protokollierung aller Aktivitäten
- **Automatische Keychain-Authentifizierung**: Verwendet macOS Keychain automatisch
- **Einfache Verwaltung**: Kommandozeilen-Interface für alle Operationen
- **Intelligente Mount-Punkte**: Automatische Ableitung der Mount-Punkte von Freigabe-Namen

## 🚀 Installation

1. **Ausführen des Installationsskripts:**

   ```bash
   ./install.sh
   ```

2. **Konfiguration anpassen:**

   ```bash
   vim ~/.network_keeper_config
   ```

## 📖 Verwendung

### Grundlegende Befehle

```bash
# Service starten
./network_keeper.sh start

# Service stoppen
./network_keeper.sh stop

# Status prüfen
./network_keeper.sh status

# Netzlaufwerk hinzufügen
./network_keeper.sh add "smb://server.local/documents"

# Netzlaufwerk entfernen
./network_keeper.sh remove "smb://server.local/documents"

# Konfiguration testen
./network_keeper.sh test

# Logs anzeigen
./network_keeper.sh logs

# Alle konfigurierten Laufwerke anzeigen
./network_keeper.sh list
```

### Mit Alias (nach Installation)

```bash
# Kurze Befehle mit dem 'nk' Alias
nk status
nk add "smb://192.168.1.100/share"
nk remove "smb://192.168.1.100/share"
nk logs
```

## ⚙️ Konfiguration

### Automatische Konfiguration

Das Skript erstellt automatisch eine Konfigurationsdatei unter `~/.network_keeper_config`. Die Konfiguration ist sehr einfach - Sie müssen nur Ihre Netzlaufwerke hinzufügen:

```bash
# Network Keeper Konfiguration
# Fügen Sie hier Ihre Netzlaufwerke hinzu

# Netzlaufwerke
NETWORK_SHARES=(
    "smb://server.local/documents"
    "smb://192.168.1.100/share"
    "afp://server.local/backup"
)
```

**Wichtige Hinweise:**

- **Mount-Punkte werden automatisch erstellt**: Der Mount-Punkt wird automatisch aus dem Freigabe-Namen abgeleitet (z.B. `smb://server/documents` → `/Volumes/documents`)
- **Keychain-Authentifizierung**: Anmeldedaten werden automatisch über macOS Keychain verwaltet - keine manuelle Passwort-Konfiguration erforderlich

### Beispiele für Mount-Punkte

Das Skript leitet automatisch Mount-Punkte aus den Freigabe-Namen ab:

```bash
# Beispiele für automatische Mount-Punkt-Zuordnung:
"smb://server.local/documents"    → "/Volumes/documents"
"smb://192.168.1.100/share"       → "/Volumes/share"  
"afp://server.local/backup"       → "/Volumes/backup"
"smb://fileserver/HR-Files"       → "/Volumes/HR-Files"
```

**Fallback-Unterstützung:**

Falls `/Volumes/` nicht verfügbar ist, verwendet das Skript automatisch `~/NetworkDrives/` als Fallback-Verzeichnis.

### Unterstützte Protokolle

- **SMB/CIFS**: `smb://server/share`
- **AFP**: `afp://server/share`
- **NFS**: `nfs://server/path`
- **FTP**: `ftp://server/path`

### Netzlaufwerke verwalten

```bash
# Netzlaufwerk hinzufügen
./network_keeper.sh add "smb://server.local/share"

# Netzlaufwerk entfernen
./network_keeper.sh remove "smb://server.local/share"

# Alle konfigurierten Laufwerke auflisten
./network_keeper.sh list

# Mit Alias:
nk add "smb://192.168.1.100/documents"
nk remove "smb://192.168.1.100/documents"
nk list
```

**Hinweise:**

- Beim Entfernen wird automatisch ein Backup der Konfiguration erstellt
- Die `remove` Funktion zeigt eine Liste verfügbarer Shares, falls der angegebene Share nicht gefunden wird
- Entfernte Shares werden sofort aus der aktiven Überwachung genommen
- Mount-Punkte werden automatisch aus den Freigabe-Namen abgeleitet

## 🔧 Erweiterte Einstellungen

### Skript-Parameter anpassen

Bearbeiten Sie `network_keeper.sh` um folgende Einstellungen zu ändern:

```bash
CHECK_INTERVAL=30        # Überprüfungsintervall in Sekunden
MAX_LOG_SIZE=1048576    # Maximale Log-Dateigröße (1MB)
```

**Hinweise:**

- Mount-Punkte werden automatisch aus Freigabe-Namen erstellt und sind nicht konfigurierbar
- Fallback-Verzeichnis `~/NetworkDrives/` wird automatisch verwendet wenn `/Volumes/` nicht verfügbar ist

- Log-Dateien werden automatisch in `$HOME/.network_keeper.log` erstellt und sind nicht konfigurierbar
- PID-Datei wird automatisch in `$HOME/.network_keeper.pid` erstellt und ist nicht konfigurierbar

### Automatischer Start

Das Installationsskript registriert automatisch einen launchd Service, der beim Login startet. Die Konfiguration finden Sie in:

- Service: `~/Library/LaunchAgents/com.user.networkkeeper.plist`
- Logs: `~/.network_keeper_out.log` und `~/.network_keeper_err.log`

## 🔍 Problembehandlung

### Service-Status prüfen

```bash
# Launchd Service Status
launchctl list | grep networkkeeper

# Logs anzeigen
nk logs
cat ~/.network_keeper_out.log
cat ~/.network_keeper_err.log
```

### Häufige Probleme

1. **Verbindung schlägt fehl:**
   - Prüfen Sie Netzwerkkonnektivität
   - Stellen Sie sicher, dass Anmeldedaten in macOS Keychain gespeichert sind
   - Testen Sie manuelle Verbindung im Finder (damit werden Keychain-Einträge erstellt)

2. **Service startet nicht:**
   - Überprüfen Sie Dateiberechtigungen: `chmod +x network_keeper.sh`
   - Prüfen Sie Pfade in der plist-Datei

3. **Mount-Punkt bereits verwendet:**
   - Das Skript verwendet automatisch Fallback-Verzeichnisse
   - Entfernen Sie alte Mount-Punkte: `diskutil unmount /Volumes/Name`

4. **Keychain-Probleme:**
   - Verbinden Sie sich einmal manuell über Finder um Keychain-Einträge zu erstellen
   - Prüfen Sie Keychain-Zugriff in den Systemeinstellungen

### Debug-Modus

Für detaillierte Fehleranalyse können Sie das Skript manuell ausführen:

```bash
# Direkte Ausführung mit Debug-Output
zsh -x ./network_keeper.sh start
```

## 🛡️ Sicherheit

- **Automatische Keychain-Nutzung**: Das Skript verwendet automatisch macOS Keychain für alle Authentifizierungen
- **Keine Klartext-Passwörter**: Anmeldedaten werden nie im Skript oder in Konfigurationsdateien gespeichert
- **Berechtigungen**: Das Skript läuft nur mit Benutzerberechtigung
- **Sichere Logs**: Enthalten keine Passwörter oder sensible Daten

### Keychain-Integration

Das Skript nutzt `osascript` für das Mounten von Netzlaufwerken, was automatisch die in macOS Keychain gespeicherten Anmeldedaten verwendet. Sie müssen nur einmal bei der ersten Verbindung zu einem Server Ihre Anmeldedaten eingeben - diese werden dann sicher in der Keychain gespeichert.

**Vorteile der automatischen Keychain-Nutzung:**

- Keine manuelle Passwort-Konfiguration erforderlich
- Sichere Verschlüsselung durch macOS Keychain
- Nahtlose Integration mit macOS-Sicherheitsrichtlinien
- Automatische Aktualisierung bei Passwort-Änderungen über Keychain

## 📁 Dateistruktur

```text
/Users/Peters/repos/networkkeeper/
├── network_keeper.sh              # Hauptskript
├── install.sh                     # Installationsskript
├── uninstall.sh                   # Deinstallationsskript
├── com.user.networkkeeper.plist   # launchd Service-Konfiguration
└── README.md                      # Diese Dokumentation

~/.network_keeper_config            # Benutzerkonfiguration
~/.network_keeper.log               # Aktivitätsprotokoll (feste Lokation)
~/.network_keeper.pid               # Prozess-ID Datei (feste Lokation)
~/.network_keeper_out.log           # Standard-Output Logs
~/.network_keeper_err.log           # Fehler-Logs
```

## 🔄 Deinstallation

### Automatische Deinstallation (Empfohlen)

```bash
# Vollständige automatische Deinstallation
./uninstall.sh
```

Das Deinstallationsskript:

- Stoppt alle laufenden Network Keeper Prozesse
- Entfernt den launchd Service
- Bereinigt Konfiguration und Log-Dateien (mit Bestätigung)
- Entfernt Shell-Aliases
- Führt Verifikation durch

### Manuelle Deinstallation

Falls Sie die Deinstallation manuell durchführen möchten:

```bash
# Service stoppen und entfernen
launchctl unload ~/Library/LaunchAgents/com.user.networkkeeper.plist
rm ~/Library/LaunchAgents/com.user.networkkeeper.plist

# Konfigurationsdateien entfernen (optional)
rm ~/.network_keeper_config
rm ~/.network_keeper.log
rm ~/.network_keeper.pid
rm ~/.network_keeper_out.log
rm ~/.network_keeper_err.log

# Alias aus ~/.zshrc entfernen (manuell)
```

## 📝 Lizenz

Dieses Skript steht zur freien Verfügung.

## 🤝 Support

Bei Problemen prüfen Sie:

1. Die Log-Dateien (`nk logs`)
2. Die Netzwerkkonnektivität
3. Die Konfiguration (`~/.network_keeper_config`)

Für erweiterte Unterstützung kontaktieren Sie Ihren Systemadministrator.
