# Den Ordner am Windows-PC dauerhaft einbinden

So erscheint der Ordner mit den Inhalten am Laden-PC als eigenes Laufwerk im Explorer, z. B.
**B: Bildschirm**. Er ist dann nach jedem Neustart des PCs von selbst wieder da, ohne Passwort
und ohne Netzwerkpfad tippen zu müssen.

[🇬🇧 English version](network-drive.md)

Die Anleitung geht von einer **FRITZ!Box** mit angeschlossener Festplatte oder USB-Stick aus. Für
ein NAS gilt dasselbe, nur der Pfad ist anders.

## Vorbereitung an der FRITZ!Box (einmalig)

1. Im Browser **http://fritz.box** öffnen und anmelden.
2. **Heimnetz → USB / Speicher → Heimnetzfreigabe:** **Speicher (NAS) aktiv** anhaken und
   übernehmen.
3. **System → FRITZ!Box-Benutzer:** Für den Laden-PC brauchst du einen Benutzer, der **lesen und
   schreiben** darf: „Zugang zu NAS-Inhalten“ anhaken, Rechte „Lesen“ und „Schreiben“. Das kann
   dein normales FRITZ!Box-Konto sein.

Der Pi bekommt am besten einen **eigenen** Benutzer, der nur lesen darf. Den fragt das Setup ab.

## Netzlaufwerk verbinden (Windows 10 und 11)

1. Den **Explorer** öffnen (Ordner-Symbol in der Taskleiste oder Windows-Taste + E).
2. Links auf **Dieser PC** klicken.
3. Oben:
   - **Windows 11:** auf **„…“** (Mehr anzeigen) klicken, dann **Netzlaufwerk verbinden**.
   - **Windows 10:** oben auf **Computer**, dann **Netzlaufwerk verbinden**.
4. Im Fenster eintragen:
   - **Laufwerk:** einen freien Buchstaben wählen, z. B. **B:**
   - **Ordner:** den Pfad zum Ordner, z. B.
     `\\fritz.box\FRITZ.NAS\USB-Speicher\Bildschirm`.
     Den genauen Namen des Speichers zeigt das Setup am Ende des FRITZ!Box-Assistenten an.
     Du siehst ihn auch, wenn du im Explorer oben `\\fritz.box\FRITZ.NAS` eintippst.
   - Haken bei **Verbindung bei Anmeldung wiederherstellen**
   - Haken bei **Verbindung mit anderen Anmeldeinformationen herstellen**
5. **Fertig stellen** klicken.
6. Benutzername und Passwort des FRITZ!Box-Benutzers mit Schreibrecht eingeben und
   **Anmeldedaten speichern** anhaken. Dann **OK**.

Der Ordner öffnet sich und steht ab jetzt unter **Dieser PC** als Laufwerk **B:**.

**Tipp:** Rechtsklick auf das Laufwerk → **Umbenennen** → `Bildschirm`. Danach Rechtsklick →
**An Schnellzugriff anheften**. Dann ist er links im Explorer immer sichtbar.

## Wenn es nicht klappt

| Meldung | Lösung |
|---|---|
| „Der Netzwerkpfad wurde nicht gefunden“ (0x80070035) | Statt `fritz.box` die Adresse der FRITZ!Box nehmen: `\\192.168.178.1\FRITZ.NAS\…`. Und prüfen, ob „Speicher (NAS) aktiv“ angehakt ist. |
| „Zugriff verweigert“ / Passwort wird nicht angenommen | Hat der Benutzer in der FRITZ!Box „Zugang zu NAS-Inhalten“? Bei den Rechten auch „Schreiben“? |
| Laufwerk hat ein rotes Kreuz | Die FRITZ!Box war beim Anmelden noch nicht erreichbar. Einmal doppelklicken, dann verbindet es sich. |
| Nach Passwortänderung geht nichts mehr | Start → **Anmeldeinformationsverwaltung** → **Windows-Anmeldeinformationen** → den Eintrag für `fritz.box` bearbeiten. |
