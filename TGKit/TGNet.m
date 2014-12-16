
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import "TGNet.h"
#import "tgnet-c.h"
#import <CFNetwork/CFNetwork.h>

#import "tgl.h"
#import "tgl-net-inner.h"

#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>

#define SOCKET_NULL -1
#define MAX_CONNECTIONS 100


@interface TGNetThread : NSThread

+ (void)startThreadIfNeeded;
+ (void)stopThreadIfNeeded;
+ (void)scheduleCFStreams:(TGNetSocket *)socket;
+ (void)unscheduleCFStreams:(TGNetSocket *)socket;

@end


@interface TGNetSocket () <TGNetSocketDelegate> {

@public
    // C callbacks
    socket_callback_t read_callback;
    socket_callback_t write_callback;
    void *read_extra;
    void *write_extra;
    bool write_requested;
#define MAX_TIMERS 2
    dispatch_source_t timers[MAX_TIMERS + 1];
    int timers_count;
}

@end


#pragma mark - TGNet

@interface TGNet () {
    dispatch_queue_t netQueue;
    void *IsOnNetQueueKey;
}

@property (atomic, strong) NSMutableArray *connections;

@end


@implementation TGNet

@synthesize netQueue = netQueue;

+ (instancetype)sharedInstance {
    static TGNet *shared_tgnet = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        shared_tgnet = [[TGNet alloc] init];
        
    });
    return shared_tgnet;
}

- (instancetype)init {
    if (!(self = [super init])) {
        return self;
    }
    self.connections = [NSMutableArray arrayWithCapacity:MAX_CONNECTIONS];
    netQueue = dispatch_queue_create("tgkit-net", DISPATCH_QUEUE_SERIAL);
    IsOnNetQueueKey = &IsOnNetQueueKey;
    void *nonNullUnusedPointer = (__bridge void *)self;
    dispatch_queue_set_specific(netQueue, IsOnNetQueueKey, nonNullUnusedPointer, NULL);
    return self;
}

- (TGNetSocket *)connectToHost:(NSString *)host onPort:(uint16_t)port {
    if (self.connections.count > MAX_CONNECTIONS) {
        return nil;
    }
    TGNetSocket *socket = [[TGNetSocket alloc] init];
    socket.delegate = socket;
    socket.delegateQueue = netQueue;
    __block BOOL result = NO;
    dispatch_sync(socket.socketQueue, ^{
        @autoreleasepool {
            result = [socket connectToHost:host onPort:port];
        }
    });
    if (result) {
        [self.connections addObject:socket];
        return socket;
    }
    return nil;
}

- (void)close:(TGNetSocket *)socket {
    dispatch_sync(socket.socketQueue, ^{
        @autoreleasepool {
            [socket closeWithError:nil];
        }
    });
    [self.connections removeObject:socket];
}

- (void)disconnect {
    [self.connections enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(TGNetSocket *socket, NSUInteger idx, BOOL *stop) {
        dispatch_sync(socket.socketQueue, ^{
            @autoreleasepool {
                [socket closeWithError:nil];
            }
        });
    }];
    [self.connections removeAllObjects];
}

@end


#pragma mark - TGNetSocket

@interface TGNetSocket () {
    int socketFD;
    
    dispatch_queue_t socketQueue;
    void *IsOnSocketQueueKey;
    
    CFStreamClientContext streamContext;
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    
    BOOL hasAddedStreamsToRunLoop;
}

@property (atomic, readonly) CFReadStreamRef readStream;
@property (atomic, readonly) CFWriteStreamRef writeStream;

@end


@implementation TGNetSocket

@synthesize socketQueue = socketQueue;
@synthesize readStream = readStream;
@synthesize writeStream = writeStream;

- (instancetype)init {
    if (!(self = [super init])) {
        return self;
    }
    socketFD = SOCKET_NULL;
    socketQueue = dispatch_queue_create("tgkit-net-socket", DISPATCH_QUEUE_SERIAL);
    IsOnSocketQueueKey = &IsOnSocketQueueKey;
    void *nonNullUnusedPointer = (__bridge void *)self;
    dispatch_queue_set_specific(socketQueue, IsOnSocketQueueKey, nonNullUnusedPointer, NULL);
    return self;
}

