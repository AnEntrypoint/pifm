#!/bin/bash
FREQ=100.0
STREAM=https://itsshort.info/listen/afroradio/radio.mp3
BUFFER=/var/lib/pifm/buffer.wav
BUFFERDIR=/var/lib/pifm
FIFO=/tmp/pifm_audio.fifo

mkdir -p $BUFFERDIR
rm -f $FIFO && mkfifo $FIFO

get_max_bytes() {
  AVAIL=$(df -m $BUFFERDIR | awk 'NR==2{print $4}')
  MAX_MB=$(( AVAIL - 100 ))
  [ $MAX_MB -lt 10 ] && MAX_MB=10
  echo $(( MAX_MB * 1024 * 1024 ))
}

update_buffer() {
  while true; do
    timeout 60 /usr/bin/ffmpeg -re -y \
      -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -i "$STREAM" -t 60 -f wav -ar 44100 -ac 1 /tmp/pifm_chunk.wav 2>/dev/null
    if [ -s /tmp/pifm_chunk.wav ]; then
      cat /tmp/pifm_chunk.wav >> $BUFFER
      MAX_BYTES=$(get_max_bytes)
      CURRENT=$(stat -c%s $BUFFER 2>/dev/null || echo 0)
      if [ $CURRENT -gt $MAX_BYTES ]; then
        tail -c $MAX_BYTES $BUFFER > /tmp/pifm_trim.wav && mv /tmp/pifm_trim.wav $BUFFER
      fi
    fi
    sleep 1
  done
}
update_buffer &

# pi_fm_adv reads from the FIFO — never restarts, no FM gap
sudo /usr/local/bin/pi_fm_adv -a $FIFO -f $FREQ &
FMPID=$!
sleep 1

feed_live() {
  /usr/bin/ffmpeg -re -y \
    -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
    -i "$STREAM" -af "dynaudnorm=p=0.95:m=100:s=12:g=15" \
    -f wav -ar 44100 -ac 1 pipe:1 2>/dev/null > $FIFO
}

feed_buffer() {
  if [ -s $BUFFER ]; then
    /usr/bin/ffmpeg -re -y \
      -i $BUFFER -af "dynaudnorm=p=0.95:m=100:s=12:g=15" \
      -f wav -ar 44100 -ac 1 pipe:1 2>/dev/null > $FIFO
  else
    sleep 5
  fi
}

while kill -0 $FMPID 2>/dev/null; do
  feed_live
  feed_buffer
done
