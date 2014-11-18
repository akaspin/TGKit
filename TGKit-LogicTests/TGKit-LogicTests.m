
/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "TGKit.h"

@interface TGKitLogicTests : XCTestCase

@end

@implementation TGKitLogicTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    NSString *keyPath = [[NSBundle bundleForClass:self.class] pathForResource:@"server" ofType:@"pub"];
    TGKit *tg = [[TGKit alloc] initWithApiKeyPath:keyPath];
    [tg start];
    XCTAssert(YES, @"Pass");
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
