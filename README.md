# DM Chat Desktop

[![Neueste Version](https://img.shields.io/github/v/release/apps-dm/DM_Chat?display_name=tag&label=Version)](https://github.com/apps-dm/DM_Chat/releases/latest)
[![Desktop-Release](https://github.com/apps-dm/DM_Chat/actions/workflows/desktop-release.yml/badge.svg)](https://github.com/apps-dm/DM_Chat/actions/workflows/desktop-release.yml)

Die offizielle Desktop-App für **DM Chat** – schnell, fokussiert und als native
Installation für Windows und macOS verfügbar.

## Download

Alle aktuellen Installationsdateien findest du unter
**[Releases](https://github.com/apps-dm/DM_Chat/releases/latest)**.

| Plattform | Datei | Hinweis |
|---|---|---|
| Windows (x64) | `DM-Chat-…-Windows-x64.exe` | Beim ersten Start kann Windows SmartScreen einen Hinweis anzeigen. |
| macOS – Apple Silicon | `DM-Chat-…-macOS-arm64.dmg` | Für Macs mit Apple-Chip. |
| macOS – Intel | `DM-Chat-…-macOS-x64.dmg` | Für Macs mit Intel-Prozessor. |

Die macOS-Pakete sind mit einer Developer ID signiert und von Apple
notarisiert.

## Automatische Updates

DM Chat prüft beim Start und anschließend alle 60 Minuten auf neue
Desktop-Versionen. Wenn ein Update verfügbar ist, entscheidest du zuerst über
den Download und nach dem Download noch einmal, ob die App sofort neu gestartet
und aktualisiert werden soll.

Die zusätzlichen YAML-, ZIP- und Blockmap-Dateien eines Releases sind signierte
beziehungsweise prüfsummengeschützte Updateartefakte für die automatische
Aktualisierung. Für eine manuelle Installation brauchst du weiterhin nur die
passende `.exe`- oder `.dmg`-Datei.

## Über dieses Repository

Dieses öffentliche Repository dient ausschließlich der automatisierten
Erstellung und Bereitstellung der offiziellen Desktop-Installer. Der
Anwendungsquellcode, die Server-Komponenten und die Web-App werden nicht nach
GitHub gespiegelt und verbleiben im privaten GitLab-Projekt.

Der lokale Release-Prozess übergibt ausschließlich den benötigten
Desktop-Build-Kontext verschlüsselt an einen GitHub-hosted Windows-Runner. Das
verschlüsselte Paket liegt nur in einem nicht öffentlichen Draft-Release und
wird nach dem Build zusammen mit seinem kurzlebigen Schlüssel gelöscht.
Signierte macOS-Pakete werden vom geschützten Release-Rechner hochgeladen. Erst
danach wird das Release veröffentlicht – ausschließlich mit fertigen
Desktop-Installations- und Updateartefakten.

## Sicherheit

- Lade DM Chat nur aus den
  [offiziellen GitHub Releases](https://github.com/apps-dm/DM_Chat/releases).
- Installationsdateien werden niemals direkt in den Git-Branch eingecheckt.
- Zugangsdaten und Signing-Schlüssel sind nicht Teil dieses Repositorys.

Weitere Informationen zu DM Apps: [dm-apps.com](https://dm-apps.com)
