#!/bin/bash
# PiFM Afro House Radio Installer
# Streams AfroRadio - Best of AfroHouse on 100.0 FM via GPIO4
# Tested on Raspberry Pi 3 B+ with Raspberry Pi OS Bookworm (32-bit)
#
# Usage: sudo bash install.sh [frequency] [stream_url]
# Example: sudo bash install.sh 100.0 https://itsshort.info/listen/afroradio/radio.mp3

set -e

FREQ=${1:-100.0}
STREAM=${2:-https://itsshort.info/listen/afroradio/radio.mp3}

echo "=== PiFM Afro House Radio Installer ==="
echo "Frequency : $FREQ MHz"
echo "Stream    : $STREAM"
echo ""

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run as root: sudo bash install.sh"
  exit 1
fi

# Set DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Install dependencies
echo "[1/4] Installing dependencies..."
apt-get update -y --fix-missing
apt-get install -y git ffmpeg libsndfile1-dev libsoxr-dev gcc make libasound2-dev

# Build PiFmAdv
echo "[2/4] Building PiFmAdv..."
rm -rf /tmp/PiFmAdv
git clone https://github.com/miegl/PiFmAdv /tmp/PiFmAdv
make -C /tmp/PiFmAdv/src
cp /tmp/PiFmAdv/src/pi_fm_adv /usr/local/bin/pi_fm_adv
chmod +x /usr/local/bin/pi_fm_adv

# Write stream script
echo "[3/4] Writing stream script..."
cat > /usr/local/bin/pifm-stream.sh << SCRIPT
#!/bin/bash
FREQ=$FREQ
STREAM=$STREAM
BUFFER=/var/lib/pifm/buffer.wav
BUFFERDIR=/var/lib/pifm

mkdir -p \$BUFFERDIR

get_max_bytes() {
  AVAIL=\$(df -m \$BUFFERDIR | awk 'NR==2{print \$4}')
  MAX_MB=\$(( AVAIL - 100 ))
  [ \$MAX_MB -lt 10 ] && MAX_MB=10
  echo \$(( MAX_MB * 1024 * 1024 ))
}

update_buffer() {
  while true; do
    timeout 60 /usr/bin/ffmpeg -re -y \\
      -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \\
      -i "\$STREAM" -t 60 -f wav -ar 44100 -ac 1 /tmp/pifm_chunk.wav 2>/dev/null
    if [ -s /tmp/pifm_chunk.wav ]; then
      cat /tmp/pifm_chunk.wav >> \$BUFFER
      MAX_BYTES=\$(get_max_bytes)
      CURRENT=\$(stat -c%s \$BUFFER 2>/dev/null || echo 0)
      if [ \$CURRENT -gt \$MAX_BYTES ]; then
        tail -c \$MAX_BYTES \$BUFFER > /tmp/pifm_trim.wav && mv /tmp/pifm_trim.wav \$BUFFER
      fi
    fi
    sleep 1
  done
}

update_buffer &

if [ -s \$BUFFER ]; then
  sudo /usr/local/bin/pi_fm_adv -a \$BUFFER -f \$FREQ 2>/dev/null &
  BOOT_PID=\$!
fi

sleep 5

kill \$BOOT_PID 2>/dev/null
pkill -f pi_fm_adv 2>/dev/null
sleep 1

while true; do
  pkill -f pi_fm_adv 2>/dev/null
  sleep 1
  timeout 300 /usr/bin/ffmpeg -re -y \\
    -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \\
    -i "\$STREAM" -af "dynaudnorm=p=0.95:m=100:s=12:g=15" \\
    -f wav -ar 44100 -ac 1 pipe:1 2>/dev/null | \\
    sudo /usr/local/bin/pi_fm_adv -a - -f \$FREQ
  if [ -s \$BUFFER ]; then
    sudo /usr/local/bin/pi_fm_adv -a \$BUFFER -f \$FREQ 2>/dev/null
  fi
  sleep 3
done
SCRIPT
chmod +x /usr/local/bin/pifm-stream.sh

# Write systemd service
echo "[4/4] Installing systemd service..."
cat > /etc/systemd/system/pifm.service << SERVICE
[Unit]
Description=PiFM Afro House Radio Stream
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/pifm-stream.sh
Restart=always
RestartSec=5
StartLimitIntervalSec=0
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable pifm
systemctl start pifm

# Write USB audio source-switch script
echo "[5/5] Installing USB audio source switcher..."
cat > /usr/local/bin/pifm-source-switch.sh << 'SWITCHSCRIPT'
#!/bin/bash
ACTION=$1
FREQ=100.0

usb_card() {
  arecord -l 2>/dev/null | grep -i "USB Audio" | grep -oP "card \K[0-9]+" | head -1
}

kill_all() {
  systemctl stop pifm-usb 2>/dev/null
  systemctl reset-failed pifm-usb 2>/dev/null
  systemctl stop pifm 2>/dev/null
  pkill -9 -f pi_fm_adv 2>/dev/null
  pkill -9 -f arecord 2>/dev/null
  pkill -9 -f ffmpeg 2>/dev/null
  sleep 2
}

case "$ACTION" in
  add)
    sleep 3
    CARD=$(usb_card)
    [ -z "$CARD" ] && exit 1
    kill_all
    systemd-run --unit=pifm-usb bash -c \
      "chrt -f 99 arecord -D hw:${CARD},0 -f S16_LE -r 44100 -c 1 --period-size=16 --buffer-size=64 | /usr/local/bin/pi_fm_adv -a - -f $FREQ"
    ;;
  remove)
    kill_all
    systemctl start pifm
    ;;
esac
SWITCHSCRIPT
chmod +x /usr/local/bin/pifm-source-switch.sh

cat > /etc/udev/rules.d/99-pifm-usb-audio.rules << 'UDEVRULE'
SUBSYSTEM=="sound", ACTION=="add", KERNEL=="controlC*", ATTRS{idVendor}=="08bb", ATTRS{idProduct}=="2902", RUN+="/usr/local/bin/pifm-source-switch.sh add"
SUBSYSTEM=="sound", ACTION=="remove", KERNEL=="controlC*", ATTRS{idVendor}=="08bb", ATTRS{idProduct}=="2902", RUN+="/usr/local/bin/pifm-source-switch.sh remove"
UDEVRULE
udevadm control --reload-rules

# Build and install alsa-to-stdout (minimal-latency ALSA reader)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/alsa-to-stdout.c" ]; then
  echo "[6/6] Building alsa-to-stdout..."
  gcc -O2 -o /usr/local/bin/alsa-to-stdout "$SCRIPT_DIR/alsa-to-stdout.c" -lasound
  chmod +x /usr/local/bin/alsa-to-stdout
fi

echo ""
echo "=== Done! ==="
echo "Streaming $STREAM on $FREQ MHz"
echo "Antenna: connect a 75cm wire to GPIO4 (Pin 7)"
echo ""
echo "Commands:"
echo "  sudo systemctl status pifm    # check status"
echo "  sudo systemctl stop pifm      # stop"
echo "  sudo systemctl start pifm     # start"
echo "  sudo journalctl -u pifm -f    # live logs"
