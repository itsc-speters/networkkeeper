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
   2. **Netzlaufwerke hinzufügen:**

      ```bash
      # Einfach mit dem add-Befehl
      ./network_keeper.sh add "smb://192.168.1.100/share"
      ./network_keeper.sh add "smb://server.local/documents"

      # Oder mit Alias (nach Installation)
      nk add "smb://192.168.1.100/share"
      ```

      Alternativ können Sie die Konfiguration auch manuell bearbeiten:

      ```bash
      vim ~/.network_keeper_config
      ```

## 📖 Verwendung

### Grundlegende Befehle

```bash
# Service starten (startet den LaunchD Service falls nötig)
./network_keeper.sh start

# Service komplett stoppen (empfohlen)
./network_keeper.sh stop

# Service neustarten
./network_keeper.sh restart

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

### Service-Management

```bash
# LaunchD Service verwalten
./network_keeper.sh service start    # Service laden
./network_keeper.sh service stop     # Service entladen  
./network_keeper.sh service restart  # Service neustarten
./network_keeper.sh service status   # Service-Status prüfen
```

**Wichtiger Unterschied:**

- `./network_keeper.sh start` - Startet den LaunchD Service falls er nicht läuft, ansonsten führt einen Überwachungszyklus aus
- `./network_keeper.sh stop` - Stoppt Service UND alle laufenden Prozesse (empfohlen)
- `./network_keeper.sh service stop` - Stoppt nur den LaunchD Service

**Hinweis:** Der `start` Befehl erkennt automatisch, ob der LaunchD Service läuft und startet ihn bei Bedarf. Dies macht die Bedienung einfacher - Sie müssen sich keine Gedanken über den Service-Status machen.

### Mit Alias (nach Installation)

```bash
# Kurze Befehle mit dem 'nk' Alias
nk start
nk status
nk stop
nk restart  
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

### Log-System

Network Keeper verwendet drei verschiedene Log-Dateien für unterschiedliche Zwecke:

- **`~/.network_keeper.log`** - Hauptanwendungslog mit timestamped Meldungen der Skript-Logik
- **`~/.network_keeper_out.log`** - Standard-Output vom launchd Service (echo-Ausgaben, Status-Meldungen)
- **`~/.network_keeper_err.log`** - Fehler-Output vom launchd Service (Fehlermeldungen, Warnungen)
- **`~/.network_keeper.pid`** - Prozess-ID Datei (automatisch verwaltet)

### Automatischer Start

Das Installationsskript registriert automatisch einen launchd Service, der beim Login startet. Die Konfiguration finden Sie in:

- **Service**: `~/Library/LaunchAgents/com.user.networkkeeper.plist`
- **Logs**: Drei getrennte Log-Dateien für verschiedene Zwecke (siehe Log-System oben)

## 🔍 Problembehandlung

### Service-Status prüfen

```bash
# Launchd Service Status
launchctl list | grep networkkeeper

# Alle Logs anzeigen
nk logs                              # Zeigt das Hauptanwendungslog
cat ~/.network_keeper.log           # Hauptanwendungslog (Skript-Logik)
cat ~/.network_keeper_out.log       # Standard-Output vom Service
cat ~/.network_keeper_err.log       # Fehler-Output vom Service
```

### Häufige Probleme

**Verbindung schlägt fehl:**

- Prüfen Sie Netzwerkkonnektivität
- Stellen Sie sicher, dass Anmeldedaten in macOS Keychain gespeichert sind
- Testen Sie manuelle Verbindung im Finder (damit werden Keychain-Einträge erstellt)

### Log-Dateien verstehen

Network Keeper verwendet drei verschiedene Log-Dateien, die jeweils unterschiedliche Informationen enthalten:

#### 📋 `.network_keeper.log` (Hauptanwendungslog)

- **Zweck**: Detaillierte Anwendungslogik mit Zeitstempeln
- **Erstellt von**: `log_message()` Funktion im Skript
- **Enthält**:
  - Verbindungsversuche und -status
  - Mount/Unmount Aktivitäten
  - Fehlerdetails und Debug-Informationen
  - Zeitgestempelte Ereignisse
- **Beispiel**: `[2025-06-02 10:30:15] Attempting to connect to smb://server/share...`

#### 📤 `.network_keeper_out.log` (Standard-Output)

- **Zweck**: Standard-Ausgaben des launchd Services
- **Erstellt von**: macOS launchd (konfiguriert in plist)
- **Enthält**:
  - Echo-Ausgaben vom Skript
  - Status-Meldungen
  - Normale Programmausgaben
- **Beispiel**: `✅ Network Keeper cycle completed`

#### ❌ `.network_keeper_err.log` (Fehler-Output)

- **Zweck**: Fehlerausgaben des launchd Services
- **Erstellt von**: macOS launchd (konfiguriert in plist)
- **Enthält**:
  - Systemfehler
  - Skript-Fehler (stderr)
  - Kritische Probleme
- **Beispiel**: `/bin/zsh: command not found`

**💡 Debugging-Tipp**: Für eine vollständige Problemanalyse prüfen Sie alle drei Log-Dateien:

```bash
# Schneller Überblick über alle Logs
echo "=== Hauptlog ==="; tail -10 ~/.network_keeper.log
echo "=== Standard Output ==="; tail -10 ~/.network_keeper_out.log  
echo "=== Fehler ==="; tail -10 ~/.network_keeper_err.log
```

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
~/.network_keeper.log               # Hauptanwendungslog (Skript-Logik mit Zeitstempel)
~/.network_keeper_out.log           # Standard-Output vom launchd Service
~/.network_keeper_err.log           # Fehler-Output vom launchd Service
~/.network_keeper.pid               # Prozess-ID Datei (automatisch verwaltet)
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

1. Die Log-Dateien:
   - `nk logs` (Hauptanwendungslog)
   - `cat ~/.network_keeper_out.log` (Service-Output)
   - `cat ~/.network_keeper_err.log` (Fehler-Output)
2. Die Netzwerkkonnektivität
3. Die Konfiguration (`~/.network_keeper_config`)

Für erweiterte Unterstützung kontaktieren Sie Ihren Systemadministrator.
