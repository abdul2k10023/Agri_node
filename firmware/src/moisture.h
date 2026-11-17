#ifndef MOIST_NODE_MOISTURE_H
#define MOIST_NODE_MOISTURE_H

#include <stdint.h>

#define MOISTURE_SAMPLE_COUNT 5

struct moisture_samples {
    /* Raw charge times in microseconds; -1 marks a failed measurement. */
    int64_t elapsed_us[MOISTURE_SAMPLE_COUNT];
};

/* Collect one batch. Returns 0 on success, or a negative error code.
 * On measurement failure, all five are still attempted and results retained.
 * Sleeps during each discharge; call from a thread, not an interrupt.
 */
int ping_moisture_sensor(struct moisture_samples *samples);

#endif
