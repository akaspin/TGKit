
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

- (void)didReceiveNewMessage:(TGMessage *)message;
- (void)getLoginUsernameWithCompletionBlock:(TGKitStringCompletionBlock)completion;
- (void)getLoginCodeWithCompletionBlock:(TGKitStringCompletionBlock)completion;
- (void)getSignupFirstNameWithCompletionBlock:(TGKitStringCompletionBlock)completion;
- (void)getSignupLastNameWithCompletionBlock:(TGKitStringCompletionBlock)completion;

@end


@protocol TGKitDataSource <NSObject>

@property (atomic, strong) NSString *phoneNumber;
@property (atomic, strong) NSString *firstName;
@property (atomic, strong) NSString *lastName;
@property (atomic, strong) NSString *exportCard;

- (void)getCardForUserId:(int)userId withCompletionBlock:(TGKitStringCompletionBlock)completion;

@end


@interface TGKit : NSObject

@property (nonatomic, assign) id<TGKitDelegate> delegate;
@property (nonatomic, assign) id<TGKitDataSource> dataSource;

- (instancetype)initWithApiKeyPath:(NSString *)serverRsaKey appId:(int)appId appHash:(NSString *)appHash;
- (void)start;
- (void)sendMessage:(NSString *)text toUserId:(int)userId;
- (void)exportCardWithCompletionBlock:(TGKitStringCompletionBlock)completion;

@end
