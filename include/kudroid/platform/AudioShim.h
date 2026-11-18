#pragma once
#include "ShimDefs.h"

#include <cstdint>

namespace kudroid {
const SymbolEntry* get_audio_symbols(size_t* count);
}

// Bridge Java audio output to host playback.
















extern "C" {

void kudroid_audio_session_resume(void);
void kudroid_audio_session_suspend(void);

// Minimum workable buffer in bytes, or 0 if the parameters make no sense.
//
// `encoding` < 0 is a second query rather than a format: it asks for the device's
// preferred output rate, which is what AudioTrack.getNativeOutputSampleRate needs. One
// native method serves both so AudioTrack needs no extra binding for it.
int32_t bionic_kudroid_audiotrack_min_buffer_size(int32_t sampleRateInHz,
                                                  int32_t channelCount,
                                                  int32_t encoding);

// Open a player. Returns a handle, or 0 — which is what makes AudioTrack report
// STATE_UNINITIALIZED rather than claiming success and going silent.
int64_t bionic_kudroid_audiotrack_create(int32_t sampleRateInHz, int32_t channelCount,
                                         int32_t encoding, int32_t bufferSizeInBytes);

// Submit PCM. Returns the byte count accepted, or a negative AudioTrack error.
int32_t bionic_kudroid_audiotrack_write(int64_t track, const void* data, int32_t sizeInBytes);
int32_t bionic_kudroid_audiotrack_write_mode(int64_t track, const void* data,
                                          int32_t sizeInBytes, bool blocking);

int32_t bionic_kudroid_audiotrack_play(int64_t track);
int32_t bionic_kudroid_audiotrack_pause(int64_t track);
int32_t bionic_kudroid_audiotrack_stop(int64_t track);
int32_t bionic_kudroid_audiotrack_flush(int64_t track);
int32_t bionic_kudroid_audiotrack_release(int64_t track);
int32_t bionic_kudroid_audiotrack_set_volume(int64_t track, float volume);

// Frames the device has consumed, wrapping at 32 bits as the platform's does.


int32_t bionic_kudroid_audiotrack_head_position(int64_t track);

// Frames queued but not yet played. Used for smoothing, not for correctness.
int32_t bionic_kudroid_audiotrack_latency_frames(int64_t track);

}  // extern "C"