- (void)dispatchSync:(dispatch_block_t)block {
    if (dispatch_get_specific(IsOnSocketQueueKey)) {
        block();
    } else {
        dispatch_sync(socketQueue, block);
    }
}

- (BOOL)connectToHost:(NSString *)host onPort:(uint16_t)port {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD == SOCKET_NULL) {
        return NO;
    }
    if (socketFD > MAX_CONNECTIONS) {
        [self closeWithError:nil];
        return NO;
    }
    int flags = -1;
    setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &flags, sizeof(flags));
    setsockopt(socketFD, SOL_SOCKET, SO_KEEPALIVE, &flags, sizeof(flags));
    setsockopt(socketFD, IPPROTO_TCP, TCP_NODELAY, &flags, sizeof(flags));
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &flags, sizeof(flags));
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons (port);
    addr.sin_addr.s_addr = inet_addr(host.UTF8String);
    if (connect(socketFD, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        if (errno != EINPROGRESS) {
            NSLog(@"Can not connect to %@:%d", host, port);
            [self closeWithError:nil];
            return NO;
        }
    }
    if (![self createReadAndWriteStream]) {
        [self closeWithError:nil];
        NSLog(@"Error: createReadAndWriteStream");
        return NO;
    }
    if (![self registerForStreamCallbacks]) {
        [self closeWithError:nil];
        NSLog(@"Error: registerForStreamCallbacks");
        return NO;
    }
    if (![self addStreamsToRunLoop]) {
        [self closeWithError:nil];
        NSLog(@"Error: addStreamsToRunLoop");
        return NO;
    }
    if (![self openStreams]) {
        [self closeWithError:nil];
        NSLog(@"Error: openStreams");
        return NO;
    }
    fcntl(socketFD, F_SETFL, O_NONBLOCK);
    return YES;
}

- (BOOL)createReadAndWriteStream {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    if (readStream || writeStream) {
        return YES;
    }
    if (socketFD == SOCKET_NULL) {
        return NO;
    }
    CFStreamCreatePairWithSocket(NULL, (CFSocketNativeHandle)socketFD, &readStream, &writeStream);
    if (readStream) {
        CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    }
    if (writeStream) {
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    }
    if ((readStream == NULL) || (writeStream == NULL)) {
        NSLog(@"Unable to create read and write stream");
        if (readStream) {
            CFReadStreamClose(readStream);
            CFRelease(readStream);
            readStream = NULL;
        }
        if (writeStream) {
            CFWriteStreamClose(writeStream);
            CFRelease(writeStream);
            writeStream = NULL;
        }
        return NO;
    }
    return YES;
}

- (BOOL)registerForStreamCallbacks {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    NSAssert((readStream != NULL && writeStream != NULL), @"Read/Write stream is null");
    streamContext.version = 0;
    streamContext.info = (__bridge void *)(self);
    streamContext.retain = nil;
    streamContext.release = nil;
    streamContext.copyDescription = nil;
    CFOptionFlags readStreamEvents = kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered;
    if (!CFReadStreamSetClient(readStream, readStreamEvents, &CFReadStreamCallback, &streamContext)) {
        return NO;
    }
    CFOptionFlags writeStreamEvents = kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered;
    if (!CFWriteStreamSetClient(writeStream, writeStreamEvents, &CFWriteStreamCallback, &streamContext)) {
        return NO;
    }
    return YES;
}

- (BOOL)addStreamsToRunLoop {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    NSAssert((readStream != NULL && writeStream != NULL), @"Read/Write stream is null");
    if (!hasAddedStreamsToRunLoop) {
        [TGNetThread startThreadIfNeeded];
        [TGNetThread scheduleCFStreams:self];
        hasAddedStreamsToRunLoop = YES;
    }
    return YES;
}

