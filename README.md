# Pi FM Radio

Streams AfroRadio (Afro House 24/7) over FM via GPIO4 on a Raspberry Pi 3 B+.

## Hardware

- Raspberry Pi 3 B+
- 75cm wire antenna on GPIO4 (Pin 7)
- Optional: PN2222A transistor amplifier on GPIO4 for better range

### PN2222A Amplifier (optional)
```
Pi Pin 4  (5V)    ──[220Ω]── Collector (C, right leg, flat face up)
Pi Pin 7  (GPIO4) ──[1kΩ]─── Base (B, middle leg)
Pi Pin 9  (GND)   ──[10kΩ]── Base (B, middle leg) -- bias to GND
                              Emitter (E, left leg) ── antenna wire
```

## Setup

### 1. Flash SD Card (Raspberry Pi OS Bookworm 32-bit)

Set up headless boot on the SD card boot partition:

```
# WiFi
wpa_supplicant.conf  (country=ZA, ssid/psk)

# Enable SSH
touch ssh

# Pre-create user (bypasses first-run wizard)
echo "pi:$(echo 'raspberry' | openssl passwd -6 -stdin)" > userconf.txt
```

### 2. Install

SSH into the Pi then run:

```bash
git clone https://github.com/yourrepo/pifm /tmp/pifm-install
sudo bash /tmp/pifm-install/install.sh
```

Or copy `install.sh` to the Pi and run:

```bash
sudo bash install.sh [frequency] [stream_url]
```

Default: **100.0 MHz**, AfroRadio stream.

### 3. Verify

```bash
sudo systemctl status pifm
sudo journalctl -u pifm -f
```

Tune an FM radio to **100.0 MHz**.

## Configuration

Change frequency or stream by editing `/usr/local/bin/pifm-stream.sh`:

```bash
sudo nano /usr/local/bin/pifm-stream.sh
sudo systemctl restart pifm
```

## Streams

| Station | URL |
|---------|-----|
| AfroRadio - Best of AfroHouse | `https://itsshort.info/listen/afroradio/radio.mp3` |

## Notes

- GPIO4 is the only pin that works for FM transmission (hardcoded in PiFmAdv)
- Tested on Raspberry Pi OS Bookworm 32-bit, kernel 6.12
- Uses PiFmAdv (https://github.com/miegl/PiFmAdv) — works on modern kernels via /dev/vcio
- Legal: keep antenna short, for personal/indoor use only
