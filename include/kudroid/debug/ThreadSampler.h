// Thread sampler: read where OTHER threads are, from outside them.




























#ifndef KUDROID_DEBUG_THREADSAMPLER_H
#define KUDROID_DEBUG_THREADSAMPLER_H

namespace kudroid {

// Write one breadcrumb line per thread in this process, plus a begin/end pair
// carrying `reason` and a sequence number so two samples can be told apart and
// diffed. Returns the number of threads reported, or 0 if the platform gave nothing.
//
// Safe to call from the telemetry watchdog while guest threads are wedged: it takes
// no lock a guest thread could hold, suspends nothing, and formats into stack
// buffers. `reason` appears verbatim in the output and should say what prompted the
// sample.
int thread_sample_report(const char* reason);

}  // namespace

#endif  // KUDROID_DEBUG_THREADSAMPLER_H
