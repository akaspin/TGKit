
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import "TGTimer.h"
#include "tgtimer-c.h"
#include "tgl-inner.h"
#include "tgl.h"


@interface TGTimer ()

@end


@implementation TGTimer

+ (instancetype)sharedInstance {
    static TGTimer *shared_tgtimer = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        shared_tgtimer = [[TGTimer alloc] init];
        
    });
    return shared_tgtimer;
}

@end


struct tgl_timer *tgtimer_alloc (struct tgl_state *TLS, void (*cb)(struct tgl_state *TLS, void *arg), void *arg) {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (!timer) {
        return NULL;
    }
    dispatch_source_set_event_handler(timer, ^{
        vlogprintf (E_DEBUG, "Timer callback %d\n", cb);
        dispatch_source_cancel(timer);
        cb(TLS, arg);
    });
    dispatch_source_set_cancel_handler(timer, ^{
        dispatch_set_context(timer, NULL);
    });
    return (__bridge void *)timer;
}

void tgtimer_insert (struct tgl_timer *t, double seconds) {
    dispatch_source_t timer = (__bridge dispatch_source_t)(t);
    uint64_t nanosecs = seconds < 0 ? 0 : seconds * NSEC_PER_SEC;
    dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), nanosecs, 1ull * NSEC_PER_SEC);
    dispatch_set_context(timer, (__bridge void *)(timer));
    dispatch_resume(timer);
}

void tgtimer_delete (struct tgl_timer *t) {
    dispatch_source_t timer = (__bridge dispatch_source_t)(t);
    dispatch_source_cancel(timer);
}

void tgtimer_free (struct tgl_timer *t) {
}

struct tgl_timer_methods tgtimer_timers = {
    .alloc = tgtimer_alloc,
    .insert = tgtimer_insert,
    .remove = tgtimer_delete,
    .free = tgtimer_free
};
