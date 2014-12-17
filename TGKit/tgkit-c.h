/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#ifndef __TGKit__tgkit_c__
#define __TGKit__tgkit_c__

#include "tgl.h"
#include <dispatch/dispatch.h>

struct tgl_config {
    // flags
    int binlog_mode;
    int sync_from_start;
    int wait_dialog_list;
    int reset_authorization;
    // callbacks
    const char *(*get_first_name) (void);
    const char *(*get_last_name) (void);
    const char *(*get_default_username) (void);
    const char *(*get_sms_code) (void);
    const char *(*get_download_directory) (void);
    const char *(*get_binlog_filename) (void);
    void (*set_default_username) (const char *username);
};

void start (struct tgl_state *TLS, struct tgl_config config);
void stop (void);

void wait_semaphore (dispatch_semaphore_t semaphore, void (^block)(void));
void wait_condition (struct tgl_state *TLS, int (*is_done)(struct tgl_state *TLS), void (^block)(void));

void dispatch_when_connected (struct tgl_state *TLS, void (^block)(void));

#endif /* defined(__TGKit__tgkit_c__) */
