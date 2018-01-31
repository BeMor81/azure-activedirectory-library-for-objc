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

#import "ADAL_Internal.h"
#import "ADURLProtocol.h"
#import "ADLogger.h"
#import "ADNTLMHandler.h"
#import "ADCustomHeaderHandler.h"
#import "MSIDTelemetryUIEvent.h"
#import "MSIDTelemetryEventStrings.h"
#import "ADURLSessionDemux.h"
#import "ADAuthorityUtils.h"

static NSMutableDictionary *s_handlers      = nil;
static NSString *s_endURL                   = nil;
static MSIDTelemetryUIEvent *s_telemetryEvent = nil;

static NSString *s_kADURLProtocolPropertyKey  = @"ADURLProtocol";

static NSUUID *_reqCorrelationId(NSURLRequest* request)
{
    NSString *uuidString = [NSURLProtocol propertyForKey:@"correlationId" inRequest:request];
    
    return [[NSUUID alloc] initWithUUIDString:uuidString];
}

@interface ADURLProtocol()

@property NSUUID *correlationId;

@end

@implementation ADURLProtocol


+ (void)registerHandler:(id)handler
             authMethod:(NSString *)authMethod
{
    if (!handler || !authMethod)
    {
        return;
    }
    
    authMethod = [authMethod lowercaseString];
    
    @synchronized(self)
    {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            s_handlers = [NSMutableDictionary new];
        });
        
        [s_handlers setValue:handler forKey:authMethod];
    }
}

+ (BOOL)registerProtocol:(NSString *)endURL
          telemetryEvent:(MSIDTelemetryUIEvent *)telemetryEvent
{
    if (s_endURL!=endURL)
    {
        s_endURL = endURL.lowercaseString;
    }
    s_telemetryEvent = telemetryEvent;
    return [NSURLProtocol registerClass:self];
}

+ (void)unregisterProtocol
{
    [NSURLProtocol unregisterClass:self];
    s_endURL = nil;
    s_telemetryEvent = nil;
    
    @synchronized(self)
    {
        for (NSString *key in s_handlers)
        {
            Class<ADAuthMethodHandler> handler = [s_handlers objectForKey:key];
            [handler resetHandler];
        }
    }
}

+ (void)addContext:(id<MSIDRequestContext>)context
               toRequest:(NSMutableURLRequest *)request
{
    [ADURLProtocol addCorrelationId:context.correlationId toRequest:request];
}

+ (void)addCorrelationId:(NSUUID *)correlationId
               toRequest:(NSMutableURLRequest *)request
{
    if (!correlationId)
    {
        return;
    }
    
    // We can not save NSUUID, because it is not a valid plist type.
    // See here list of allowed types: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/PropertyLists/AboutPropertyLists/AboutPropertyLists.html#//apple_ref/doc/uid/20001010-46719
    [NSURLProtocol setProperty:correlationId.UUIDString forKey:@"correlationId" inRequest:request];
}

+ (ADURLSessionDemux *)sharedDemux
{
    static dispatch_once_t sOnceToken;
    static ADURLSessionDemux * sDemux;
    dispatch_once(&sOnceToken, ^{
        NSURLSessionConfiguration *config;
        
        config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.protocolClasses = @[ self ];
        
        sDemux = [[ADURLSessionDemux alloc] initWithConfiguration:config delegateQueue:nil];
    });
    return sDemux;
}

#pragma mark - Overrides
+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    // If we've already handled this request, don't pick it up again
    if ([NSURLProtocol propertyForKey:s_kADURLProtocolPropertyKey inRequest:request])
    {
        return NO;
    }
    
    //TODO: Experiment with filtering of the URL to ensure that this class intercepts only
    //ADAL initiated webview traffic, INCLUDING redirects. This may have issues, if requests are
    //made from javascript code, instead of full page redirection. As such, I am intercepting
    //all traffic while authorization webview session is displayed for now.
    if ( [[request.URL.scheme lowercaseString] isEqualToString:@"https"])
    {
        MSID_LOG_VERBOSE_CORR(_reqCorrelationId(request), @"+[ADURLProtocol canInitWithRequest:] handling host - host: %@", [ADAuthorityUtils isKnownHost:request.URL] ? [request.URL host] : @"unknown host");
        MSID_LOG_VERBOSE_CORR_PII(_reqCorrelationId(request), @"+[ADURLProtocol canInitWithRequest:] handling host - host: %@", [request.URL host]);
        
        //This class needs to handle only TLS. The check below is needed to avoid infinite recursion between starting and checking
        //for initialization
        if (![NSURLProtocol propertyForKey:s_kADURLProtocolPropertyKey inRequest:request])
        {
            return YES;
        }
    }
    
    MSID_LOG_VERBOSE_CORR(_reqCorrelationId(request), @"+[ADURLProtocol canInitWithRequest:] ignoring handling of host - host: %@", [ADAuthorityUtils isKnownHost:request.URL] ? [request.URL host] : @"unknown host");
    MSID_LOG_VERBOSE_CORR_PII(_reqCorrelationId(request), @"+[ADURLProtocol canInitWithRequest:] ignoring handling of host - host: %@", [request.URL host]);
    
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    MSID_LOG_VERBOSE_CORR(_reqCorrelationId(request), @"%@ - host: %@", @"+[ADURLProtocol canonicalRequestForRequest:]", [ADAuthorityUtils isKnownHost:request.URL] ? [request.URL host] : @"unknown host");
    MSID_LOG_VERBOSE_CORR_PII(_reqCorrelationId(request), @"%@ - host: %@", @"+[ADURLProtocol canonicalRequestForRequest:]", [request.URL host]);
    
    return request;
}

