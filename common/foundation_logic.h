#ifndef VC_FOUNDATION_LOGIC_H
#define VC_FOUNDATION_LOGIC_H
#import <Foundation/Foundation.h>
BOOL VCImportPathIsInsideRoot(NSString *rootPath, NSString *path);
BOOL VCAppearanceIsDarkInDefaults(id defaults);
void VCAppearanceSetDarkInDefaults(BOOL dark, id defaults);
NSInteger VCAppearanceAccentIndexInDefaults(id defaults);
void VCAppearanceSetAccentIndexInDefaults(NSInteger index, id defaults);
BOOL VCAutomaticUpdateCheckIsFreshAtTime(id defaults, NSTimeInterval now);
void VCCacheSuccessfulUpdateResultAtTime(NSDictionary *result, id defaults, NSTimeInterval now);
NSString *RoutingPolicyTextInDefaults(id defaults);
NSString *TrimSimpleString(NSString *s);
NSInteger VCNormalizedPingTimeoutSeconds(double seconds);
NSInteger VCPingTimeoutSecondsInDefaults(id defaults);

BOOL VCIsASCIIHexDigit(unichar value);
NSData *VCEncryptSecureStorePayload(NSData *plaintext, const unsigned char key[32]);
NSData *VCDecryptSecureStorePayload(NSData *encrypted, const unsigned char key[32]);
BOOL VCAppearanceIsDark(void);
void VCAppearanceSetDark(BOOL dark);
NSArray *VCAppearanceAccentIdentifiers(void);
NSArray *VCAppearanceAccentNames(void);
NSInteger VCAppearanceAccentIndex(void);
void VCAppearanceSetAccentIndex(NSInteger index);
NSString *VCAppearanceAccentName(void);
BOOL VCXrayVersionIsValid(NSString *value);
BOOL URLStringUsesPlainHTTP(NSString *urlString);
BOOL SubscriptionDictionaryAllowsInsecureFetch(NSDictionary *sub);
NSString *VCValidatedProviderURLString(id rawValue);
NSDictionary *VCSubscriptionMetadataDictionary(NSDictionary *subscription);
NSString *VCSubscriptionDescription(NSDictionary *subscription);
NSString *VCSubscriptionProviderURL(NSDictionary *subscription, NSString *metadataKey);
NSString *VCSubscriptionLastUpdatedText(NSDictionary *subscription);
BOOL SubscriptionDictionaryAllowsPlainHTTP(NSDictionary *sub);
BOOL HappURLStringIsEncrypted(NSString *urlString);
BOOL SubscriptionDictionaryUsesHappHeaders(NSDictionary *sub);
BOOL SubscriptionDictionaryIsHappEncrypted(NSDictionary *sub);
BOOL CurlExitCodeCanRetryInsecurely(int exitCode);
BOOL NSURLErrorCanRetryInsecurely(NSError *err);
BOOL SubscriptionDataLooksLikeHTML(NSData *data);
NSArray *VCNumericVersionComponents(NSString *version);
NSString *VCNormalizedReleaseVersion(NSString *version);
NSComparisonResult VCCompareVersions(NSString *left, NSString *right);
BOOL VCUpdateResultIsSuccessful(NSDictionary *result);
NSData *DecodeBase64String(NSString *input);
NSString *VCSanitizeDiagnosticText(NSString *value, NSUInteger maximumLength);
NSString *VCDiagnosticErrorCategory(NSString *errorText);
NSInteger VCDiagnosticIntegerAfterMarker(NSString *text,
                                                NSString *marker,
                                                NSInteger minimum,
                                                NSInteger maximum);
NSString *VCDiagnosticErrorSummary(NSString *errorText);
void VCIncrementDiagnosticCategory(NSMutableDictionary *counts, NSString *errorText);
NSString *VCDiagnosticCategoryCountsText(NSDictionary *counts);
NSDictionary *VCMakeAppDiagnosticEvent(long long timestamp,
                                               NSString *category,
                                               NSString *action,
                                               NSString *detail);
BOOL VCIsOptionalAppDiagnosticEvent(NSString *category, NSString *action);
NSArray *VCCombinedDiagnosticEvents(NSArray *daemonEvents,
                                           NSArray *appEvents,
                                           NSArray *localEvents);
NSDictionary *VCParseDaemonDiagnostics(NSString *response);
NSArray *VCParseDaemonEvents(NSString *response);
NSString *VCNormalizedIPAddress(NSString *value);

#endif
