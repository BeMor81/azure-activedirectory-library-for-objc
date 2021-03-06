// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ADALBaseUITest.h"
#import "NSDictionary+ADALiOSUITests.h"

@implementation ADALBaseUITest

- (void)setUp
{
    [super setUp];
    
    self.continueAfterFailure = NO;
    
    self.testApp = [XCUIApplication new];
    [self.testApp launch];
    
    self.accountsProvider = [ADTestAccountsProvider new];
}

#pragma mark - Profiles

- (NSMutableDictionary *)fociConfig
{
    return [[self.accountsProvider testProfileOfType:ADTestProfileTypeFoci] mutableCopy];
}

- (NSMutableDictionary *)sovereignConfig
{
    return [[self.accountsProvider testProfileOfType:ADTestProfileTypeSovereign] mutableCopy];
}

- (NSMutableDictionary *)basicConfig
{
    return [[self.accountsProvider testProfileOfType:ADTestProfileTypeBasic] mutableCopy];
}

#pragma mark - Asserts

- (void)assertRefreshTokenInvalidated
{
    NSDictionary *result = [self resultDictionary];
    
    XCTAssertTrue([result[@"invalidated_refresh_token_count"] intValue] == 1);
}

- (void)assertAccessTokenExpired
{
    NSDictionary *result = [self resultDictionary];
    
    XCTAssertTrue([result[@"expired_access_token_count"] intValue] == 1);
}

- (void)assertAuthUIAppear
{
    XCUIElement *webView = self.testApp.otherElements[@"ADAL_SIGN_IN_WEBVIEW"].firstMatch;
    
    BOOL result = [webView waitForExistenceWithTimeout:2.0];
    
    XCTAssertTrue(result);
}

- (void)assertError:(NSString *)error
{
    NSDictionary *result = [self resultDictionary];
    
    XCTAssertNotEqual([result[@"error"] length], 0);
    NSString *errorDescription = result[@"error_description"];
    XCTAssertTrue([errorDescription containsString:@"error"]);
}

- (void)assertAccessTokenNotNil
{
    NSDictionary *result = [self resultDictionary];
    
    XCTAssertTrue([result[@"access_token"] length] > 0);
    XCTAssertEqual([result[@"error"] length], 0);
}

- (void)assertRefreshTokenNotNil
{
    NSDictionary *result = [self resultDictionary];
    
    XCTAssertTrue([result[@"refresh_token"] length] > 0);
}

#pragma mark - Actions

- (void)aadEnterEmail:(NSString *)email
{
    XCUIElement *emailTextField = self.testApp.textFields[@"Email or phone"];
    [self waitForElement:emailTextField];
    if ([email isEqualToString:emailTextField.value])
    {
        return;
    }
    
    [emailTextField pressForDuration:0.5f];
    
    // There is a bug when we test in iOS 11 when emailTextField.value return placeholder value
    // instead of empty string. In order to make it work we check that value of text field is not
    // equal to placeholder.
    // See here: https://forums.developer.apple.com/thread/86653
    if (![emailTextField.placeholderValue isEqualToString:emailTextField.value] && emailTextField.value)
    {
        [emailTextField selectAll:self.testApp];
    }
    [emailTextField typeText:email];
}

- (void)aadEnterEmail
{
    [self aadEnterEmail:[NSString stringWithFormat:@"%@\n", self.accountInfo.account]];
}

- (void)closeAuthUI
{
     [self.testApp.navigationBars[@"ADAuthenticationView"].buttons[@"Cancel"] tap];
}

- (void)closeResultView
{
    [self.testApp.buttons[@"Done"] tap];
}

- (void)invalidateRefreshToken:(NSString *)jsonString
{
    [self.testApp.buttons[@"Invalidate Refresh Token"] tap];
    [self.testApp.textViews[@"requestInfo"] tap];
    [self.testApp.textViews[@"requestInfo"] pasteText:jsonString application:self.testApp];
    [self.testApp.buttons[@"Go"] tap];
}

- (void)expireAccessToken:(NSString *)jsonString
{
    [self.testApp.buttons[@"Expire Access Token"] tap];
    [self.testApp.textViews[@"requestInfo"] tap];
    [self.testApp.textViews[@"requestInfo"] pasteText:jsonString application:self.testApp];
    [self.testApp.buttons[@"Go"] tap];
}

- (void)acquireToken:(NSString *)jsonString
{
    [self.testApp.buttons[@"Acquire Token"] tap];
    [self.testApp.textViews[@"requestInfo"] tap];
    [self.testApp.textViews[@"requestInfo"] pasteText:jsonString application:self.testApp];
    [self.testApp.buttons[@"Go"] tap];
}

- (void)acquireTokenSilent:(NSString *)jsonString
{
    [self.testApp.buttons[@"Acquire Token Silent"] tap];
    [self.testApp.textViews[@"requestInfo"] tap];
    [self.testApp.textViews[@"requestInfo"] pasteText:jsonString application:self.testApp];
    [self.testApp.buttons[@"Go"] tap];
}

- (void)clearCache
{
    [self.testApp.buttons[@"Clear Cache"] tap];
    [self.testApp.buttons[@"Done"] tap];
}

- (void)clearCookies
{
    [self.testApp.buttons[@"Clear Cookies"] tap];
    [self.testApp.buttons[@"Done"] tap];
}

#pragma mark - Helpers

- (NSString *)configParamsJsonString:(NSMutableDictionary *)config
                    additionalParams:(NSDictionary *)additionalParams
{
    [config addEntriesFromDictionary:additionalParams];
    
    return [config toJsonString];
}

- (NSString *)configParamsJsonString:(NSDictionary *)additionalParams
{
    return [self configParamsJsonString:self.baseConfigParams additionalParams:additionalParams];
}

- (NSDictionary *)resultDictionary
{
    XCUIElement *resultTextView = self.testApp.textViews[@"resultInfo"];
    [self waitForElement:resultTextView];
    
    return [NSJSONSerialization JSONObjectWithData:[resultTextView.value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

- (void)waitForElement:(id)object
{
    NSPredicate *existsPredicate = [NSPredicate predicateWithFormat:@"exists == 1"];
    [self expectationForPredicate:existsPredicate evaluatedWithObject:object handler:nil];
    [self waitForExpectationsWithTimeout:20.0f handler:nil];
}

@end