- (void)startLoading
{
    NSUUID *correlationId = _reqCorrelationId(self.request);
    if (correlationId)
    {
        _correlationId = correlationId;
    }
    
    MSID_LOG_VERBOSE_CORR(correlationId, @"%@ - host: %@", @"-[ADURLProtocol startLoading]", [ADAuthorityUtils isKnownHost:self.request.URL] ? [self.request.URL host] : @"unknown host");
    MSID_LOG_VERBOSE_CORR_PII(correlationId, @"%@ - host: %@", @"-[ADURLProtocol startLoading]", [self.request.URL host]);
    
    NSMutableURLRequest* request = [self.request mutableCopy];
     [ADCustomHeaderHandler applyCustomHeadersTo:request];
    
    // Make sure the correlation ID propogates through the requests
    if (!correlationId && _correlationId)
    {
        [ADURLProtocol addCorrelationId:correlationId toRequest:request];
    }
    
    [NSURLProtocol setProperty:@YES forKey:s_kADURLProtocolPropertyKey inRequest:request];
    
    _dataTask = [[[self class] sharedDemux] dataTaskWithRequest:request delegate:self];
    [_dataTask resume];
}

- (void)stopLoading
{
    MSID_LOG_VERBOSE_CORR(_reqCorrelationId(self.request), @"%@ - host: %@", @"-[ADURLProtocol stopLoading]", [ADAuthorityUtils isKnownHost:self.request.URL] ? [self.request.URL host] : @"unknown host");
    MSID_LOG_VERBOSE_CORR_PII(_reqCorrelationId(self.request), @"%@ - host: %@", @"-[ADURLProtocol stopLoading]", [self.request.URL host]);
    
    [_dataTask cancel];
    _dataTask = nil;
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
    (void)session;
    
    if ([request.URL.scheme.lowercaseString isEqualToString:@"http"])
    {
        if ([request.URL.absoluteString.lowercaseString hasPrefix:s_endURL])
        {
            // In this case we want to create an NSURLError so we can intercept the URL in the webview
            // delegate, while still forcing the connection to cancel. This error is the same one the
            // OS sends if it's unable to connect to the host
            [task cancel];
            NSError *failingError = [NSError errorWithDomain:NSURLErrorDomain
                                                        code:-1003
                                                    userInfo:@{ NSURLErrorFailingURLErrorKey : request.URL }];
            [self.client URLProtocol:self didFailWithError:failingError];
        }
        completionHandler(nil);
        return;
    }
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    
    [ADCustomHeaderHandler applyCustomHeadersTo:mutableRequest];
    [ADURLProtocol addCorrelationId:_correlationId toRequest:mutableRequest];
    
    if (!response)
    {
        completionHandler(mutableRequest);
        return;
    }
    
    // If we don't have this line in the redirectResponse case then we get a HTTP too many redirects
    // error.
    [NSURLProtocol removePropertyForKey:s_kADURLProtocolPropertyKey inRequest:mutableRequest];

    [self.client URLProtocol:self wasRedirectedToRequest:mutableRequest redirectResponse:response];
    
    // If we don't cancel out the connection in the redirectResponse case then we will end up
    // with duplicate connections
    
    // Here are the comments from Apple's CustomHTTPProtocol demo code:
    // https://developer.apple.com/library/ios/samplecode/CustomHTTPProtocol/Introduction/Intro.html
    
    // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
    // the load of the redirect.
    
    // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled,
    // which specificallys traps and ignores the error.
    
    [task cancel];
    [self.client URLProtocol:self
            didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                                 code:NSUserCancelledError
                                             userInfo:nil]];
    
    completionHandler(nil);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(ChallengeCompletionHandler)completionHandler
{
    NSString *authMethod = [challenge.protectionSpace.authenticationMethod lowercaseString];
    
    MSID_LOG_VERBOSE_CORR(_correlationId,
                          @"%@ - %@. Previous challenge failure count: %ld",
                          @"session:task:didReceiveChallenge:completionHandler",
                          authMethod, (long)challenge.previousFailureCount);
    
    BOOL handled = NO;
    Class<ADAuthMethodHandler> handler = nil;
    @synchronized ([self class])
    {
        handler = [s_handlers objectForKey:authMethod];
    }
    
    handled = [handler handleChallenge:challenge
                               session:session
                                  task:task
                              protocol:self
                     completionHandler:completionHandler];
    
    if (!handled)
    {
        // Do default handling
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    
    if ([authMethod caseInsensitiveCompare:NSURLAuthenticationMethodNTLM] == NSOrderedSame)
    {
        [s_telemetryEvent setNtlm:MSID_TELEMETRY_VALUE_YES];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error
{
    (void)session;
    (void)task;
    
    if (error == nil)
    {
        [self.client URLProtocolDidFinishLoading:self];
    }
    else if ([error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
    {
        // Do nothing.  This happens in two cases - 
        // during a redirect, and request cancellation via -stopLoading.
    }
    else
    {
        [self.client URLProtocol:self didFailWithError:error];
    }
}

#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    (void)session;
    (void)dataTask;
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    (void)session;
    (void)dataTask;
    [self.client URLProtocol:self didLoadData:data];
}



@end
