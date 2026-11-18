#pragma once

#include <cstdint>

// Capture microphone samples for Java audio input.






extern "C" {

// Smallest workable buffer in bytes, or a negative error when the parameters are invalid.
int32_t bionic_kudroid_audiorecord_min_buffer_size(int32_t sampleRateInHz, int32_t channelCount);

// Open a recorder. Returns 0 when the parameters are invalid or the host has not
// authorized the microphone, which AudioRecord reports as STATE_UNINITIALIZED.
int64_t bionic_kudroid_audiorecord_create(int32_t sampleRateInHz, int32_t channelCount,
                                          int32_t bufferSizeInBytes);

int32_t bionic_kudroid_audiorecord_start(int64_t rec);
int32_t bionic_kudroid_audiorecord_stop(int64_t rec);

// Copy up to `sizeInBytes` of captured PCM. A blocking read waits until the whole request
// is satisfied, the recorder stops, or the device stalls. Returns the bytes copied.
int32_t bionic_kudroid_audiorecord_read(int64_t rec, void* data, int32_t sizeInBytes,
                                        bool blocking);

int32_t bionic_kudroid_audiorecord_release(int64_t rec);

// Number of open recorders; the host audio session must allow input while this is non-zero.
int32_t kudroid_audio_capture_active(void);

// Drop every recorder at the end of a guest run.
void kudroid_audio_capture_release_all(void);

// Feed PCM to every recording recorder as the capture device would. Used by host tests,
// which have no microphone.
void kudroid_audio_capture_test_feed(const int16_t* samples, int32_t frames);

}  // extern "C"
