
/* Any copyright in this file is dedicated to the Public Domain.
 * http://creativecommons.org/publicdomain/zero/1.0/ */

#import "ViewController.h"
#import "TGKit.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *keyPath = [[NSBundle mainBundle] pathForResource:@"server" ofType:@"pub"];
    TGKit *tg = [[TGKit alloc] initWithKey:keyPath];
    [tg run];
    NSLog(@"Running...");
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
