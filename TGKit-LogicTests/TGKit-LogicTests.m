//
//  TGKit_Tests.m
//  TGKit Tests
//
//  Created by Paul Eipper on 24/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

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
    TGKit *tg = [[TGKit alloc] initWithKey:keyPath];
    XCTAssert(YES, @"Pass");
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
