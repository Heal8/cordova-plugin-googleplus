#import "AppDelegate.h"
#import "objc/runtime.h"
#import "GooglePlus.h"

@implementation GooglePlus

- (void)pluginInitialize
{
    NSLog(@"GooglePlus pluginInitialize");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:CDVPluginHandleOpenURLNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLWithAppSourceAndAnnotation:) name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void)handleOpenURL:(NSNotification*)notification
{
    // no need to handle this handler, we dont have a sourceApplication here, which is required by GIDSignIn handleURL
}

- (void)handleOpenURLWithAppSourceAndAnnotation:(NSNotification*)notification
{
    NSMutableDictionary * options = [notification object];

    NSURL* url = options[@"url"];

    NSString* possibleReversedClientId = [url.absoluteString componentsSeparatedByString:@":"].firstObject;

    if ([possibleReversedClientId isEqualToString:self.getreversedClientId]) {
        [[GIDSignIn sharedInstance] handleURL:url];
    }
}

// If this returns false, you better not call the login function because of likely app rejection by Apple,
// see https://code.google.com/p/google-plus-platform/issues/detail?id=900
// Update: should be fine since we use the GoogleSignIn framework instead of the GooglePlus framework
- (void) isAvailable:(CDVInvokedUrlCommand*)command {
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];

    NSString* scopesString = options[@"scopes"];
    NSString* serverClientId = options[@"webClientId"];
    NSString *loginHint = options[@"loginHint"];
    BOOL offline = [options[@"offline"] boolValue];
    NSString* hostedDomain = options[@"hostedDomain"];

    // Build GIDConfiguration (replaces v5 property-based configuration)
    GIDConfiguration *config = [[GIDConfiguration alloc]
        initWithClientID:clientId
        serverClientID:(serverClientId != nil && offline) ? serverClientId : nil
        hostedDomain:hostedDomain
        openIDRealm:nil];
    GIDSignIn.sharedInstance.configuration = config;

    // Build additional scopes array
    NSArray *additionalScopes = nil;
    if (scopesString != nil) {
        additionalScopes = [scopesString componentsSeparatedByString:@" "];
    }

    // Perform sign-in with completion handler (replaces v5 delegate pattern)
    [GIDSignIn.sharedInstance signInWithPresentingViewController:self.viewController
                                                           hint:loginHint
                                               additionalScopes:additionalScopes
                                                     completion:^(GIDSignInResult * _Nullable signInResult, NSError * _Nullable error) {
        if (error) {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        } else {
            [self handleSignInResult:signInResult.user serverAuthCode:signInResult.serverAuthCode];
        }
    }];
}

- (void) trySilentLogin:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;

    [GIDSignIn.sharedInstance restorePreviousSignInWithCompletion:^(GIDGoogleUser * _Nullable user, NSError * _Nullable error) {
        if (error) {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        } else {
            [self handleSignInResult:user serverAuthCode:nil];
        }
    }];
}

- (void) handleSignInResult:(GIDGoogleUser *)user serverAuthCode:(NSString *)serverAuthCode {
    NSString *email = user.profile.email;
    NSString *idToken = user.idToken.tokenString ? : @"";
    NSString *accessToken = user.accessToken.tokenString ? : @"";
    NSString *refreshToken = user.refreshToken.tokenString ? : @"";
    NSString *userId = user.userID;
    NSString *authCode = serverAuthCode != nil ? serverAuthCode : @"";
    NSURL *imageUrl = [user.profile imageURLWithDimension:120];
    NSDictionary *result = @{
                   @"email"           : email ? : [NSNull null],
                   @"idToken"         : idToken,
                   @"serverAuthCode"  : authCode,
                   @"accessToken"     : accessToken,
                   @"refreshToken"    : refreshToken,
                   @"userId"          : userId ? : [NSNull null],
                   @"displayName"     : user.profile.name       ? : [NSNull null],
                   @"givenName"       : user.profile.givenName  ? : [NSNull null],
                   @"familyName"      : user.profile.familyName ? : [NSNull null],
                   @"imageUrl"        : imageUrl ? imageUrl.absoluteString : [NSNull null],
                   };

    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
}

- (NSString*) reverseUrlScheme:(NSString*)scheme {
  NSArray* originalArray = [scheme componentsSeparatedByString:@"."];
  NSArray* reversedArray = [[originalArray reverseObjectEnumerator] allObjects];
  NSString* reversedString = [reversedArray componentsJoinedByString:@"."];
  return reversedString;
}

- (NSString*) getreversedClientId {
  NSArray* URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];

  if (URLTypes != nil) {
    for (NSDictionary* dict in URLTypes) {
      NSString *urlName = dict[@"CFBundleURLName"];
      if ([urlName isEqualToString:@"REVERSED_CLIENT_ID"]) {
        NSArray* URLSchemes = dict[@"CFBundleURLSchemes"];
        if (URLSchemes != nil) {
          return URLSchemes[0];
        }
      }
    }
  }
  return nil;
}

- (void) logout:(CDVInvokedUrlCommand*)command {
  [[GIDSignIn sharedInstance] signOut];
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
  [[GIDSignIn sharedInstance] disconnectWithCompletion:^(NSError * _Nullable error) {
      if (error) {
          CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      } else {
          CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      }
  }];
}

- (void) share_unused:(CDVInvokedUrlCommand*)command {
  // for a rainy day.. see for a (limited) example https://github.com/vleango/GooglePlus-PhoneGap-iOS/blob/master/src/ios/GPlus.m
}

@end
