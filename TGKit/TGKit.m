
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import "TGKit.h"
#import "tgl.h"
#import "loop.h"


@implementation TGPeer
@end

@implementation TGMedia
@end

@implementation TGMessage
@end


@interface TGKit ()
@end


@implementation TGKit

id<TGKitDelegate> _delegate;
dispatch_queue_t _loop_queue;

- (instancetype)initWithDelegate:(id<TGKitDelegate>)delegate andKey:(NSString *)serverRsaKey {
    static TGKit *sharedInstance = nil;
    assert(sharedInstance == nil);  // multiple init called, only single instance allowed
    sharedInstance = [super init];
    NSLog(@"Init with key path: [%@]", serverRsaKey);
    _delegate = delegate;
    tgl_state.verbosity = 3;
    tgl_set_rsa_key([serverRsaKey cStringUsingEncoding:NSUTF8StringEncoding]);
    _loop_queue = dispatch_queue_create("tgkit-loop", DISPATCH_QUEUE_CONCURRENT);
    return sharedInstance;
}

- (void)run {
    dispatch_async(_loop_queue, ^{
        loop(&upd_cb);
    });
}

- (void)sendMessage:(NSString *)text toPeer:(int)peerId {
    NSLog(@"Send msg:[%@] to peer:[%d]", text, peerId);
    send_message_to_user_id(text.UTF8String, peerId);
}


#pragma mark - TGKit classes

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
    peer.printName = NSStringFromUTF8String(P->print_name);
    peer.flags = P->flags;
    switch (tgl_get_peer_type(peer_id)) {
        case TGL_PEER_USER:
            peer.userFirstName = NSStringFromUTF8String(P->user.first_name);
            peer.userLastName = NSStringFromUTF8String(P->user.last_name);
            peer.userRealFirstName = NSStringFromUTF8String(P->user.real_first_name);
            peer.userRealLastName = NSStringFromUTF8String(P->user.real_last_name);
            peer.userPhone = NSStringFromUTF8String(P->user.phone);
            if (P->user.access_hash) {
                peer.userAccessHash = 1;
            }
            break;
        case TGL_PEER_CHAT:
            peer.chatTitle = NSStringFromUTF8String(P->chat.title);
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


#pragma mark - C workflow

void did_create_secret_chat (void *extra, int success, struct tgl_secret_chat *E) {
    NSLog(@"did_create_secret_chat success:[%d]", success);
    tgl_do_send_message(E->id, extra, (int)(strlen(extra)), did_send_message, 0);
}

void did_get_user_info(void *callback_extra, int success, struct tgl_user *U) {
    if (!success) {
        NSLog(@"Error fetching user info");
    } else {
        NSLog(@"Create new secret chat [from user info]");
        tgl_do_create_secret_chat(U->id, did_create_secret_chat, callback_extra);
    }
}

void did_send_message(void *callback_extra, int success, struct tgl_message *M) {
    if (!success) {
        write_secret_chat_file();
    } else {
        NSLog(@"Message sent");
    }
}

void send_message_to_user_id(const char *text, int user_id) {
    tgl_peer_id_t user = TGL_MK_USER(user_id);
    int encr_chat_id = tgl_get_secret_chat_for_user(user);
    if (encr_chat_id == -1) {
        if (!tgl_peer_get(user)) {
            NSLog(@"Get user info");
            tgl_do_get_user_info(user, 0, did_get_user_info, &text);
        } else {
            NSLog(@"Create new secret chat");
            tgl_do_create_secret_chat(user, did_create_secret_chat, &text);
        }
    } else {
        NSLog(@"Found secret chat id [%d]", encr_chat_id);
        tgl_peer_id_t encr_chat = TGL_MK_ENCR_CHAT(encr_chat_id);
        tgl_do_send_message(encr_chat, text, (int)(strlen(text)), did_send_message, &user);
    }
}


#pragma mark - C callbacks

void print_message_gw(struct tgl_message *M) {
    NSLog(@"print_message_gw from [%d] to: [%d] text: [%@] service: [%d]", M->from_id.id, M->to_id.id, NSStringFromUTF8String(M->message), M->service);
    if (M->service) {
        log_service(M);
    }
    TGMessage *message = [[TGMessage alloc] init];
    static char s[30];
    snprintf(s, 30, "%lld", M->id);
    message.msgId = [NSString stringWithUTF8String:s];
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
            message.text = [NSString stringWithUTF8String:M->message];
        }
        if (M->media.type && M->media.type != tgl_message_media_none) {
            message.media = make_media(&M->media);
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate didReceiveNewMessage:message];
    });
}

