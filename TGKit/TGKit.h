
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import <Foundation/Foundation.h>


@interface TGPeer : NSObject

@property int peerId;
@property NSString* type;
@property NSString* printName;
@property int flags;
// user
@property NSString *userFirstName;
@property NSString *userLastName;
@property NSString *userRealFirstName;
@property NSString *userRealLastName;
@property NSString *userPhone;
@property int userAccessHash;
// chat
@property NSString *chatTitle;
@property NSArray *chatMembers;
// encr_chat
@property TGPeer *encrChatPeer;

@end


@interface TGMedia : NSObject

@property NSString *type;
@property NSDictionary *data;

@end


@interface TGMessage : NSObject

@property NSString *msgId;
@property int flags;
@property TGPeer *fwdFrom;
@property int fwdDate;
@property TGPeer *from;
@property TGPeer *to;
@property BOOL isOut;
@property BOOL isUnread;
@property int date;
@property BOOL isService;
@property NSString *text;
@property TGMedia *media;

@end


typedef void (^TGKitStringCompletionBlock)(NSString *text);


@protocol TGKitDelegate <NSObject>

@property (atomic, strong) NSString *username;

- (void)didReceiveNewMessage:(TGMessage *)message;
- (void)getLoginUsernameWithCompletionBlock:(TGKitStringCompletionBlock)completion;
- (void)getLoginCodeWithCompletionBlock:(TGKitStringCompletionBlock)completion;

@end


@interface TGKit : NSObject

- (instancetype)initWithDelegate:(id<TGKitDelegate>)delegate andKey:(NSString *)serverRsaKey;
- (void)run;
- (void)sendMessage:(NSString *)text toPeer:(int)peerId;

@end
