# Network Drive Keeper für macOS

Hält automatisch Verbindungen zu Netzlaufwerken aufrecht. Schnell, leicht, unsichtbar.

## ✨ Features

- ⚡ **Schnell** - Reconnect in ~5 Sekunden nach VPN-Verbindung
- 🪶 **Leicht** - ~0.1% CPU, adaptive Intervalle (5s/30s)
- 😌 **Entspannt** - Keine Error-Dialoge, kein Spam bei Offline
- 🔐 **Sicher** - Keychain-Integration, keine Passwörter im Script
- 🛡️ **AD-sicher** - Stoppt automatisch bei Passwort-Fehler, verhindert Account-Sperrung
- 🎯 **Einfach** - Einmal einrichten, läuft von selbst

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
nk restart                      # Neustart
nk resume                       # Nach Passwort-Wechsel: Retries wieder aktivieren
```

**Logs ansehen:**

```bash
tail -f ~/.network_keeper.log   # Live ansehen
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
tail -f ~/.network_keeper.log   # Live ansehen
tail -50 ~/.network_keeper.log  # Letzte 50 Zeilen
```

**Häufige Probleme:**

- **"Share not available"** → VPN getrennt oder Server offline
- **"Connection timeout"** → Server antwortet nicht, wird automatisch retried
- **Auth retries PAUSED** → AD-Passwort geändert, Keychain hat noch das alte Passwort

**Nach einem AD-Passwort-Wechsel:**

Nach einem Passwort-Wechsel im Active Directory hält der Service automatisch nach 2 fehlgeschlagenen Versuchen an, um eine Kontosperrung zu verhindern. Eine macOS-Benachrichtigung erscheint.

Ablauf:

1. Keychain-Eintrag aktualisieren: *Keychain-Zugriff* öffnen → alten Eintrag für den Server suchen → Passwort ändern
2. Retries wieder aktivieren:

```bash
nk status    # Zeigt an, ob und seit wann Retries pausiert sind
nk resume    # Aktiviert Retries wieder
```

**Service-Status:**

```bash
nk status                       # Zeigt alles Wichtige
```

## 🗑️ Deinstallation

```bash
./uninstall.sh
```

---

**Konfiguration:** `~/.network_keeper_config`  
**Log-Datei:** `~/.network_keeper.log` (auto-rotiert bei 1MB)  
**Service:** LaunchAgent (startet automatisch beim Login)