void mark_read_upd(int num, struct tgl_message *list[]) {
    NSLog(@"mark_read_upd");
}

void type_notification_upd(struct tgl_user *U, enum tgl_typing_status status) {
    NSLog(@"type_notification_upd status:[%d]", status);
    NSLog(@"User [%@] id [%d] status is %@", NSStringFromUTF8String(U->print_name), tgl_get_peer_id(U->id), log_typing(status));
}

void type_in_chat_notification_upd(struct tgl_user *U, struct tgl_chat *C, enum tgl_typing_status status) {
    NSLog(@"type_in_chat_notification_upd status:[%d]", status);
    NSLog(@"User [%@] id [%d] status is %@ in chat [%@] id [%d]", NSStringFromUTF8String(U->print_name), tgl_get_peer_id(U->id), log_typing(status), NSStringFromUTF8String(C->title), tgl_get_peer_id(C->id));
}

void user_update_gw(struct tgl_user *U, unsigned flags) {
    NSLog(@"user_update_gw flags:[%d]", flags);
    log_updates("User", U->print_name, tgl_get_peer_id(U->id), flags);
}

void chat_update_gw(struct tgl_chat *U, unsigned flags) {
    NSLog(@"chat_update_gw flags:[%d]", flags);
    log_updates("Chat", U->title, tgl_get_peer_id(U->id), flags);
}

void secret_chat_update_gw(struct tgl_secret_chat *U, unsigned flags) {
    NSLog(@"secret_chat_update_gw flags:[%d]", flags);
    if ((flags & TGL_UPDATE_WORKING) || (flags & TGL_UPDATE_DELETED)) {
        write_secret_chat_file ();
    }
    if ((flags & TGL_UPDATE_REQUESTED))  {
        tgl_do_accept_encr_chat_request (U, 0, 0);
    }
    log_updates("Secret chat", U->print_name, tgl_get_peer_id(U->id), flags);
}

void our_id_gw(int our_id) {
    NSLog(@"our_id_gw id:[%d]", our_id);
}

void nslog_logprintf(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSLog(@"%@", [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:format] arguments:ap]);
    va_end (ap);
}

struct tgl_update_callback upd_cb = {
    .new_msg = print_message_gw,
    .marked_read = mark_read_upd,
    .logprintf = nslog_logprintf,
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


#pragma mark - C Config

int username_ok = 0;
int has_username(void) {
    return username_ok;
}

int sms_code_ok = 0;
int has_sms_code(void) {
    return sms_code_ok;
}

int first_name_ok = 0;
int has_first_name(void) {
    return first_name_ok;
}

int last_name_ok = 0;
int has_last_name(void) {
    return last_name_ok;
}

void set_default_username(const char* username) {
    _delegate.username = [NSString stringWithUTF8String:username];
}

const char *get_default_username(void) {
    username_ok = 0;
    if (_delegate.username) {
        return _delegate.username.UTF8String;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate getLoginUsernameWithCompletionBlock:^(NSString *text) {
            username_ok = 1;
            _delegate.username = text;
        }];
    });
    wait_loop(has_username);
    return _delegate.username.UTF8String;
}

const char *get_sms_code (void) {
    sms_code_ok = 0;
    __block NSString *code;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate getLoginCodeWithCompletionBlock:^(NSString *text) {
            sms_code_ok = 1;
            code = text;
        }];
    });
    wait_loop(has_sms_code);
    return code.UTF8String;
}

