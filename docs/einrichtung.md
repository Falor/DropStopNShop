# Einrichtung Schritt für Schritt (mit einem Windows-PC)

Diese Anleitung setzt nichts voraus. Du brauchst etwa **eine Stunde**, das meiste davon ist
Warten. Unter macOS oder Linux funktioniert es genauso: Statt PowerShell nimmst du das Terminal.

[🇬🇧 English version](setup-guide.md)

## Was du brauchst

| Teil | Hinweis |
|---|---|
| Raspberry Pi 5 (oder 4) | 2 GB RAM reichen |
| Offizielles Netzteil | Pi 5: USB-C mit 27 W. Billige Handy-Netzteile führen zu Abstürzen. |
| microSD-Karte, 16 GB oder mehr | Eine Markenkarte (A1/A2). Billige Karten gehen früher kaputt. |
| **Micro-HDMI**-auf-HDMI-Kabel | Der Pi hat kleine Micro-HDMI-Buchsen, normale HDMI-Kabel passen nicht. |
| Monitor oder Fernseher mit HDMI | Querformat ist am einfachsten |
| Netzwerkkabel zum Router | Empfohlen. WLAN geht auch. |
| Kartenleser am PC | Für die microSD-Karte |
| Schaltbare Steckdose (optional) | Schaltet Pi und Monitor gemeinsam ein und aus |

## Schritt 1: Den Ordner für die Inhalte anlegen

Die Anzeige holt sich ihre Inhalte aus einem Ordner im Netzwerk. Wähle **eine** Möglichkeit:

### A) FRITZ!Box mit USB-Festplatte oder USB-Stick (empfohlen, falls vorhanden)
1. Im Browser **http://fritz.box** öffnen und anmelden.
2. **Heimnetz → USB / Speicher**: Den Speicher (NAS) aktivieren.
3. **System → FRITZ!Box-Benutzer → Benutzer hinzufügen**:
   - Name z. B. `anzeige`, mit sicherem Passwort.
   - Haken bei **„Zugang zu NAS-Inhalten“**.
   - Wenn möglich nur **Leserecht** geben.
   Diesen Benutzer verwendet der Pi.
4. Am Windows-PC den Explorer öffnen und oben in die Adresszeile eintippen:
   `\\fritz.box\FRITZ.NAS`. Mit Enter bestätigen und mit deinem normalen FRITZ!Box-Konto anmelden.
5. Die Festplatte öffnen und einen neuen Ordner **`Bildschirm`** anlegen.

Den Pfad musst du dir nicht merken: Das Setup findet die FRITZ!Box und den Ordner selbst.

**Für den Alltag:** Damit der Ordner am Laden-PC immer als Laufwerk da ist, siehe
[Netzlaufwerk dauerhaft einbinden](netzlaufwerk.md).

### B) NAS (Synology, QNAP, …)
Lege einen freigegebenen Ordner an, z. B. `Bildschirm`, und einen Benutzer mit Leserecht darauf.
Der Pfad sieht dann so aus: `\\nas\Freigabe\Bildschirm`.

### C) Windows-PC
Das geht auch: Ordner → Rechtsklick → Eigenschaften → Freigabe. Allerdings muss der PC dann
immer laufen, wenn die Anzeige neue Inhalte holen soll. Ein NAS oder eine FRITZ!Box ist
praktischer.

### D) Kein Netzwerk, nur USB-Stick
Auch das geht. Du überspringst später einfach die Frage nach dem Netzwerkordner.

## Schritt 2: Die SD-Karte bespielen

1. Den **Raspberry Pi Imager** von https://www.raspberrypi.com/software/ herunterladen und
   installieren.
2. Die microSD-Karte in den PC stecken und den Imager starten.
3. Auswählen:
   - **Gerät:** Raspberry Pi 5 (bzw. 4)
   - **Betriebssystem:** *Raspberry Pi OS (other)* → **Raspberry Pi OS Lite (64-bit)**.
     Wichtig ist „Lite“, also ohne Desktop.
   - **Speicher:** deine microSD-Karte. **Vorsicht:** nicht aus Versehen eine andere Festplatte
     wählen!
4. Der Imager fragt nach **Anpassungen** (in älteren Versionen: „Einstellungen bearbeiten“).
   Trage ein:
   - **Hostname:** `dropstopnshop`
   - **Benutzername und Passwort:** z. B. `laden` und ein Passwort, das du dir **aufschreibst**
   - **WLAN:** nur, wenn kein Netzwerkkabel verwendet wird. Du kannst es auch später im Setup
     aus einer Liste auswählen.
   - **Zeitzone und Tastatur:** Europe/Berlin, `de`
   - **SSH aktivieren**, mit Passwort-Anmeldung
5. Schreiben lassen und warten, bis der Imager fertig ist. Dann die Karte entnehmen.

## Schritt 3: Den Pi zum ersten Mal starten

1. Karte in den Pi stecken. Monitor, Netzwerkkabel und **zuletzt** das Netzteil anschließen.
2. **3 Minuten warten.** Beim ersten Start richtet sich der Pi ein und startet einmal neu.
   Am Ende steht auf dem Monitor eine Anmeldeaufforderung. Das ist richtig so.

## Schritt 4: Vom PC aus mit dem Pi verbinden

1. Am PC auf **Start** klicken, **PowerShell** eintippen und öffnen.
2. Eintippen (statt `laden` deinen Benutzernamen aus Schritt 2) und Enter drücken:
   ```
   ssh laden@dropstopnshop.local
   ```
3. Beim ersten Mal kommt die Frage *„Are you sure you want to continue connecting?“*. Mit
   `yes` antworten und Enter drücken.
