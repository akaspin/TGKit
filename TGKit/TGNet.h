
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import <Foundation/Foundation.h>

@protocol TGNetSocketDelegate;


@interface TGNetSocket : NSObject

@property (atomic, weak, readwrite) id<TGNetSocketDelegate> delegate;
@property (atomic, strong, readwrite) dispatch_queue_t delegateQueue;
@property (atomic, readonly) dispatch_queue_t socketQueue;

- (BOOL)connectToHost:(NSString *)host onPort:(uint16_t)port;
- (void)closeWithError:(NSError *)error;
- (void)dispatchSync:(dispatch_block_t)block;

@end


@protocol TGNetSocketDelegate <NSObject>

- (void)socket:(TGNetSocket *)socket canReadStream:(CFReadStreamRef)readStream;
- (void)socket:(TGNetSocket *)socket canWriteStream:(CFWriteStreamRef)writeStream;

@end


@interface TGNet : NSObject

@property (atomic, readonly) dispatch_queue_t netQueue;

+ (instancetype)sharedInstance;
- (TGNetSocket *)connectToHost:(NSString *)host onPort:(uint16_t)port;
- (void)disconnect;

@end
