# Step-by-step setup (with a Windows PC)

This guide assumes no prior knowledge. Plan for about **an hour**, most of it waiting. On macOS
or Linux it works the same way: use the Terminal instead of PowerShell.

[🇩🇪 Deutsche Version](einrichtung.md)

## What you need

| Part | Note |
|---|---|
| Raspberry Pi 5 (or 4) | 2 GB RAM is enough |
| Official power supply | Pi 5: USB-C, 27 W. Cheap phone chargers cause crashes. |
| microSD card, 16 GB or more | A brand-name card (A1/A2). Cheap cards wear out sooner. |
| **Micro-HDMI** to HDMI cable | The Pi has small micro-HDMI sockets, so regular HDMI cables don't fit. |
| Monitor or TV with HDMI | Landscape is easiest |
| Network cable to the router | Recommended. Wi-Fi works too. |
| Card reader on the PC | For the microSD card |
| Smart plug (optional) | Switches the Pi and the monitor on and off together |

## Step 1: Create the folder for the content

The display gets its content from a folder on the network. Pick **one** option:

### A) Router with USB storage (e.g. FRITZ!Box)
Many routers can share a plugged-in USB drive on the network.
1. Enable the storage sharing (SMB/NAS) in the router's web interface.
2. Create a user for the Pi with **read-only** access.
3. On the Windows PC, open File Explorer and type the router's share into the address bar, e.g.
   `\\fritz.box\FRITZ.NAS`.
4. Open the drive and create a new folder **`Display`**.
5. Write down the path that File Explorer shows at the top, e.g.
   `\\fritz.box\FRITZ.NAS\MyDrive\Display`. With a FRITZ!Box you can skip this: the setup
   finds the router and the folder by itself.

**For everyday use:** To keep the folder available as a drive on the shop PC, see
[map the folder permanently](network-drive.md).

### B) NAS (Synology, QNAP, …)
Create a shared folder, e.g. `Display`, and a user with read access to it. The path then looks
like `\\nas\share\Display`.

### C) Windows PC
This works too: right-click the folder → Properties → Sharing. But the PC has to be running
whenever the display should pick up new content. A NAS or router is more practical.

### D) No network, USB stick only
That's fine. You'll simply skip the network folder question later.

## Step 2: Prepare the SD card

1. Download and install the **Raspberry Pi Imager** from https://www.raspberrypi.com/software/.
2. Insert the microSD card into the PC and start the Imager.
3. Choose:
   - **Device:** Raspberry Pi 5 (or 4)
   - **Operating system:** *Raspberry Pi OS (other)* → **Raspberry Pi OS Lite (64-bit)**.
     It has to be "Lite", i.e. without a desktop.
   - **Storage:** your microSD card. **Careful:** don't pick another drive by mistake!
4. The Imager asks for **customisation** (older versions: "Edit settings"). Enter:
   - **Hostname:** `dropstopnshop`
   - **Username and password:** e.g. `shop` and a password you **write down**
   - **Wi-Fi:** only if you don't use a network cable. You can also pick it from a list later
     in the setup.
   - **Time zone and keyboard layout:** yours
   - **Enable SSH**, with password authentication
5. Let it write and wait until the Imager is done. Then take out the card.

## Step 3: First start of the Pi

1. Put the card into the Pi. Connect the monitor, the network cable and the power supply **last**.
2. **Wait 3 minutes.** On the first start the Pi sets itself up and reboots once. In the end
   the monitor shows a login prompt. That's expected.

## Step 4: Connect to the Pi from the PC

1. On the PC click **Start**, type **PowerShell** and open it.
2. Type this (replace `shop` with your username from step 2) and press Enter:
   ```
   ssh shop@dropstopnshop.local
   ```
3. The first time, you'll be asked *"Are you sure you want to continue connecting?"*. Type `yes`
   and press Enter.
4. Enter the password. **Nothing appears while you type.** That's normal, just type and press
   Enter.

