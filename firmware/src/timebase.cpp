#if !defined(ARDUINO)

#include "timebase.h"

static uint32_t s_fakeMs = 0;

uint32_t nowMs() { return s_fakeMs; }

void tb_set(uint32_t ms) { s_fakeMs = ms; }

void tb_advance(uint32_t deltaMs) { s_fakeMs += deltaMs; }

void tb_reset() { s_fakeMs = 0; }

#endif