- (void)removeStreamsFromRunLoop {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    NSAssert((readStream != NULL && writeStream != NULL), @"Read/Write stream is null");
    if (hasAddedStreamsToRunLoop) {
        [TGNetThread unscheduleCFStreams:self];
        [TGNetThread stopThreadIfNeeded];
        hasAddedStreamsToRunLoop = NO;
    }
}

- (BOOL)openStreams {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    NSAssert((readStream != NULL && writeStream != NULL), @"Read/Write stream is null");
    CFStreamStatus readStatus = CFReadStreamGetStatus(readStream);
    CFStreamStatus writeStatus = CFWriteStreamGetStatus(writeStream);
    if ((readStatus == kCFStreamStatusNotOpen) || (writeStatus == kCFStreamStatusNotOpen)) {
        BOOL r1 = CFReadStreamOpen(readStream);
        BOOL r2 = CFWriteStreamOpen(writeStream);
        if (!r1 || !r2) {
            return NO;
        }
    }
    return YES;
}

- (void)closeWithError:(NSError *)error {
    NSAssert(dispatch_get_specific(IsOnSocketQueueKey), @"Must be dispatched on socketQueue");
    if (readStream || writeStream) {
        [self removeStreamsFromRunLoop];
        if (readStream) {
            CFReadStreamSetClient(readStream, kCFStreamEventNone, NULL, NULL);
            CFReadStreamClose(readStream);
            CFRelease(readStream);
            readStream = NULL;
        }
        if (writeStream) {
            CFWriteStreamSetClient(writeStream, kCFStreamEventNone, NULL, NULL);
            CFWriteStreamClose(writeStream);
            CFRelease(writeStream);
            writeStream = NULL;
        }
    }
    if (socketFD != SOCKET_NULL) {
        close(socketFD);
        socketFD = SOCKET_NULL;
    }
}

- (void)readData {
    dispatch_async(self.delegateQueue, ^{
        [self.delegate socket:self canReadStream:readStream];
    });
}

- (void)writeData {
    dispatch_async(self.delegateQueue, ^{
        [self.delegate socket:self canWriteStream:writeStream];
    });
}

#pragma mark - CFStream callbacks

static void CFReadStreamCallback (CFReadStreamRef stream, CFStreamEventType type, void *pInfo) {
    TGNetSocket *socket = (__bridge TGNetSocket *)pInfo;
    switch (type) {
        case kCFStreamEventHasBytesAvailable: {
            dispatch_async(socket->socketQueue, ^{
                @autoreleasepool {
                    if (socket->readStream != stream) {
                        return;
                    }
                    [socket readData];
                }
            });
            break;
        }
        default: {
            if (socket->readStream != stream) {
                return;
            }
            NSError *error = (__bridge_transfer  NSError *)CFReadStreamCopyError(stream);
            dispatch_async(socket->socketQueue, ^{
                [socket closeWithError:error];
            });
        }
    }
}

static void CFWriteStreamCallback (CFWriteStreamRef stream, CFStreamEventType type, void *pInfo) {
    TGNetSocket *socket = (__bridge TGNetSocket *)pInfo;
    switch (type) {
        case kCFStreamEventCanAcceptBytes: {
            dispatch_async(socket->socketQueue, ^{
                @autoreleasepool {
                    if (socket->writeStream != stream) {
                        return;
                    }
                    [socket writeData];
                }
            });
            break;
        }
        default: {
            if (socket->writeStream != stream) {
                return;
            }
            NSError *error = (__bridge_transfer  NSError *)CFWriteStreamCopyError(stream);
            dispatch_async(socket->socketQueue, ^{
                [socket closeWithError:error];
            });
        }
    }
}

#pragma mark - TGNetSocketDelegate

static long read_stream_wrapper(void *_socket, uint8_t *buffer, long buffer_size) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    __block CFIndex result;
    [socket dispatchSync:^{
        result = CFReadStreamRead(socket.readStream, buffer, buffer_size);
    }];
    return result;
}

