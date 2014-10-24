//
//  ViewController.m
//  TGKit Tester
//
//  Created by Paul Eipper on 24/10/2014.
//  Copyright (c) 2014 nKey. All rights reserved.
//

#import "ViewController.h"
#import "TGKit.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *keyPath = [[NSBundle mainBundle] pathForResource:@"server" ofType:@"pub"];
    TGKit *tg = [[TGKit alloc] initWithKey:keyPath];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