const char *get_first_name (void) {
    first_name_ok = 0;
    __block NSString *first_name;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate getSignupFirstNameWithCompletionBlock:^(NSString *text) {
            first_name_ok = 1;
            first_name = text;
        }];
    });
    wait_loop(has_first_name);
    return first_name.UTF8String;
}

const char *get_last_name (void) {
    last_name_ok = 0;
    __block NSString *last_name;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate getSignupLastNameWithCompletionBlock:^(NSString *text) {
            last_name_ok = 1;
            last_name = text;
        }];
    });
    wait_loop(has_last_name);
    return last_name.UTF8String;
}

const char *get_auth_key_filename (void) {
    return documentPathWithFilename(@"auth_file");
}

const char *get_state_filename (void) {
    return documentPathWithFilename(@"state_file");
}

const char *get_secret_chat_filename (void) {
    return documentPathWithFilename(@"secret");
}

const char *get_binlog_filename (void) {
    return documentPathWithFilename(@"binlog");
}

const char *get_download_directory (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return documentsPath.UTF8String;
}

struct tgl_config config = {
    .get_first_name = get_first_name,
    .get_last_name = get_last_name,
    .set_default_username = set_default_username,
    .get_default_username = get_default_username,
    .get_sms_code = get_sms_code,
    .get_auth_key_filename = get_auth_key_filename,
    .get_state_filename = get_state_filename,
    .get_secret_chat_filename = get_secret_chat_filename,
    .get_download_directory = get_download_directory,
    .get_binlog_filename = get_binlog_filename,
    .sync_from_start = 0,
    .wait_dialog_list = 0,
    .reset_authorization = 0,
};


#pragma mark - Helper functions

static inline NSString *NSStringFromUTF8String (const char *cString) {
    return cString ? [NSString stringWithUTF8String:cString] : nil;
}

static inline const char *documentPathWithFilename (NSString *filename) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:filename].UTF8String;
}


#pragma mark - Log functions

NSDictionary *peer_updates_dict() {
    static NSDictionary *_updateNames = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _updateNames = @{
            @(TGL_UPDATE_PHONE): @"phone",
            @(TGL_UPDATE_CONTACT): @"contact",
            @(TGL_UPDATE_PHOTO): @"photo",
            @(TGL_UPDATE_BLOCKED): @"blocked",
            @(TGL_UPDATE_REAL_NAME): @"name",
            @(TGL_UPDATE_NAME): @"contact_name",
            @(TGL_UPDATE_REQUESTED): @"status",
            @(TGL_UPDATE_WORKING): @"status",
            @(TGL_UPDATE_FLAGS): @"flags",
            @(TGL_UPDATE_TITLE): @"title",
            @(TGL_UPDATE_ADMIN): @"admin",
            @(TGL_UPDATE_MEMBERS): @"members",
            @(TGL_UPDATE_ACCESS_HASH): @"access_hash",
            @(TGL_UPDATE_USERNAME): @"username",
        };
    });
    return _updateNames;
}

NSArray *peer_updates_list (int flags) {
    NSDictionary *updateNames = peer_updates_dict();
    NSMutableArray *list = [NSMutableArray array];
    for (NSNumber *update in updateNames) {
        if (flags & update.intValue) {
            NSString *name = updateNames[update];
            [list addObject:name];
        }
    }
    return list.copy;
}

static inline void log_updates(const char *type, const char *name, int id, unsigned flags) {
    if (!(flags & TGL_UPDATE_CREATED)) {
        NSString *updates = @"deleted";
        if (!(flags & TGL_UPDATE_DELETED)) {
            updates = [@"updated " stringByAppendingString:[peer_updates_list(flags) componentsJoinedByString:@" "]];
        }
        NSLog(@"%s [%@] id [%d] %@", type, NSStringFromUTF8String(name), id, updates);
    }
}

