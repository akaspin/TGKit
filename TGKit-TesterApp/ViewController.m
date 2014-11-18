
/* Any copyright in this file is dedicated to the Public Domain.
 * http://creativecommons.org/publicdomain/zero/1.0/ */

#import "ViewController.h"
#import "TGKit.h"

#define TG_APP_HASH @"844584f2b1fd2daecee726166dcc1ef8"
#define TG_APP_ID 10534


@interface ViewController ()

@property (nonatomic, strong) TGKitStringCompletionBlock alertCompletion;
@property (nonatomic, strong) TGKit *tg;

@end


@implementation ViewController

@synthesize phoneNumber;
@synthesize firstName;
@synthesize lastName;
@synthesize exportCard;

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *keyPath = [[NSBundle mainBundle] pathForResource:@"server" ofType:@"pub"];
    self.tg = [[TGKit alloc] initWithApiKeyPath:keyPath appId:TG_APP_ID appHash:TG_APP_HASH];
    self.tg.delegate = self;
    self.tg.dataSource = self;
    [self.tg start];
    NSLog(@"Running...");
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.tg exportCardWithCompletionBlock:^(NSString *card) {
        NSString *line = [NSString stringWithFormat:@"User card: %@\n---\n", card];
        self.messageView.text = [self.messageView.text stringByAppendingString:line];
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)sendButtonPressed:(id)sender {
    if (!self.userId.text.length || !self.messageInput.text.length) {
        return;
    }
    [self.tg sendMessage:self.messageInput.text toUserId:self.userId.text.intValue];
}

- (IBAction)doneEditing:(id)sender {
    [sender resignFirstResponder];
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
    if (message.isService || !message.text.length) {
        return;
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n---\n", message.isOut ? @">" : @"<", message.text];
    self.messageView.text = [self.messageView.text stringByAppendingString:line];
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

- (void)getSignupFirstNameWithCompletionBlock:(TGKitStringCompletionBlock)completion {
    self.alertCompletion = completion;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Sign Up" message:@"First name:" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alertView.tag = 3;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}

- (void)getSignupLastNameWithCompletionBlock:(TGKitStringCompletionBlock)completion {
    self.alertCompletion = completion;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Sign Up" message:@"Last name:" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alertView.tag = 4;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}


#pragma mark - TGKitDataSource

- (void)getCardForUserId:(int)userId withCompletionBlock:(TGKitStringCompletionBlock)completion {
    self.alertCompletion = completion;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"User Card" message:[NSString stringWithFormat:@"Enter card for user [%d]:", userId] delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alertView.tag = 5;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alertView show];
}

@end
