# DropStopNShop

**Datei in einen Ordner legen, schon ist sie auf dem Bildschirm im Laden.**

[🇬🇧 English version](README.md)

DropStopNShop macht aus einem Raspberry Pi und einem beliebigen Monitor eine Anzeige für
Preislisten, Angebote und Hinweise. Die Inhalte sind einfach Dateien in einem freigegebenen Ordner:
- **PDFs** aus LibreOffice, Canva, Word, PowerPoint, …
- **PowerPoint-Dateien** (`.pptx`, auch LibreOffice Impress `.odp`)
- **Bilder**
- **Videos**

Es gibt kein Redaktionssystem, keine Cloud, kein Abo und keine App, die man lernen muss. Wer ein
PDF speichern kann, kann die Anzeige bedienen.

Gedacht ist es für kleine Betriebe wie Läden, Cafés, Praxen oder Werkstätten: bedienbar für
Leute ohne Technikinteresse, gebaut für die nächsten 10 Jahre und sparsam im Stromverbrauch.

## Was es kann

- **Der Ordner ist die Abspielliste:** Dateien laufen in der Reihenfolge ihrer Namen (`01_…`,
  `02_…`). Wer eine Datei löscht, nimmt sie vom Bildschirm.
- **PDF-Seiten werden Folien:** Ein PDF mit 5 Seiten ergibt 5 Folien. PowerPoint-Dateien genauso.
- **Keine schwarzen Ränder:** Hat eine Folie nicht das Format des Bildschirms (ein A4-Blatt, ein
  Handyfoto), werden die Ränder mit den Farben an ihrem Rand aufgefüllt. Jede Datei wird nur
  einmal aufbereitet und wiederverwendet, bis sie sich ändert. Abschaltbar; Videos bleiben, wie
  sie sind.
- **Angebote laufen von selbst ab:** `bis 30.11.2026` oder `until 2026-11-30` in den Dateinamen
  schreiben.
- **Läuft auch offline:** Ein USB-Stick mit dem Ordner hat Vorrang (Messe, kein Netz). Ist der
  Netzwerkordner nicht erreichbar, laufen die letzten Inhalte weiter.
- **Für schaltbare Steckdosen gemacht:** Pi und Monitor dürfen jeden Abend hart abgeschaltet
  werden. Der Pi schreibt kaum etwas auf die SD-Karte, ein Stromausfall macht nichts kaputt.
- **Ein Skript:** `setup.sh` richtet alles auf einem frischen Raspberry Pi OS ein. Es zeigt vorher,
  was es ändert, richtet bei Bedarf das WLAN ein, findet den Ordner auf der FRITZ!Box selbst,
  und `--uninstall` macht alles rückgängig.
- **Deutsch oder Englisch** im Installer und in den Meldungen auf dem Bildschirm.

## Schnellstart

Du brauchst:
- einen Raspberry Pi 5 oder 4 mit Netzteil
- eine microSD-Karte
- einen Monitor
- optional einen Netzwerkordner (SMB), z. B. auf der FRITZ!Box, einem NAS oder einem Windows-PC

