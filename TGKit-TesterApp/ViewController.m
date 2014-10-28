
/* Any copyright in this file is dedicated to the Public Domain.
 * http://creativecommons.org/publicdomain/zero/1.0/ */

#import "ViewController.h"
#import "TGKit.h"


@interface ViewController ()

@property (nonatomic, strong) TGKitStringCompletionBlock alertCompletion;

@end


@implementation ViewController

@synthesize username;

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *keyPath = [[NSBundle mainBundle] pathForResource:@"server" ofType:@"pub"];
    TGKit *tg = [[TGKit alloc] initWithDelegate:self andKey:keyPath];
    [tg run];
    NSLog(@"Running...");
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - UIAlertViewDelegate

- (void)alertViewCancel:(UIAlertView *)alertView {
    UITextField *textField = [alertView textFieldAtIndex:0];
    self.alertCompletion(textField.text);
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    UITextField *textField = [alertView textFieldAtIndex:0];
    self.alertCompletion(textField.text);
}


#pragma mark - TGKitDelegate

- (void)didReceiveNewMessage:(TGMessage *)message {
    NSLog(@"%@", message.text);
}

- (void)getLoginUsernameWithCompletionBlock:(TGKitStringCompletionBlock)completion {
    self.alertCompletion = completion;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Telephone" message:@"Telephone number (with '+' sign):" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alertView.tag = 1;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}

- (void)getLoginCodeWithCompletionBlock:(TGKitStringCompletionBlock)completion {
    self.alertCompletion = completion;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Activation" message:@"Code from SMS:" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alertView.tag = 2;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}

@end
