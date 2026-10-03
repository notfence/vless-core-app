#ifndef VC_PROFILE_LOGIC_H
#define VC_PROFILE_LOGIC_H
#import <Foundation/Foundation.h>
#include <stdint.h>

@protocol VCSubscriptionUpdateOptions <NSObject>
- (BOOL)preserveCustomSubscriptionNames;
- (NSTimeInterval)subscriptionUpdateTimestamp;
@end

@interface VCProfileLogic : NSObject
- (NSString *)decodedURLComponent:(NSString *)component;
- (NSString *)decodedSubscriptionTitleValue:(NSString *)rawValue;
- (NSString *)subscriptionTitleFromMetadataText:(NSString *)text;
- (NSString *)subscriptionTitleFromData:(NSData *)data;
- (NSString *)subscriptionTitleFromHTTPHeaders:(NSDictionary *)headers;
- (NSDictionary *)subscriptionMetadataFromMetadataText:(NSString *)text;
- (NSDictionary *)subscriptionMetadataFromData:(NSData *)data;
- (NSDictionary *)subscriptionMetadataFromHTTPHeaders:(NSDictionary *)headers;
- (NSString *)formattedSubscriptionBytes:(unsigned long long)bytes;
- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub;
- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub;
- (NSDictionary *)updatedSubscriptionFromSource:(NSDictionary *)sub
                                           data:(NSData *)data
                               nameFromMetadata:(NSString *)nameFromMeta
                           userInfoFromMetadata:(NSDictionary *)userInfoFromMeta
                           metadataFromResponse:(NSDictionary *)metadataFromMeta
                                    nameFromURL:(NSString *)nameFromURL
                                       hostName:(NSString *)hostName
                                        options:(id<VCSubscriptionUpdateOptions>)options
                                      errorText:(NSString **)errorTextOut;
- (NSString *)decodeImportTextData:(NSData *)data;
- (BOOL)parseSOCKS5Host:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri;
- (NSString *)strictDecodedConfigQueryComponent:(NSString *)component;
- (NSString *)canonicalConfigQueryKey:(NSString *)encodedKey;
- (NSString *)configURIQueryValidationReason:(NSString *)uri;
- (NSString *)queryValueForURLString:(NSString *)urlString key:(NSString *)key;
- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri;
- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri;
- (NSArray *)extractConfigURIsFromText:(NSString *)text;
- (NSArray *)extractImportLinksFromText:(NSString *)text;
- (NSArray *)extractConfigURIsFromHappJSONData:(NSData *)data;
- (NSArray *)parseSubscriptionData:(NSData *)data;
- (NSArray *)sanitizeSubscriptionURIs:(NSArray *)uris;
- (NSDictionary *)subscriptionUserInfoFromHeaderValue:(NSString *)headerValue;
- (NSString *)safeTrim:(NSString *)s;
- (NSString *)schemeFromURIString:(NSString *)uri;
- (NSString *)transportTypeFromURI:(NSString *)uri;
- (NSString *)securityTypeFromURI:(NSString *)uri;
- (NSString *)realityFlowFromURI:(NSString *)uri;
- (NSString *)realityFingerprintFromURI:(NSString *)uri;
- (BOOL)isSupportedRealityFingerprint:(NSString *)fp;
- (NSArray *)happJSONArrayValue:(id)value;
- (NSString *)vlessURIFromHappJSONConfig:(NSDictionary *)config;
- (NSDictionary *)happJSONDictionaryValue:(id)value;
- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri;
- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri;
- (NSNumber *)subscriptionUnsignedNumberFromString:(NSString *)text;
- (NSString *)happJSONStringValue:(id)value;
- (void)addHappURIQueryValue:(NSString *)value key:(NSString *)key toParts:(NSMutableArray *)parts;
- (NSString *)happJSONStringFromDictionary:(NSDictionary *)dictionary;
- (NSString *)percentEncodedHappURIValue:(NSString *)value;
- (NSDictionary *)subscriptionUserInfoFromMetadataText:(NSString *)text;
- (NSDictionary *)subscriptionUserInfoFromData:(NSData *)data;
- (NSDictionary *)subscriptionUserInfoFromHTTPHeaders:(NSDictionary *)headers;
- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromMetadataText:(NSString *)text;
- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromHTTPHeaders:(NSDictionary *)headers;
@end
VCProfileLogic *VCProfiles(void);
#endif
