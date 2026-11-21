#pragma once

#include <cerrno>
#include <poll.h>
#include <sys/stat.h>

namespace kudroid {

// Darwin random devices reject poll despite supporting nonblocking reads.
inline void NormalizeEntropyPollReadiness(pollfd* fds, nfds_t count, int result) {
    if (!fds || result <= 0) return;
    const int savedErrno = errno;
    for (nfds_t i = 0; i < count; ++i) {
        const short readable = fds[i].events & (POLLIN | POLLRDNORM);
        if (!readable || fds[i].revents != POLLNVAL) continue;
        struct stat descriptor{};
        if (::fstat(fds[i].fd, &descriptor) != 0 || !S_ISCHR(descriptor.st_mode)) continue;
        struct stat device{};
        const bool random =
            (::stat("/dev/urandom", &device) == 0 && S_ISCHR(device.st_mode) &&
             descriptor.st_rdev == device.st_rdev) ||
            (::stat("/dev/random", &device) == 0 && S_ISCHR(device.st_mode) &&
             descriptor.st_rdev == device.st_rdev);
        if (random) fds[i].revents = readable;
    }
    errno = savedErrno;
}

}  // namespace kudroid
