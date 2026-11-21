#include "JITNotifications.h"
#include <notify.h>

uint32_t kudroid_post_jit_progress(const char *name) {
    return notify_post(name);
}