1. Mit dem [Raspberry Pi Imager](https://www.raspberrypi.com/software/) **Raspberry Pi OS Lite
   (64-bit)** auf die Karte schreiben. Benutzer und Passwort festlegen, SSH aktivieren.
2. Pi starten, per SSH verbinden und ausführen:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh | sudo bash
   ```
3. Die Fragen beantworten: Sprache, Ordnername, Netzwerkordner und Zugangsdaten. Dann neu starten.

**Zum ersten Mal oder unter Windows?** Dann der
[Schritt-für-Schritt-Anleitung](docs/einrichtung.md) folgen. Sie setzt nichts voraus.

**Für die Leute, die die Inhalte ändern:** die [Bedienungsanleitung](docs/bedienung.md).
Am besten ausdrucken und neben den Laden-PC hängen. Damit der Ordner am Laden-PC immer als
Laufwerk da ist: [Netzlaufwerk einbinden](docs/netzlaufwerk.md).

## So funktioniert es

- **Abgleich:** Ein systemd-Timer holt alle 3 Minuten die Dateien (USB-Stick vor
  Netzwerkordner). PowerPoint-Dateien wandelt LibreOffice in PDFs um, PDF-Seiten werden zu
  Bildern, und die Ränder werden auf das Format des Bildschirms aufgefüllt. Jede Datei wird nur
  einmal aufbereitet (`data/cache/`), danach geht es schnell. Geschrieben wird nur, wenn sich etwas
  geändert hat. Ein neuer Stand wird erst vollständig geschrieben und dann atomar umgeschaltet.
- **Anzeige:** Nach dem Einschalten startet der systemd-Dienst `dropstopnshop-kiosk`
  [cage](https://github.com/cage-kiosk/cage) mit Chromium im Kiosk-Modus auf `tty1`. Chromium
  zeigt eine statische HTML-Seite als Diashow. Bei einem Desktop-Image stellt das Setup den
  Start auf die Konsole um.
- **Alles in einem Ordner:** Das Setup fragt nach dem Installationsordner, Vorgabe ist
  `dropstopnshop` im aktuellen Verzeichnis, z. B. `~/dropstopnshop`. Darin liegen Programm,
  `config` und die aufbereiteten Folien (`data/`). Alles lässt sich ohne `sudo` bearbeiten,
  nur das Passwort für den Netzwerkordner liegt in `/etc/dropstopnshop/` (nur root).
- **SD-Karte:**
  - Logs und Browser-Profil liegen im RAM.
  - Automatische Updates sind abgeschaltet.

Details zu Pfaden und Aufbau stehen im [englischen README](README.md#how-it-works).

## Wartung

| Aufgabe | Befehl (per SSH) |
|---|---|
| **Irgendwas stimmt nicht – was sieht die Anzeige?** | `sudo bash ~/dropstopnshop/setup.sh --check` |
| Was macht der Abgleich? | `journalctl -u dropstopnshop-sync` |
| Sofort abgleichen | `sudo systemctl start dropstopnshop-sync` |
| Was macht die Anzeige? | `journalctl -u dropstopnshop-kiosk` |
| Anzeige neu starten | `sudo systemctl restart dropstopnshop-kiosk` |
| Einstellungen ändern (Ordner, Passwort, WLAN, …) | `sudo bash ~/dropstopnshop/setup.sh` |
| Wieder den Desktop starten (Image mit Desktop) | `sudo bash ~/dropstopnshop/setup.sh --desktop` |
| Alles entfernen und Systemänderungen rückgängig machen | `sudo bash ~/dropstopnshop/setup.sh --uninstall` |
| System aktualisieren (ab und zu) | `sudo apt update && sudo apt full-upgrade && sudo reboot` |

Nur aktualisieren, wenn währenddessen niemand den Strom abschaltet.

Optional richtet der Installer [Tailscale](https://tailscale.com) ein. Damit erreichst du den Pi
von überall per SSH, ohne Ports am Router zu öffnen.

## Vorschau unter Linux

Die Diashow lässt sich ohne Pi mit eigenen Dateien testen. Dafür braucht es `pdftoppm`: unter
Arch das Paket `poppler`, unter Debian/Ubuntu `poppler-utils`. Für das Auffüllen der Ränder
braucht es Pillow (`python-pillow` / `python3-pil`), für PowerPoint-Dateien LibreOffice.

```bash
bash setup.sh --preview pfad/zum/ordner
```

Die Seite öffnet sich im Browser und übernimmt Änderungen im Ordner, bis du Strg+C drückst.

## Grenzen

- **Datum ohne Netz:** Der Pi hat keine Uhr-Batterie. Ohne Netz kennt er das Datum eventuell
  nicht genau, dann kann ein abgelaufenes Angebot noch erscheinen.
- **PowerPoint:** Die Folien zeichnet LibreOffice, sie können also etwas anders aussehen als in
  PowerPoint, vor allem bei Schriften, die der Pi nicht hat. Animationen und Übergänge gibt es
  nicht. Sieht eine Folie falsch aus, sie stattdessen als PDF speichern: Das ist immer exakt.
- **Videos:** Der Pi 5 dekodiert H.264 in Software. Full HD (1080p) läuft, 4K nicht.
- **USB-Sticks:** müssen FAT32 oder exFAT formatiert sein. So kommen sie aus der Packung.

## Lizenz

[MIT](LICENSE). Benutzen, ändern, verkaufen, in den eigenen Laden stellen.
