/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#include "tgtimer-c.h"


struct tgl_timer *tgtimer_alloc (struct tgl_state *TLS, void (*callback)(struct tgl_state *TLS, void *arg), void *arg) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (!timer) {
        return NULL;
    }
    dispatch_source_set_event_handler(timer, ^{
        if (dispatch_get_context(timer) == NULL) {
            return; // should be suspended
        }
        dispatch_suspend(timer);
        dispatch_set_context(timer, NULL);
        dispatch_async(tgtimer_target_queue, ^{
            callback(TLS, arg);
        });
    });
    dispatch_source_set_cancel_handler(timer, ^{
        dispatch_set_context(timer, NULL);
    });
    return (void *)(timer);
}

void tgtimer_insert (struct tgl_timer *t, double seconds) {
    dispatch_source_t timer = (dispatch_source_t)(t);
    uint64_t nanosecs = seconds < 0 ? 0 : seconds * NSEC_PER_SEC;
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, nanosecs, 1ull * NSEC_PER_SEC);
    if (dispatch_get_context(timer) == NULL) {
        dispatch_set_context(timer, (void *)(timer));
        dispatch_resume(timer);
    }
}

void tgtimer_delete (struct tgl_timer *t) {
    dispatch_source_t timer = (dispatch_source_t)(t);
    dispatch_suspend(timer);
    dispatch_set_context(timer, NULL);
}

void tgtimer_free (struct tgl_timer *t) {
    dispatch_source_t timer = (dispatch_source_t)(t);
    dispatch_source_cancel(timer);
    if (dispatch_get_context(timer) == NULL) {
        dispatch_resume(timer); // resume if suspended
    }
    dispatch_release(timer);
}

struct tgl_timer_methods tgtimer_timers = {
    .alloc = tgtimer_alloc,
    .insert = tgtimer_insert,
    .remove = tgtimer_delete,
    .free = tgtimer_free
};
