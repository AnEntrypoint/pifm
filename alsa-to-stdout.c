#include <stdio.h>
#include <stdlib.h>
#include <alsa/asoundlib.h>
#include <fcntl.h>
#ifndef F_SETPIPE_SZ
#define F_SETPIPE_SZ 1031
#endif

#define PERIOD_FRAMES 16
#define BUFFER_FRAMES 64
#define RATE 44100
#define CHANNELS 1

int main(int argc, char *argv[]) {
    const char *device = argc > 1 ? argv[1] : "hw:2,0";
    snd_pcm_t *pcm;
    snd_pcm_hw_params_t *params;
    int16_t buf[PERIOD_FRAMES * CHANNELS];
    int err;

    // Write a minimal WAV header to stdout so pi_fm_adv accepts stdin
    // Use a large data chunk size (live stream)
    uint8_t wav_header[44] = {
        'R','I','F','F', 0xFF,0xFF,0xFF,0x7F, // chunk size = max
        'W','A','V','E',
        'f','m','t',' ', 16,0,0,0,            // subchunk1 size
        1,0,                                   // PCM
        CHANNELS,0,                            // channels
        RATE&0xFF,(RATE>>8)&0xFF,(RATE>>16)&0xFF,(RATE>>24)&0xFF,
        (RATE*CHANNELS*2)&0xFF,((RATE*CHANNELS*2)>>8)&0xFF,
        ((RATE*CHANNELS*2)>>16)&0xFF,((RATE*CHANNELS*2)>>24)&0xFF,
        CHANNELS*2,0,                          // block align
        16,0,                                  // bits per sample
        'd','a','t','a',
        0xFF,0xFF,0xFF,0x7F                    // data chunk size = max
    };
    fwrite(wav_header, 1, 44, stdout);
    fflush(stdout);

    // Set stdout pipe buffer to minimum (4096 bytes = ~23ms at 44100 16-bit mono)
    fcntl(STDOUT_FILENO, F_SETPIPE_SZ, 4096);

    if ((err = snd_pcm_open(&pcm, device, SND_PCM_STREAM_CAPTURE, 0)) < 0) {
        fprintf(stderr, "open error: %s\n", snd_strerror(err));
        return 1;
    }

    snd_pcm_hw_params_alloca(&params);
    snd_pcm_hw_params_any(pcm, params);
    snd_pcm_hw_params_set_access(pcm, params, SND_PCM_ACCESS_RW_INTERLEAVED);
    snd_pcm_hw_params_set_format(pcm, params, SND_PCM_FORMAT_S16_LE);
    unsigned int rate = RATE;
    snd_pcm_hw_params_set_rate_near(pcm, params, &rate, 0);
    snd_pcm_hw_params_set_channels(pcm, params, CHANNELS);
    snd_pcm_uframes_t period = PERIOD_FRAMES;
    snd_pcm_hw_params_set_period_size_near(pcm, params, &period, 0);
    snd_pcm_uframes_t buffer = BUFFER_FRAMES;
    snd_pcm_hw_params_set_buffer_size_near(pcm, params, &buffer);
    snd_pcm_hw_params(pcm, params);
    snd_pcm_prepare(pcm);

    while (1) {
        err = snd_pcm_readi(pcm, buf, PERIOD_FRAMES);
        if (err == -EPIPE) { snd_pcm_prepare(pcm); continue; }
        if (err < 0) break;
        fwrite(buf, sizeof(int16_t) * CHANNELS, err, stdout);
        fflush(stdout);
    }

    snd_pcm_close(pcm);
    return 0;
}