static long write_stream_wrapper(void *_socket, uint8_t *buffer, long buffer_size) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    __block CFIndex result;
    [socket dispatchSync:^{
        result = CFWriteStreamWrite(socket.writeStream, buffer, buffer_size);
    }];
    return result;
}

- (void)socket:(TGNetSocket *)socket canReadStream:(CFReadStreamRef)stream {
    if (read_callback) {
        read_callback(read_stream_wrapper, (__bridge void *)(socket), read_extra);
    }
}

- (void)socket:(TGNetSocket *)socket canWriteStream:(CFWriteStreamRef)stream {
    if (write_callback && write_requested) {
        self->write_requested = false;
        write_callback(write_stream_wrapper, (__bridge void *)(socket), write_extra);
    }
}

@end


#pragma mark - TGNetThread

@implementation TGNetThread

static NSThread *cfstreamThread;
static uint64_t cfstreamThreadRetainCount;
static dispatch_queue_t cfstreamThreadSetupQueue;

+ (void)startThreadIfNeeded {
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        cfstreamThreadRetainCount = 0;
        cfstreamThreadSetupQueue = dispatch_queue_create("tgkit-net-threadsetup", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_sync(cfstreamThreadSetupQueue, ^{
        @autoreleasepool {
            if (++cfstreamThreadRetainCount == 1) {
                cfstreamThread = [[TGNetThread alloc] init];
                [cfstreamThread start];
            }
        }
    });
}

+ (void)stopThreadIfNeeded {
    int delayInSeconds = 30;  // time before closing the thread, to allow reuse
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(when, cfstreamThreadSetupQueue, ^{
        @autoreleasepool {
            if (cfstreamThreadRetainCount == 0) {
                NSLog(@"Logic error concerning cfstreamThread start / stop");
                return;
            }
            if (--cfstreamThreadRetainCount == 0) {
                [cfstreamThread cancel];
                [cfstreamThread performSelector:@selector(ignore:) onThread:cfstreamThread withObject:nil waitUntilDone:NO];
                cfstreamThread = nil;
            }
        }
    });
}

+ (void)scheduleCFStreams:(TGNetSocket *)socket {
    [TGNetThread performSelector:@selector(threadScheduleCFStreams:) onThread:cfstreamThread withObject:socket waitUntilDone:YES];
}

+ (void)unscheduleCFStreams:(TGNetSocket *)socket {
    [TGNetThread performSelector:@selector(threadUnscheduleCFStreams:) onThread:cfstreamThread withObject:socket waitUntilDone:YES];
}


- (void)main {
    @autoreleasepool {
        self.name = @"TGNetThread";
        NSLog(@"%@ started", self.name);
        // setup an infinite run loop
        [NSTimer scheduledTimerWithTimeInterval:[[NSDate distantFuture] timeIntervalSinceNow] target:self selector:@selector(ignore:) userInfo:nil repeats:YES];
        NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
        while (!self.isCancelled && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
        }
        NSLog(@"%@ stopped", self.name);
    };
}

- (void)ignore:(id)_ {
    
}

#pragma mark - Threaded methods

+ (void)threadScheduleCFStreams:(TGNetSocket *)socket {
    NSAssert([NSThread currentThread] == cfstreamThread, @"Invoked on wrong thread");
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    if (socket.readStream) {
        CFReadStreamScheduleWithRunLoop(socket.readStream, runLoop, kCFRunLoopDefaultMode);
    }
    if (socket.writeStream) {
        CFWriteStreamScheduleWithRunLoop(socket.writeStream, runLoop, kCFRunLoopDefaultMode);
    }
}

+ (void)threadUnscheduleCFStreams:(TGNetSocket *)socket {
    NSAssert([NSThread currentThread] == cfstreamThread, @"Invoked on wrong thread");
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    if (socket.readStream) {
        CFReadStreamUnscheduleFromRunLoop(socket.readStream, runLoop, kCFRunLoopDefaultMode);
    }
    if (socket.writeStream) {
        CFWriteStreamUnscheduleFromRunLoop(socket.writeStream, runLoop, kCFRunLoopDefaultMode);
    }
}

@end


#pragma mark - Helper functions

static inline NSString *NSStringFromUTF8String (const char *cString) {
    return cString ? [NSString stringWithUTF8String:cString] : nil;
}


#pragma mark - C interface

const void * const tgnet_instance (void) {
    return (__bridge const void *)(TGNet.sharedInstance);
}

void tgnet_read_callback(const void *_socket, socket_callback_t read_cb, void *extra) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        socket->read_callback = read_cb;
        socket->read_extra = extra;
    }];
}

