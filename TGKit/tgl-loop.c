/*
    This file is part of telegram-cli.

    Telegram-cli is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    Telegram-cli is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this telegram-cli.  If not, see <http://www.gnu.org/licenses/>.

    Copyright Vitaly Valtman 2013-2014
    Copyright Paul Eipper 2014
*/

#include <assert.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

#include <event2/event.h>

#include "tgl-loop.h"
#include "tgl-binlog.h"
#include "tgl-net.h"
#include "tgl-timers.h"
#include "tgl-serialize.h"
#include "tgl-structures.h"
#include "tgl-inner.h"
#include "tgl.h"


// loop callbacks

struct tgl_dc *cur_a_dc;
int is_authorized (struct tgl_state *TLS) {
    return tgl_authorized_dc (TLS, cur_a_dc);
}

int all_authorized (struct tgl_state *TLS) {
    int i;
    for (i = 0; i <= TLS->max_dc_num; i++) if (TLS->DC_list[i]) {
        if (!tgl_authorized_dc (TLS, TLS->DC_list[i])) {
            return 0;
        }
    }
    return 1;
}

int should_register;
char *hash;
void sign_in_callback (struct tgl_state *TLS, void *extra, int success, int registered, const char *mhash) {
    if (!success) {
        vlogprintf(E_ERROR, "Can not send code");
        exit (1);
    }
    should_register = !registered;
    hash = strdup (mhash);
}

int signed_in_result;
void sign_in_result (struct tgl_state *TLS, void *extra, int success, struct tgl_user *U) {
    signed_in_result = success ? 1 : 2;
}

int signed_in (struct tgl_state *TLS) {
    return signed_in_result;
}

int sent_code (struct tgl_state *TLS) {
    return hash != 0;
}

int dc_signed_in (struct tgl_state *TLS) {
    return tgl_signed_dc (TLS, cur_a_dc);
}

void export_auth_callback (struct tgl_state *TLS, void *DC, int success) {
    if (!success) {
        vlogprintf (E_ERROR, "Can not export auth\n");
        exit (1);
    }
}

int d_got_ok;
void get_difference_callback (struct tgl_state *TLS, void *extra, int success) {
    assert (success);
    d_got_ok = 1;
}

int dgot (struct tgl_state *TLS) {
    return d_got_ok;
}

void dlist_cb (struct tgl_state *TLS, void *callback_extra, int success, int size, tgl_peer_id_t peers[], int last_msg_id[], int unread_count[])  {
    d_got_ok = 1;
}


// main loops

void net_loop (struct tgl_state *TLS, int flags, int (*is_end)(struct tgl_state *TLS)) {
    int last_get_state = (int)(time (0));
    while (!is_end || !is_end (TLS)) {
        event_base_loop (TLS->ev_base, EVLOOP_ONCE);
        if (time (0) - last_get_state > 3600) {
            tgl_do_lookup_state (TLS);
            last_get_state = (int)(time (0));
        }
    }
}

void wait_loop(struct tgl_state *TLS, int (*is_end)(struct tgl_state *TLS)) {
    net_loop (TLS, 0, is_end);
}

int main_loop (struct tgl_state *TLS) {
    net_loop (TLS, 1, 0);
    return 0;
}

int loop(struct tgl_state *TLS, struct tgl_update_callback *upd_cb) {
    tgl_set_callback (TLS, upd_cb);
    //TLS->temp_key_expire_time = 60;
    struct event_base *ev = event_base_new ();
    tgl_set_ev_base (TLS, ev);
    tgl_set_net_methods (TLS, &tgl_conn_methods);
    tgl_set_timer_methods (TLS, &tgl_libevent_timers);
    tgl_set_serialize_methods (TLS, &tgl_file_methods);
    tgl_set_download_directory (TLS, config.get_download_directory ());
    tgl_set_binlog_mode (TLS, config.binlog_mode);
    tgl_init (TLS);
    TLS->serialize_methods->load_auth (TLS);
    TLS->serialize_methods->load_state (TLS);
    TLS->serialize_methods->load_secret_chats (TLS);
    if (config.reset_authorization) {
        tgl_peer_t *P = tgl_peer_get (TLS, TGL_MK_USER (TLS->our_id));
        if (P && P->user.phone && config.reset_authorization == 1) {
            vlogprintf(E_NOTICE, "Try to login as %s", P->user.phone);
            config.set_default_username(P->user.phone);
        }
        bl_do_reset_authorization (TLS);
    }
    net_loop (TLS, 0, all_authorized);
    if (!tgl_signed_dc(TLS, TLS->DC_working)) {
        vlogprintf(E_NOTICE, "Need to login first");
        tgl_do_send_code(TLS, config.get_default_username (), sign_in_callback, 0);
        net_loop(TLS, 0, sent_code);
        vlogprintf (E_NOTICE, "%s\n", should_register ? "phone not registered" : "phone registered");
        if (!should_register) {
            vlogprintf(E_NOTICE, "Enter SMS code");
            const char *username = config.get_default_username ();
            while (1) {
                const char *sms_code = config.get_sms_code ();
                tgl_do_send_code_result (TLS, username, hash, sms_code, sign_in_result, 0);
                net_loop (TLS, 0, signed_in);
                if (signed_in_result == 1) {
                    break;
                }
                vlogprintf(E_WARNING, "Invalid code");
                signed_in_result = 0;
            }
        } else {
            vlogprintf(E_NOTICE, "User is not registered");
            const char *username = config.get_default_username ();
            const char *first_name = config.get_first_name ();
            const char *last_name = config.get_last_name ();
            while (1) {
                const char *sms_code = config.get_sms_code ();
                tgl_do_send_code_result_auth (TLS, username, hash, sms_code, first_name, last_name, sign_in_result, 0);
                net_loop (TLS, 0, signed_in);
                if (signed_in_result == 1) {
                    break;
                }
                vlogprintf(E_WARNING, "Invalid code");
                signed_in_result = 0;
            }
        }
    }
    for (int i = 0; i <= TLS->max_dc_num; i++) if (TLS->DC_list[i] && !tgl_signed_dc (TLS, TLS->DC_list[i])) {
        tgl_do_export_auth (TLS, i, export_auth_callback, (void*)(long)TLS->DC_list[i]);
        cur_a_dc = TLS->DC_list[i];
        net_loop (TLS, 0, dc_signed_in);
        assert (tgl_signed_dc (TLS, TLS->DC_list[i]));
    }
    TLS->serialize_methods->store_auth (TLS);
    tglm_send_all_unsent (TLS);
    tgl_do_get_difference (TLS, config.sync_from_start, get_difference_callback, 0);
    net_loop (TLS, 0, dgot);
    assert (!(TLS->locks & TGL_LOCK_DIFF));
    TLS->started = 1;
    if (config.wait_dialog_list) {
        d_got_ok = 0;
        tgl_do_get_dialog_list (TLS, dlist_cb, 0);
        net_loop (TLS, 0, dgot);
    }
    return main_loop(TLS);
}