**"Could not resolve hostname"?** Then look up the Pi's address in your router's list of
devices, where it's called "dropstopnshop". Then use e.g. `ssh shop@192.168.1.42`.

**Neither a network cable nor Wi-Fi?** Then you can run it directly on the Pi:
1. Before the first start, put the SD card into the PC once more. A drive called **bootfs**
   shows up.
2. Download [`setup.sh`](https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh)
   (right-click → "Save as") and copy it onto **bootfs**.
3. Connect a keyboard to the Pi, sign in and type `sudo bash /boot/firmware/setup.sh`. The setup
   then offers to set up Wi-Fi.

## Step 5: Install DropStopNShop

Copy this line into PowerShell (paste with a **right-click**) and press Enter:

```
curl -fsSL https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh | sudo bash
```

If asked for a password, enter the one from step 2. Then the script asks a few questions. When
there's already an answer in square brackets, press Enter to accept it.

| Question | Answer |
|---|---|
| Language | `en` |
| Continue? | The setup first lists what it changes on the system. Enter. |
| Set up Wi-Fi now? | Only asked when no Wi-Fi is connected. If yes: country (e.g. `GB`), pick the network from the list, password. |
| Install folder | Enter (e.g. `/home/shop/dropstopnshop`) |
| Name of the folder | `Display` (or whatever you called it in step 1) |
| Seconds per slide | Enter (12 seconds) or another number |
| Tailscale | `n`, unless you want to maintain the Pi remotely |
| Where does the content come from? | `1` = FRITZ!Box assistant (only shown if one is found), then a path for a NAS or PC, or USB stick only |
| Username / password | The user you created for the Pi in step 1 |

The **FRITZ!Box assistant** signs in and looks for the folder on the router's storage. If several
drives are connected it asks which one. If the folder is missing, create it on the PC and press
Enter. Other paths are tested right away too, before they are saved.

The script then installs everything. **This takes 10–20 minutes.** At the end it shows the first
sync, e.g. "Done: 0 slides" while the folder is still empty. Answer "Reboot now?" with Enter.

## Step 6: Try it

1. Make a presentation in **PowerPoint** (or LibreOffice Impress, Canva, …) and save it, or a PDF
   of it, into the `Display` folder.
2. Wait 3 minutes at most, and it appears on the monitor.

Done! How to change content day to day is explained in the [user guide](user-guide.md). Print it
and put it next to the PC.

## Troubleshooting

| Problem | Solution |
|---|---|
| Monitor shows "No content found" | The folder is empty or unreachable. See the next row. |
| Content doesn't show up | Connect via SSH (step 4) and type `sudo bash ~/dropstopnshop/setup.sh --check`. It shows whether a USB stick is plugged in (it takes priority!), whether the network folder is reachable, which files are found and what is on screen right now. Often the path or password is wrong: just run the setup again with `sudo bash ~/dropstopnshop/setup.sh`. |
| Monitor shows text or a desktop instead of the slideshow | Connect via SSH and type `journalctl -u dropstopnshop-kiosk -n 50`, it shows the error. |
| Monitor stays black | Is the cable in the micro-HDMI socket **next to the USB-C port** (HDMI 0)? Is the monitor set to the right input? |
| Pi keeps rebooting | Power supply too weak. Use the official one. |
| Everything is broken | Flash the card again and start over. The content lives in the network folder, so nothing is lost. |

## Undo

| What | Command (via SSH) |
|---|---|
| Start the desktop instead of the display (desktop image only) | `sudo bash ~/dropstopnshop/setup.sh --desktop` |
| Back to the display | `sudo bash ~/dropstopnshop/setup.sh` |
| Remove DropStopNShop completely | `sudo bash ~/dropstopnshop/setup.sh --uninstall` |

Removing it deletes the services and reverts the system changes. It only deletes the install
folder if you confirm. The content in the network folder is never touched.