void tgnet_write_callback(const void *_socket, socket_callback_t write_cb, void *extra) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        socket->write_callback = write_cb;
        socket->write_extra = extra;
        socket->write_requested = false;
    }];
}

void tgnet_request_write(const void *_socket) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        socket->write_requested = true;
        if (CFWriteStreamCanAcceptBytes(socket.writeStream)) {
            [socket writeData];
        }
    }];
}

const void *tgnet_connect (const char *host, uint16_t port) {
    return (__bridge const void *)([TGNet.sharedInstance connectToHost:NSStringFromUTF8String(host) onPort:port]);
}

void tgnet_close (const void *_socket) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        socket->read_callback = NULL;
        socket->read_extra = NULL;
        socket->write_callback = NULL;
        socket->write_extra = NULL;
        socket->write_requested = NULL;
        for (int timer_index = 0; timer_index < MAX_TIMERS + 1; ++timer_index) {
            dispatch_source_t timer = socket->timers[timer_index];
            if (timer) {
                dispatch_source_set_cancel_handler(timer, NULL);
                dispatch_source_cancel(timer);
            }
            socket->timers[timer_index] = NULL;
        }
        socket->timers_count = 0;
    }];
    [TGNet.sharedInstance close:socket];
}

void tgnet_disconnect_all (void) {
    return [TGNet.sharedInstance disconnect];
}

int tgnet_timer_new (const void *_socket, socket_timer_t timer_cb, void *extra) {
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    __block int timer_index = -1;
    [socket dispatchSync:^{
        if (socket->timers_count >= MAX_TIMERS) {
            return;
        }
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, socket.socketQueue);
        if (!timer) {
            return;
        }
        dispatch_source_set_event_handler(timer, ^{
            dispatch_source_cancel(timer);
            timer_cb(extra);
        });
        socket->timers[++(socket->timers_count)] = timer;
        timer_index = socket->timers_count;
        dispatch_source_set_cancel_handler(timer, ^{
            socket->timers[timer_index] = NULL;
            socket->timers_count--;
        });
    }];
    return timer_index;
}

void tgnet_timer_add (const void *_socket, int timer_index, long seconds) {
    if (timer_index <= 0 || timer_index >= MAX_TIMERS) {
        return;
    }
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        dispatch_source_t timer = socket->timers[timer_index];
        if (timer && !dispatch_get_context(timer)) {
            dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), (uint64_t)(seconds) * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
            dispatch_set_context(timer, (__bridge void *)(timer));
            dispatch_resume(timer);
        }
    }];
}

void tgnet_timer_del (const void *_socket, int timer_index) {
    if (timer_index <= 0 || timer_index >= MAX_TIMERS) {
        return;
    }
    TGNetSocket *socket = (__bridge TGNetSocket *)(_socket);
    [socket dispatchSync:^{
        dispatch_source_t timer = socket->timers[timer_index];
        if (timer) {
            dispatch_source_cancel(timer);
        }
    }];
}

void tgnet_set_response_queue(void *_queue) {
    TGNet.sharedInstance.responseQueue = (__bridge dispatch_queue_t)(_queue);
}

void tgnet_dispatch_response(struct connection *c, int op, int len) {
    dispatch_sync(TGNet.sharedInstance.responseQueue, ^{
        c->methods->execute(c->TLS, c, op, len);
    });
}
