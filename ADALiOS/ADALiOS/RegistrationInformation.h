// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.

#import <Foundation/Foundation.h>

@interface RegistrationInformation : NSObject
{
@private
    SecIdentityRef _identity;
    SecCertificateRef _certificate;
    NSString *_certificateSubject;
    NSString *_certificateProperties;
    NSString *_certificateIssuer;
    NSData *_certificateData;
    SecKeyRef _privateKey;
    NSData *_privateKeyData;
    NSString *_userPrincipalName;
}


@property (nonatomic, readonly) SecIdentityRef identity;
@property (nonatomic, readonly) SecCertificateRef certificate;
@property (nonatomic, readonly) NSString *certificateSubject;
@property (nonatomic, readonly) NSString *certificateIssuer;
@property (nonatomic, readonly) NSData *certificateData;
@property (nonatomic, readonly) SecKeyRef privateKey;
@property (nonatomic, readonly) NSData *privateKeyData;
@property (nonatomic, readonly) NSString *userPrincipalName;


-(id)initWithSecurityIdentity:(SecIdentityRef)identity
            userPrincipalName:(NSString*)userPrincipalName
        certificateIssuer:(NSString*)certificateIssuer
                  certificate:(SecCertificateRef)certificate
           certificateSubject:(NSString*)certificateSubject
              certificateData:(NSData*)certificateData
                   privateKey:(SecKeyRef)privateKey
               privateKeyData:(NSData*)privateKeyData;

-(BOOL) isWorkPlaceJoined;

-(void) releaseData;

@end