4. Das Passwort eingeben. **Beim Tippen erscheinen keine Zeichen.** Das ist normal, einfach
   tippen und Enter drücken.

**„Could not resolve hostname“?** Dann die Adresse des Pi im Router nachsehen. Bei der FRITZ!Box
unter **Heimnetz → Netzwerk**, dort heißt das Gerät „dropstopnshop“. Anschließend z. B.
`ssh laden@192.168.178.42` verwenden.

**Weder Netzwerkkabel noch WLAN?** Dann geht es auch direkt am Pi:
1. Die SD-Karte vor dem ersten Start noch einmal in den PC stecken. Es erscheint ein Laufwerk
   **bootfs**.
2. [`setup.sh`](https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh) herunterladen
   (Rechtsklick → „Speichern unter“) und auf **bootfs** kopieren.
3. Am Pi eine Tastatur anschließen, anmelden und `sudo bash /boot/firmware/setup.sh` eingeben.
   Das Setup bietet dann an, das WLAN einzurichten.

## Schritt 5: DropStopNShop installieren

Diese Zeile in die PowerShell kopieren (einfügen mit **Rechtsklick**) und Enter drücken:

```
curl -fsSL https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh | sudo bash
```

Wenn nach dem Passwort gefragt wird, das Passwort aus Schritt 2 eingeben. Dann stellt das Skript
ein paar Fragen. Wenn in eckigen Klammern schon eine Antwort steht, übernimmst du sie mit Enter.

| Frage | Antwort |
|---|---|
| Sprache | `de` |
| Fortfahren? | Das Setup zählt vorher auf, was es am System ändert. Enter. |
| WLAN jetzt einrichten? | Kommt nur, wenn kein WLAN verbunden ist. Bei Ja: Land (`DE`), Netz aus der Liste wählen, Passwort. |
| Installationsordner | Enter (z. B. `/home/laden/dropstopnshop`) |
| Name des Ordners | `Bildschirm` (oder wie du ihn in Schritt 1 genannt hast) |
| Sekunden pro Folie | Enter (12 Sekunden) oder eine andere Zahl |
| Tailscale | `n`, außer du willst den Pi aus der Ferne warten |
| Woher kommen die Inhalte? | `1` = FRITZ!Box-Assistent (siehe unten), `2` = Pfad zu einem NAS oder PC eingeben, `3` = nur USB-Stick |
| Benutzername / Passwort | Der Benutzer, den du in Schritt 1 für den Pi angelegt hast |

Der **FRITZ!Box-Assistent** meldet sich an und sucht den Ordner auf dem Speicher. Hängen mehrere
Speicher an der FRITZ!Box, fragt er, welcher. Fehlt der Ordner noch, legst du ihn am PC an und
drückst Enter. Andere Pfade werden ebenfalls gleich geprüft, bevor sie gespeichert werden.

Danach installiert das Skript alles. **Das dauert 10–20 Minuten.** Am Ende zeigt es den ersten
Abgleich an, z. B. „Fertig: 0 Folien“, solange der Ordner noch leer ist. Auf die Frage „Jetzt
neu starten?“ mit Enter antworten.

## Schritt 6: Ausprobieren

1. Eine Präsentation in **PowerPoint** (oder LibreOffice Impress, Canva …) erstellen und sie
   oder ein PDF davon in den Ordner `Bildschirm` speichern.
2. Höchstens 3 Minuten warten, dann erscheint sie auf dem Monitor.

Fertig! Wie man im Alltag Inhalte ändert, steht in der [Bedienungsanleitung](bedienung.md).
Die kannst du ausdrucken und neben den PC hängen.

## Wenn etwas nicht klappt

| Problem | Lösung |
|---|---|
| Monitor zeigt „Keine Inhalte gefunden“ | Der Ordner ist leer oder nicht erreichbar. Siehe nächste Zeile. |
| Inhalte kommen nicht an | Per SSH verbinden (Schritt 4) und `sudo bash ~/dropstopnshop/setup.sh --check` eingeben. Das zeigt, ob ein USB-Stick steckt (der hat Vorrang!), ob der Netzwerkordner erreichbar ist, welche Dateien gefunden werden und was gerade angezeigt wird. Häufig sind Pfad oder Passwort falsch: Das Setup einfach erneut ausführen mit `sudo bash ~/dropstopnshop/setup.sh`. |
| Monitor zeigt Text oder einen Desktop statt der Anzeige | Per SSH `journalctl -u dropstopnshop-kiosk -n 50` eingeben, dort steht der Fehler. |
| Monitor bleibt schwarz | Steckt das Kabel in der Micro-HDMI-Buchse **neben dem USB-C-Anschluss** (HDMI 0)? Monitor auf den richtigen Eingang gestellt? |
| Pi startet ständig neu | Netzteil zu schwach. Das offizielle verwenden. |
| Alles kaputt | Karte neu bespielen und von vorn anfangen. Die Inhalte liegen ja im Netzwerkordner, verloren geht nichts. |

## Rückgängig machen

| Was | Befehl (per SSH) |
|---|---|
| Den Desktop statt der Anzeige starten (nur beim Image mit Desktop) | `sudo bash ~/dropstopnshop/setup.sh --desktop` |
| Zurück zur Anzeige | `sudo bash ~/dropstopnshop/setup.sh` |
| DropStopNShop komplett entfernen | `sudo bash ~/dropstopnshop/setup.sh --uninstall` |

Beim Entfernen werden die Dienste gelöscht und die Änderungen am System zurückgenommen. Den
Installationsordner löscht es nur nach Rückfrage. Die Inhalte im Netzwerkordner bleiben immer
erhalten.
