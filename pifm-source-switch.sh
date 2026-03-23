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
