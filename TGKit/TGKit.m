//
//  TGKit.m
//  TGKit
//
//  Created by Paul Eipper on 21/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

#import "TGKit.h"
#import "tgl.h"


// loop

#import <event2/event.h>

struct event *term_ev = 0;
void net_loop (int flags, int (*is_end)(void)) {
    int last_get_state = (int)(time (0));
    while (!is_end || !is_end ()) {
        event_base_loop (tgl_state.ev_base, EVLOOP_ONCE);
        if (time (0) - last_get_state > 3600) {
            tgl_do_lookup_state ();
            last_get_state = (int)(time (0));
        }
    }
    if (term_ev) {
        event_free (term_ev);
        term_ev = 0;
    }
}

// missing functions

char *get_downloads_directory (void) {
    return "";
}

char *get_binlog_file_name (void) {
    return "";
}


// classes

@implementation TGPeer
@end

@implementation TGMedia
@end

@implementation TGMessage
@end


@interface TGKit ()

@end


@implementation TGKit

TGKit *delegate; // global for now, need to add userdata to callbacks

- (instancetype)initWithKey:(NSString *)serverRsaKey {
    self = [super init];
    NSLog(@"Init with key path: [%@]", serverRsaKey);
    delegate = self;
    tgl_set_rsa_key([serverRsaKey cStringUsingEncoding:NSUTF8StringEncoding]);
    tgl_set_callback(&upd_cb);
    tgl_init();
    const char *default_username = "+554899170146";
    const char *sms_code = "62933";
    if (!tgl_signed_dc(tgl_state.DC_working)) {
        NSLog(@"Need to login first");
        tgl_do_send_code(default_username, sign_in_callback, 0);
        net_loop(0, sent_code);
        if (!should_register) {
            NSLog(@"Enter SMS code");
            while (true) {
                if (tgl_do_send_code_result (default_username, hash, sms_code, sign_in_result, 0) >= 0) {
                    break;
                }
                break;
            }
        }
        net_loop (0, signed_in);
    }
    return self;
}

- (void)didGetNewMessage:(TGMessage *)message {
    NSLog(@"%@", message.text);
}

// C event callbacks

int signed_in_ok;
void sign_in_result (void *extra, int success, struct tgl_user *U) {
    if (!success) {
        NSLog(@"Can not login");
        exit(1);
    }
    signed_in_ok = 1;
}

int signed_in (void) {
    return signed_in_ok;
}

int should_register;
char *hash;
void sign_in_callback (void *extra, int success, int registered, const char *mhash) {
    if (!success) {
        NSLog(@"Can not send code");
        exit(1);
    }
    should_register = !registered;
    hash = strdup (mhash);
}

int sent_code (void) {
    return hash != 0;
}


// C handlers

TGPeer *make_peer(tgl_peer_id_t peer_id, tgl_peer_t *P) {
    TGPeer *peer = [[TGPeer alloc] init];
    peer.peerId = tgl_get_peer_id(peer_id);
    switch (tgl_get_peer_type(peer_id)) {
        case TGL_PEER_USER:
            peer.type = @"user";
            break;
        case TGL_PEER_CHAT:
            peer.type = @"chat";
            break;
        case TGL_PEER_ENCR_CHAT:
            peer.type = @"encr_chat";
            break;
        default:
            break;
    }
    if (!P || !(P->flags & FLAG_CREATED)) {
        peer.printName = [NSString stringWithFormat:@"%@#%d", peer.type, peer.peerId];
        return peer;
    }
    peer.printName = [NSString stringWithCString:P->print_name encoding:NSUTF8StringEncoding];
    peer.flags = P->flags;
    switch (tgl_get_peer_type(peer_id)) {
        case TGL_PEER_USER:
            peer.userFirstName = [NSString stringWithCString:P->user.first_name encoding:NSUTF8StringEncoding];
            peer.userLastName = [NSString stringWithCString:P->user.last_name encoding:NSUTF8StringEncoding];
            peer.userRealFirstName = [NSString stringWithCString:P->user.real_first_name encoding:NSUTF8StringEncoding];
            peer.userRealLastName = [NSString stringWithCString:P->user.real_last_name encoding:NSUTF8StringEncoding];
            peer.userPhone = [NSString stringWithCString:P->user.phone encoding:NSUTF8StringEncoding];
            if (P->user.access_hash) {
                peer.userAccessHash = 1;
            }
            break;
        case TGL_PEER_CHAT:
            peer.chatTitle = [NSString stringWithCString:P->chat.title encoding:NSUTF8StringEncoding];
            if (P->chat.user_list) {
                NSMutableArray *members = [NSMutableArray arrayWithCapacity:P->chat.users_num];
                for (int i = 0; i < P->chat.users_num; i++) {
                    tgl_peer_id_t member_id = TGL_MK_USER (P->chat.user_list[i].user_id);
                    [members addObject:make_peer(member_id, tgl_peer_get(member_id))];
                }
                peer.chatMembers = members;
            }
            break;
        case TGL_PEER_ENCR_CHAT:
            peer.encrChatPeer = make_peer(TGL_MK_USER (P->encr_chat.user_id), tgl_peer_get (TGL_MK_USER (P->encr_chat.user_id)));
            break;
        default:
            break;
    }
    return peer;
}

