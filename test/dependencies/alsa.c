#include <stddef.h>
#include <stdio.h>

extern size_t snd_pcm_status_sizeof(void);
extern int snd_config_update(void);
extern void snd_config_update_free_global(void);

int main(void) {
    if (snd_pcm_status_sizeof() == 0) {
        return 1;
    }
    if (snd_config_update() < 0) {
        return 2;
    }
    snd_config_update_free_global();
    puts("PASS: ALSA interface resolved against the native provider");
    return 0;
}
