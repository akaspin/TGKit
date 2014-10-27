//
//  TGKit.m
//  TGKit
//
//  Created by Paul Eipper on 21/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

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

@property NSString *username;

@end


@implementation TGKit

TGKit *delegate; // global for now, need to add userdata to callbacks
dispatch_queue_t loop_queue;

- (instancetype)initWithKey:(NSString *)serverRsaKey {
    self = [super init];
    NSLog(@"Init with key path: [%@]", serverRsaKey);
    delegate = self;
    tgl_state.verbosity = 3;
    tgl_set_rsa_key([serverRsaKey cStringUsingEncoding:NSUTF8StringEncoding]);
    loop_queue = dispatch_queue_create("tgkit-loop", DISPATCH_QUEUE_CONCURRENT);
    return self;
}

- (void)run {
    dispatch_async(loop_queue, ^{
        loop(&upd_cb);
    });
}

- (void)didGetNewMessage:(TGMessage *)message {
    NSLog(@"%@", message.text);
}


#pragma mark - UIAlertViewDelegate

- (void)alertViewCancel:(UIAlertView *)alertView {
    if (alertView.tag == 1) {
        username_ok = 1;
    } else if (alertView.tag == 2){
        sms_code_ok = 1;
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 1) {
        username_ok = 1;
    } else if (alertView.tag == 2){
        sms_code_ok = 1;
    }
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

#pragma mark - C callbacks

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

void set_default_username(const char* username) {
    delegate.username = [NSString stringWithUTF8String:username];
}

const char *get_default_username(void) {
    username_ok = 0;
    if (delegate.username) {
        return delegate.username.UTF8String;
    }
    __block UITextField *textField;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Telephone" message:@"Telephone number (with '+' sign):" delegate:delegate cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
        alertView.tag = 1;
        alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
        textField = [alertView textFieldAtIndex:0];
        [alertView show];
    });
    wait_loop(has_username);
    delegate.username = textField.text;
    return textField.text.UTF8String;
}

const char *get_sms_code (void) {
    sms_code_ok = 0;
    __block UITextField *textField;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Activation" message:@"Code from SMS:" delegate:delegate cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
        alertView.tag = 2;
        alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
        textField = [alertView textFieldAtIndex:0];
        [alertView show];
    });
    wait_loop(has_sms_code);
    return textField.text.UTF8String;
}

const char *get_auth_key_filename (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filePath = [documentsPath stringByAppendingPathComponent:@"auth_file"];
    return filePath.UTF8String;
}

const char *get_state_filename (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filePath = [documentsPath stringByAppendingPathComponent:@"state_file"];
    return filePath.UTF8String;
}

const char *get_secret_chat_filename (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filePath = [documentsPath stringByAppendingPathComponent:@"secret"];
    return filePath.UTF8String;
}

const char *get_binlog_filename (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filePath = [documentsPath stringByAppendingPathComponent:@"binlog"];
    return filePath.UTF8String;
}

const char *get_download_directory (void) {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return documentsPath.UTF8String;
}

struct tgl_config config = {
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

@end