TGMedia *make_media(struct tgl_message_media *M) {
    TGMedia *media = [[TGMedia alloc] init];
    switch (M->type) {
        case tgl_message_media_photo:
        case tgl_message_media_photo_encr:
            media.type = @"photo";
            break;
        case tgl_message_media_video:
        case tgl_message_media_video_encr:
            media.type = @"video";
            break;
        case tgl_message_media_audio:
        case tgl_message_media_audio_encr:
            media.type = @"audio";
            break;
        case tgl_message_media_document:
        case tgl_message_media_document_encr:
            media.type = @"document";
            break;
        case tgl_message_media_unsupported:
            media.type = @"unsupported";
            break;
        case tgl_message_media_geo:
            media.type = @"geo";
            media.data = @{@"longitude": @(M->geo.longitude),
                           @"latitude": @(M->geo.latitude)};
            break;
        case tgl_message_media_contact:
            media.type = @"contact";
            media.data = @{@"phone": @(M->phone),
                           @"first_name": @(M->first_name),
                           @"last_name": @(M->last_name),
                           @"user_id": @(M->user_id)};
            break;
        default:
            break;
    }
    return media;
}

// callbacks

void print_message_gw(struct tgl_message *M) {
    NSLog(@"print_message_gw");
    TGMessage *message = [[TGMessage alloc] init];
    static char s[30];
    snprintf(s, 30, "%lld", M->id);
    message.msgId = [NSString stringWithCString:s encoding:NSUTF8StringEncoding];
    message.flags = M->flags;
    message.isOut = M->out;
    message.isUnread = M->unread;
    message.date = M->date;
    message.isService = M->service;
    if (tgl_get_peer_type(M->fwd_from_id)) {
        message.fwdDate = M->fwd_date;
        message.fwdFrom = make_peer(M->fwd_from_id, tgl_peer_get(M->fwd_from_id));
    }
    message.from = make_peer(M->from_id, tgl_peer_get(M->from_id));
    message.to = make_peer(M->to_id, tgl_peer_get (M->to_id));
    if (!M->service) {
        if (M->message_len && M->message) {
            message.text = [NSString stringWithCString:M->message encoding:NSUTF8StringEncoding];
        }
        if (M->media.type && M->media.type != tgl_message_media_none) {
            message.media = make_media(&M->media);
        }
    }
    [delegate didGetNewMessage:message];
}

void mark_read_upd(int num, struct tgl_message *list[]) {
    NSLog(@"mark_read_upd");
}

void type_notification_upd(struct tgl_user *U, enum tgl_typing_status status) {
    NSLog(@"type_notification_upd");
}

void type_in_chat_notification_upd(struct tgl_user *U, struct tgl_chat *C, enum tgl_typing_status status) {
    NSLog(@"type_in_chat_notification_upd");
}

void user_update_gw(struct tgl_user *U, unsigned flags) {
    NSLog(@"user_update_gw");
}

void chat_update_gw(struct tgl_chat *U, unsigned flags) {
    NSLog(@"chat_update_gw");
}

void secret_chat_update_gw(struct tgl_secret_chat *U, unsigned flags) {
    NSLog(@"secret_chat_update_gw");
}

void our_id_gw(int id) {
    NSLog(@"our_id_gw");
}

void logprintf(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSLog([NSString stringWithCString:format encoding:NSUTF8StringEncoding], ap);
    va_end (ap);
}

struct tgl_update_callback upd_cb = {
    .new_msg = print_message_gw,
    .marked_read = mark_read_upd,
    .logprintf = logprintf,
    .type_notification = type_notification_upd,
    .type_in_chat_notification = type_in_chat_notification_upd,
    .type_in_secret_chat_notification = 0,
    .status_notification = 0,
    .user_registered = 0,
    .user_activated = 0,
    .new_authorization = 0,
    .user_update = user_update_gw,
    .chat_update = chat_update_gw,
    .secret_chat_update = secret_chat_update_gw,
    .msg_receive = print_message_gw,
    .our_id = our_id_gw
};


@end