static inline NSString *log_typing(enum tgl_typing_status status) {
    switch (status) {
        case tgl_typing_none:
            return @"doing nothing";
        case tgl_typing_typing:
            return @"typing";
        case tgl_typing_cancel:
            return @"deleting typed message";
        case tgl_typing_record_video:
            return @"recording video";
        case tgl_typing_upload_video:
            return @"uploading video";
        case tgl_typing_record_audio:
            return @"recording audio";
        case tgl_typing_upload_audio:
            return @"uploading audio";
        case tgl_typing_upload_photo:
            return @"uploading photo";
        case tgl_typing_upload_document:
            return @"uploading document";
        case tgl_typing_geo:
            return @"choosing location";
        case tgl_typing_choose_contact:
            return @"choosing contact";
        default:
            return @"undefined";
    }
}

static inline void log_service(struct tgl_message *M) {
    tgl_peer_t *to_peer = tgl_peer_get(M->to_id);
    tgl_peer_t *from_user = tgl_peer_get(M->from_id);
    NSString *to_name = tgl_get_peer_type(M->to_id) == TGL_PEER_CHAT ? NSStringFromUTF8String(to_peer->chat.title) : NSStringFromUTF8String(to_peer->print_name);
    NSString *from_name = NSStringFromUTF8String(from_user->print_name);
    NSString *action;
    switch (M->action.type) {
        case tgl_message_action_none: {
            action = @"None";
        } break;
        case tgl_message_action_geo_chat_create: {
            action = @"Created geo chat";
        } break;
        case tgl_message_action_geo_chat_checkin: {
            action = @"Checkin in geochat";
        } break;
        case tgl_message_action_chat_create: {
            action = [NSString stringWithFormat:@"created chat %@. %d users", NSStringFromUTF8String(M->action.title), M->action.user_num];
        } break;
        case tgl_message_action_chat_edit_title: {
            action = [NSString stringWithFormat:@"changed title to %@", NSStringFromUTF8String(M->action.new_title)];
        } break;
        case tgl_message_action_chat_edit_photo: {
            action = @"changed photo";
        } break;
        case tgl_message_action_chat_delete_photo: {
            action = @"deleted photo";
        } break;
        case tgl_message_action_chat_add_user: {
            tgl_peer_t *user = tgl_peer_get(tgl_set_peer_id(TGL_PEER_USER, M->action.user));
            action = [@"added user " stringByAppendingFormat:@"[%@] id: [%d]", NSStringFromUTF8String(user->print_name), M->action.user];
        } break;
        case tgl_message_action_chat_delete_user: {
            tgl_peer_t *user = tgl_peer_get(tgl_set_peer_id(TGL_PEER_USER, M->action.user));
            action = [@"deleted user " stringByAppendingFormat:@"[%@] id: [%d]", NSStringFromUTF8String(user->print_name), M->action.user];
        } break;
        case tgl_message_action_set_message_ttl: {
            action = [NSString stringWithFormat:@"set ttl to %d seconds. Unsupported yet" , M->action.ttl];
        } break;
        case tgl_message_action_read_messages: {
            action = [NSString stringWithFormat:@"%d messages marked read", M->action.read_cnt];
        } break;
        case tgl_message_action_delete_messages: {
            action = [NSString stringWithFormat:@"%d messages deleted", M->action.delete_cnt];
        } break;
        case tgl_message_action_screenshot_messages: {
            action = [NSString stringWithFormat:@"%d messages screenshoted", M->action.screenshot_cnt];
        } break;
        case tgl_message_action_flush_history: {
            action = @"cleared history";
        } break;
        case tgl_message_action_notify_layer: {
            action = [NSString stringWithFormat:@"updated layer to %d", M->action.layer];
        } break;
        case tgl_message_action_typing: {
            action = [NSString stringWithFormat:@"is %@", log_typing(M->action.typing)];
        } break;
        default:
            action = @"undefined";
    }
    NSLog(@"Service: [%@] id [%d] from: [%@] id [%d] action: %@", to_name, tgl_get_peer_id(M->to_id), from_name, tgl_get_peer_id(M->from_id), action);
}

@end

