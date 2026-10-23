#ifndef VC_PROFILE_LOGIC_H
#define VC_PROFILE_LOGIC_H
#import <Foundation/Foundation.h>
#include <stdint.h>

@protocol VCSubscriptionUpdateOptions <NSObject>
- (BOOL)preserveCustomSubscriptionNames;
- (NSTimeInterval)subscriptionUpdateTimestamp;
@optional
- (void)profileMetadataPrepared:(NSDictionary *)metadata;
@end

@interface VCProfileLogic : NSObject {
    NSDictionary *_profileMetadata;
}
- (NSDictionary *)metadataForURI:(NSString *)uri;
- (BOOL)isConfigurationURI:(NSString *)uri;
- (void)prepareMetadataForConfigurations:(NSArray *)configs subscriptions:(NSArray *)subscriptions;
- (NSDictionary *)preparedMetadataForConfigurations:(NSArray *)configs subscriptions:(NSArray *)subscriptions additionalMetadata:(NSDictionary *)additional;
- (void)installPreparedMetadata:(NSDictionary *)metadata;
- (BOOL)parseServerHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri;
- (NSString *)URIFromKaringServer:(NSDictionary *)server error:(NSString **)error;
- (NSString *)URIFromHappJSONConfig:(NSDictionary *)config;
- (NSDictionary *)importReportFromHappJSONData:(NSData *)data;
- (NSDictionary *)subscriptionImportReportFromData:(NSData *)data;
- (BOOL)appendTransportSettings:(NSDictionary *)stream query:(NSMutableArray *)query;
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
