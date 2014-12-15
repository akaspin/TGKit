/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#ifndef TGKit_tgtimer_c_h
#define TGKit_tgtimer_c_h

#include "tgl.h"
#include <dispatch/dispatch.h>

extern struct tgl_timer_methods tgtimer_timers;

void tgtimer_target_queue (dispatch_queue_t target_queue);

#endif
