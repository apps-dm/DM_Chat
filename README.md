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
| macOS – Apple Silicon | `DM.Chat-…-arm64.dmg` | Für Macs mit M1, M2, M3 oder neuer. |
| macOS – Intel | `DM.Chat-….dmg` | Für Macs mit Intel-Prozessor. |

Die macOS-Pakete sind mit einer Developer ID signiert und von Apple
notarisiert.

## Über dieses Repository

Dieses öffentliche Repository dient ausschließlich der automatisierten
Erstellung und Bereitstellung der offiziellen Desktop-Installer. Der
Anwendungsquellcode, die Server-Komponenten und die Web-App werden nicht nach
GitHub gespiegelt und verbleiben im privaten GitLab-Projekt.

Der Release-Prozess baut den Windows-Installer in GitHub Actions aus einem
explizit ausgewählten, read-only ausgecheckten GitLab-Release-Tag. Signierte
macOS-Pakete werden vom geschützten Release-Rechner hochgeladen. In GitHub
Releases werden ausschließlich fertige Installationsdateien veröffentlicht.

## Sicherheit

- Lade DM Chat nur aus den
  [offiziellen GitHub Releases](https://github.com/apps-dm/DM_Chat/releases).
- Installationsdateien werden niemals direkt in den Git-Branch eingecheckt.
- Zugangsdaten und Signing-Schlüssel sind nicht Teil dieses Repositorys.

Weitere Informationen zu DM Apps: [dm-apps.com](https://dm-apps.com)
