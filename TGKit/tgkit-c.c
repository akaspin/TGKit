/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#include "tgkit-c.h"
#include "tgtimer-c.h"
#include "tgnet-c.h"

#include <dispatch/dispatch.h>

#include "tgl.h"
#include "tgl-net.h"
#include "tgl-inner.h"
#include "tgl-binlog.h"
#include "tgl-serialize.h"
#include "tgl-structures.h"

static bool running;
static int should_register;
static char *hash;
static int signed_in_result;
static struct tgl_dc *cur_a_dc;
static void *main_queue_key;
static void *wait_queue_key;
static dispatch_queue_t main_queue;
static dispatch_queue_t wait_queue;
static dispatch_semaphore_t send_code_wait;
static dispatch_semaphore_t sign_in_wait;
static dispatch_semaphore_t difference_wait;


#pragma mark - Forward declarations

void loop (struct tgl_state *TLS, struct tgl_config config);
void do_login (struct tgl_state *TLS, struct tgl_config config);
void do_register (struct tgl_state *TLS, struct tgl_config config);

int all_authorized (struct tgl_state *TLS);
int dc_signed_in (struct tgl_state *TLS);

void sign_in_callback (struct tgl_state *TLS, void *extra, int success, int registered, const char *mhash);
void sign_in_result (struct tgl_state *TLS, void *extra, int success, struct tgl_user *U);
void export_auth_callback (struct tgl_state *TLS, void *DC, int success);
void get_difference_callback (struct tgl_state *TLS, void *extra, int success);
void dlist_cb (struct tgl_state *TLS, void *callback_extra, int success, int size, tgl_peer_id_t peers[], int last_msg_id[], int unread_count[]);


#pragma mark - Functions

static void init (struct tgl_state *TLS, struct tgl_config config) {
    main_queue = dispatch_queue_create("tgkit-main", DISPATCH_QUEUE_SERIAL);
    wait_queue = dispatch_queue_create("tgkit-loop-wait", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_set_specific(main_queue, &main_queue_key, NULL, NULL);
    dispatch_queue_set_specific(wait_queue, &wait_queue_key, NULL, NULL);
    send_code_wait = dispatch_semaphore_create(0);
    sign_in_wait = dispatch_semaphore_create(0);
    difference_wait = dispatch_semaphore_create(0);
    tgtimer_target_queue(main_queue);
    tgnet_set_response_queue(main_queue);
    tgl_set_net_methods(TLS, &tgl_conn_methods);
    tgl_set_timer_methods(TLS, &tgtimer_timers);
    tgl_set_serialize_methods(TLS, &tgl_file_methods);
    tgl_set_download_directory(TLS, config.get_download_directory ());
    tgl_set_binlog_mode(TLS, config.binlog_mode);
    tgl_init (TLS);
    TLS->serialize_methods->load_auth(TLS);
    TLS->serialize_methods->load_state(TLS);
    TLS->serialize_methods->load_secret_chats(TLS);
}

static int has_started (struct tgl_state *TLS) {
    return TLS->started;
}

void start (struct tgl_state *TLS, struct tgl_config config) {
    if (running) {
        return;
    }
    init(TLS, config);
    running = true;
    dispatch_source_t main_loop = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, wait_queue);
    dispatch_source_set_timer(main_loop, DISPATCH_TIME_NOW, 3600ull * NSEC_PER_SEC, 3600ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(main_loop, ^{
        vlogprintf(E_NOTICE, "main loop");
        if (running) {
            dispatch_async(main_queue, ^{
                tgl_do_lookup_state(TLS);
            });
        } else {
            dispatch_source_cancel(main_loop);
        }
    });
    dispatch_resume(main_loop);
    dispatch_async(main_queue, ^{
        loop(TLS, config);
    });
}

void dispatch_when_connected (struct tgl_state *TLS, void (^block)(void)) {
    if (TLS->started) {
        block();
    } else {
        wait_condition(TLS, has_started, block);
    }
}

void stop (void) {
    dispatch_sync(main_queue, ^{
        running = false;
    });
}

void wait_semaphore (dispatch_semaphore_t semaphore, void (^block)(void)) {
    if (block) {
        dispatch_async(wait_queue, ^{
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            dispatch_async(main_queue, block);
        });
    } else {
        dispatch_sync(wait_queue, ^{
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        });
    }
}

void wait_condition (struct tgl_state *TLS, int (*is_done)(struct tgl_state *TLS), void (^block)(void)) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, wait_queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        vlogprintf(E_DEBUG, "condition timer loop");
        if (is_done(TLS)) {
            dispatch_source_cancel(timer);
            dispatch_semaphore_signal(semaphore);
        }
    });
    dispatch_source_set_cancel_handler(timer, ^{
        vlogprintf(E_DEBUG, "condition timer end");
    });
    dispatch_resume(timer);
    wait_semaphore(semaphore, block);
}

