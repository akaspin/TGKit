//
//  loop.h
//  TGKit
//
//  Created by Paul Eipper on 24/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

#ifndef __TGKit__loop__
#define __TGKit__loop__

struct tgl_update_callback; // fwd declaration

struct tgl_config {
    int sync_from_start;
    int wait_dialog_list;
    int reset_authorization;
    const char *(*get_default_username) (void);
    const char *(*get_sms_code) (void);
    const char *(*get_auth_key_filename) (void);
    const char *(*get_state_filename) (void);
    const char *(*get_secret_chat_filename) (void);
    const char *(*get_download_directory) (void);
    const char *(*get_binlog_filename) (void);
    void (*set_default_username) (const char *username);
};

extern struct tgl_config config; // must be defined by caller

int loop(struct tgl_update_callback *upd_cb);
void wait_loop(int (*is_end)(void));

#endif /* defined(__TGKit__loop__) */
