# Map the folder permanently on a Windows PC

This makes the folder with the content show up on the shop PC as its own drive in File Explorer,
e.g. **B: Display**. It comes back by itself after every restart of the PC, without typing a
password or a network path.

[🇩🇪 Deutsche Version](netzlaufwerk.md)

This guide uses a **FRITZ!Box** router with a connected USB drive as the example. For a NAS it
works the same way, only the path differs.

## Preparing the router (once)

1. Open **http://fritz.box** in the browser and sign in.
2. **Home Network → USB / Storage → Home Network Sharing:** tick **Storage (NAS) active** and
   apply.
3. **System → FRITZ!Box Users:** The shop PC needs a user that may **read and write**. Tick
   "Access to NAS contents" with the rights "Read" and "Write". This can be your regular account.

Best give the Pi a user **of its own** that may only read. The setup asks for it.

## Map the network drive (Windows 10 and 11)

1. Open **File Explorer** (folder icon in the taskbar, or Windows key + E).
2. Click **This PC** on the left.
3. At the top:
   - **Windows 11:** click **"…"** (See more), then **Map network drive**.
   - **Windows 10:** click **Computer** at the top, then **Map network drive**.
4. Fill in:
   - **Drive:** any free letter, e.g. **B:**
   - **Folder:** the path to the folder, e.g. `\\fritz.box\FRITZ.NAS\USB-Storage\Display`.
     The setup shows the exact storage name at the end of the FRITZ!Box assistant. You can also
     see it by typing `\\fritz.box\FRITZ.NAS` into File Explorer's address bar.
   - Tick **Reconnect at sign-in**
   - Tick **Connect using different credentials**
5. Click **Finish**.
6. Enter the username and password of the router user with write access, and tick **Remember my
   credentials**. Then **OK**.

The folder opens and from now on sits under **This PC** as drive **B:**.

**Tip:** Right-click the drive → **Rename** → `Display`. Then right-click → **Pin to Quick
access**. That way it's always visible on the left in File Explorer.

## If it doesn't work

| Message | Solution |
|---|---|
| "The network path was not found" (0x80070035) | Use the router's address instead of `fritz.box`, e.g. `\\192.168.178.1\FRITZ.NAS\…`. Also check that "Storage (NAS) active" is ticked. |
| "Access denied" / password not accepted | Does the user have "Access to NAS contents"? With the "Write" right too? |
| The drive shows a red cross | The router wasn't reachable yet at sign-in. Double-click it once and it connects. |
| Nothing works after a password change | Start → **Credential Manager** → **Windows Credentials** → edit the entry for `fritz.box`. |