void loop (struct tgl_state *TLS, struct tgl_config config) {
    if (config.reset_authorization) {
        tgl_peer_t *P = tgl_peer_get(TLS, TGL_MK_USER (TLS->our_id));
        if (P && P->user.phone && config.reset_authorization == 1) {
            vlogprintf(E_NOTICE, "Try to login as %s", P->user.phone);
            config.set_default_username(P->user.phone);
        }
        bl_do_reset_authorization(TLS);
    }
    wait_condition(TLS, all_authorized, NULL);
    if (!tgl_signed_dc(TLS, TLS->DC_working)) {
        vlogprintf(E_NOTICE, "Need to login first");
        tgl_do_send_code(TLS, config.get_default_username(), sign_in_callback, 0);
        wait_semaphore(send_code_wait, NULL);
        vlogprintf(E_NOTICE, "%s\n", should_register ? "phone not registered" : "phone registered");
        if (!should_register) {
            vlogprintf(E_NOTICE, "Enter SMS code");
            do_login(TLS, config);
        } else {
            vlogprintf(E_NOTICE, "User is not registered");
            do_register(TLS, config);
        }
    }
    for (int i = 0; i <= TLS->max_dc_num; i++) {
        if (TLS->DC_list[i] && !tgl_signed_dc(TLS, TLS->DC_list[i])) {
            tgl_do_export_auth(TLS, i, export_auth_callback, (void*)(long)TLS->DC_list[i]);
            cur_a_dc = TLS->DC_list[i];
            wait_condition(TLS, dc_signed_in, NULL);
            assert(tgl_signed_dc(TLS, TLS->DC_list[i]));
        }
    }
    TLS->serialize_methods->store_auth(TLS);
    tglm_send_all_unsent(TLS);
    tgl_do_get_difference(TLS, config.sync_from_start, get_difference_callback, 0);
    wait_semaphore(difference_wait, NULL);
    assert (!(TLS->locks & TGL_LOCK_DIFF));
    TLS->started = 1;
    if (config.wait_dialog_list) {
        tgl_do_get_dialog_list(TLS, dlist_cb, 0);
        wait_semaphore(difference_wait, NULL);
    }
}

void do_login (struct tgl_state *TLS, struct tgl_config config) {
    const char *username = config.get_default_username();
    while (1) {
        const char *sms_code = config.get_sms_code();
        tgl_do_send_code_result(TLS, username, hash, sms_code, sign_in_result, 0);
        wait_semaphore(sign_in_wait, NULL);
        if (signed_in_result == 1) {
            break;
        }
        vlogprintf(E_WARNING, "Invalid code");
        signed_in_result = 0;
    }
}

void do_register (struct tgl_state *TLS, struct tgl_config config) {
    const char *username = config.get_default_username();
    const char *first_name = config.get_first_name();
    const char *last_name = config.get_last_name();
    while (1) {
        const char *sms_code = config.get_sms_code();
        tgl_do_send_code_result_auth(TLS, username, hash, sms_code, first_name, last_name, sign_in_result, 0);
        wait_semaphore(sign_in_wait, NULL);
        if (signed_in_result == 1) {
            break;
        }
        vlogprintf(E_WARNING, "Invalid code");
        signed_in_result = 0;
    }
}


#pragma mark - Conditions

int all_authorized (struct tgl_state *TLS) {
    for (int i = 0; i <= TLS->max_dc_num; i++) {
        if (TLS->DC_list[i]) {
            if (!tgl_authorized_dc(TLS, TLS->DC_list[i])) {
                return 0;
            }
        }
    }
    return 1;
}

int dc_signed_in (struct tgl_state *TLS) {
    return tgl_signed_dc (TLS, cur_a_dc);
}


#pragma mark - Callbacks

void sign_in_callback (struct tgl_state *TLS, void *extra, int success, int registered, const char *mhash) {
    if (!success) {
        vlogprintf(E_ERROR, "Can not send code");
        stop();
    }
    should_register = !registered;
    hash = strdup(mhash);
    dispatch_semaphore_signal(send_code_wait);
}

void sign_in_result (struct tgl_state *TLS, void *extra, int success, struct tgl_user *U) {
    signed_in_result = success ? 1 : 2;
    dispatch_semaphore_signal(sign_in_wait);
}

void export_auth_callback (struct tgl_state *TLS, void *DC, int success) {
    if (!success) {
        vlogprintf (E_ERROR, "Can not export auth\n");
        stop();
    }
}

void get_difference_callback (struct tgl_state *TLS, void *extra, int success) {
    assert(success);
    dispatch_semaphore_signal(difference_wait);
}

void dlist_cb (struct tgl_state *TLS, void *callback_extra, int success, int size, tgl_peer_id_t peers[], int last_msg_id[], int unread_count[])  {
    dispatch_semaphore_signal(difference_wait);
}
