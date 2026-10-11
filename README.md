# DropStopNShop

**Drop a file into a folder, and it's on the screen in your shop.**

[🇩🇪 Deutsche Version](README.de.md)

DropStopNShop turns a Raspberry Pi and any monitor into a display for price lists, offers and
announcements. The content is simply files in a shared folder:
- **PDFs** made with LibreOffice, Canva, Word, PowerPoint, …
- **Images**
- **Videos**

There is no CMS, no cloud, no subscription and no app to learn. If you can save a PDF, you can
run the display.

It's made for small businesses such as shops, cafés, practices or workshops: usable by people
who don't care about technology, built to still work in 10 years, and frugal with power.

## Features

- **The folder is the playlist:** files play in name order (`01_…`, `02_…`). Delete a file and
  it's gone from the screen.
- **PDF pages become slides:** a 5-page PDF gives 5 slides.
- **Offers expire by themselves:** put `until 2026-11-30` or `bis 30.11.2026` in the file name.
- **Works offline:** a USB stick with the folder takes priority (trade fairs, no network). If the
  network folder is unreachable, the last content keeps playing.
- **Made for smart plugs:** switch the Pi and monitor off hard every evening. The Pi barely writes
  to the SD card, so a power cut can't break it.
- **One script:** `setup.sh` installs everything on a fresh Raspberry Pi OS. It shows what it
  will change before it starts, can set up Wi-Fi and find the folder on a FRITZ!Box, and
  `--uninstall` undoes it all.
- **German or English** installer and screen messages.

## Quick start

You need:
- a Raspberry Pi 5 or 4 with power supply
- a microSD card
- a monitor
- optionally a network folder (SMB), e.g. on a FRITZ!Box, a NAS or a Windows PC

1. Flash **Raspberry Pi OS Lite (64-bit)** with the [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
   Set a username and password, and enable SSH.
2. Boot the Pi, connect via SSH and run:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Falor/DropStopNShop/main/setup.sh | sudo bash
   ```
3. Answer the questions: language, folder name, network folder and its credentials. Then reboot.

**First time doing this, or on Windows?** Follow the
[step-by-step setup guide](docs/setup-guide.md). It assumes no prior knowledge.

**For the people who change the content:** see the [user guide](docs/user-guide.md)
(German: [Bedienung](docs/bedienung.md)). Print it and stick it next to the shop PC. To make
the folder a permanent drive on the shop PC, see [network drive](docs/network-drive.md).

## How it works

```
┌──────────────┐  every 3 min   ┌──────────────────────────────┐
│ USB stick    │ ─────────────▶ │ dropstopnshop-sync           │
│  or SMB share│   (USB wins)   │ PDF → PNG, copy images/videos│
└──────────────┘                │ → ~/dropstopnshop/data/      │
                                └──────────────┬───────────────┘
                                               │ playlist.js
                                ┌──────────────▼───────────────┐
                                │ cage + Chromium (kiosk)      │
                                │ index.html: slideshow        │
                                └──────────────────────────────┘
```

- **Sync:** A systemd timer runs the sync job every 3 minutes. It only writes when something
  changed. A new state is written completely first and then switched over atomically, so a power
  cut always leaves a complete state behind.
- **Display:** After power-on, the systemd service `dropstopnshop-kiosk` starts
  [cage](https://github.com/cage-kiosk/cage) with Chromium in kiosk mode on `tty1`. It shows a
  static HTML page that reloads the playlist after every round. If a desktop image was used, the
  setup switches it to boot to the console.
- **SD card:**
  - Logs and the browser profile live in RAM.
  - Automatic updates are disabled.

Everything lives in the install folder. The setup asks for it; the default is `dropstopnshop`
in the current directory, e.g. `~/dropstopnshop`. You can edit everything there without `sudo`.

| Path | Contents |
|---|---|
| `~/dropstopnshop/index.html` | the slideshow page |
| `~/dropstopnshop/dropstopnshop-sync` | the sync job |
| `~/dropstopnshop/kiosk.sh` | starts the browser |
| `~/dropstopnshop/setup.sh` | a copy of the installer |
| `~/dropstopnshop/config` | language, folder name, share path, seconds per slide, render width |
| `~/dropstopnshop/data/` | prepared slides (`state-…`, symlink `current`), written by the sync job |
| `/etc/dropstopnshop/share-credentials` | username and password for the share (root only) |
| `/etc/dropstopnshop/location` | where the install folder is |

## Maintenance

| Task | Command (via SSH) |
|---|---|
| **Something's wrong – what does the display see?** | `sudo bash ~/dropstopnshop/setup.sh --check` |
| What is the sync doing? | `journalctl -u dropstopnshop-sync` |
| Sync right now | `sudo systemctl start dropstopnshop-sync` |
| What is the display doing? | `journalctl -u dropstopnshop-kiosk` |
| Restart the display | `sudo systemctl restart dropstopnshop-kiosk` |
| Change settings (share, password, Wi-Fi, …) | `sudo bash ~/dropstopnshop/setup.sh` |
| Boot to the desktop again (desktop image) | `sudo bash ~/dropstopnshop/setup.sh --desktop` |
| Remove everything and undo the system changes | `sudo bash ~/dropstopnshop/setup.sh --uninstall` |
| Update the system (now and then) | `sudo apt update && sudo apt full-upgrade && sudo reboot` |

Only update when nobody will switch off the power in the meantime.

The installer can optionally set up [Tailscale](https://tailscale.com). With it you can reach
the Pi via SSH from anywhere, without opening ports on the router.

## Preview on a Linux desktop

Try the slideshow with your own files, without a Pi. It needs `pdftoppm`: install `poppler` on
Arch, `poppler-utils` on Debian/Ubuntu.

```bash
bash setup.sh --preview path/to/folder
```

The page opens in your browser and picks up changes to the folder until you press Ctrl+C.

## Limitations

- **Dates offline:** The Pi has no clock battery. Without a network it may not know the exact
  date, so an expired offer can show up again.
- **Videos:** The Pi 5 decodes H.264 in software. Full HD (1080p) is fine, 4K is not.
- **USB sticks:** must be formatted FAT32 or exFAT. That is how they come out of the box.

## License

[MIT](LICENSE). Use it, change it, sell it, put it in your shop.
