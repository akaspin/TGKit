//
//  TGKit.h
//  TGKit
//
//  Created by Paul Eipper on 21/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

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


@protocol TGKitDelegate <NSObject>

- (void)didGetNewMessage:(TGMessage *)message;

@end


@interface TGKit : NSObject <TGKitDelegate>

- (instancetype)initWithKey:(NSString *)serverRsaKey;

@end
