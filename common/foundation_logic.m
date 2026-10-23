#import "foundation_logic.h"
#import "app_constants.h"
#include "daemon_policy.h"
#include "../integrations/happ/happ_crypto.h"
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <arpa/inet.h>
#include <limits.h>
#include <math.h>
#include <errno.h>

BOOL VCImportPathIsInsideRoot(NSString *rootPath, NSString *path) {
    NSString *root = [rootPath stringByResolvingSymlinksInPath];
    NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    if ([resolved isEqualToString:root]) return YES;
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [resolved hasPrefix:prefix];
}

BOOL VCAppearanceIsDarkInDefaults(id defaults) {
    return [defaults boolForKey:kDefaultsDarkThemeKey];
}

void VCAppearanceSetDarkInDefaults(BOOL dark, id defaults) {
    NSUserDefaults *ud = defaults;
    [ud setBool:dark forKey:kDefaultsDarkThemeKey];
    [ud synchronize];
}

NSInteger VCAppearanceAccentIndexInDefaults(id defaults) {
    NSString *identifier = [defaults stringForKey:kDefaultsAccentColorKey];
    NSUInteger index = [VCAppearanceAccentIdentifiers() indexOfObject:identifier];
    return index == NSNotFound ? 0 : (NSInteger)index;
}

void VCAppearanceSetAccentIndexInDefaults(NSInteger index, id defaults) {
    NSArray *identifiers = VCAppearanceAccentIdentifiers();
    if (index < 0 || index >= (NSInteger)[identifiers count]) index = 0;
    [defaults setObject:[identifiers objectAtIndex:index] forKey:kDefaultsAccentColorKey];
    [defaults synchronize];
}

BOOL VCAutomaticUpdateCheckIsFreshAtTime(id defaults, NSTimeInterval now) {
    NSTimeInterval lastCheck = [defaults doubleForKey:kDefaultsLastUpdateCheckKey];
    return lastCheck > 0.0 && now >= lastCheck &&
           (now - lastCheck) < kAutomaticUpdateCheckInterval;
}

void VCCacheSuccessfulUpdateResultAtTime(NSDictionary *result, id defaults, NSTimeInterval now) {
    if (!VCUpdateResultIsSuccessful(result)) return;

    [defaults setDouble:now forKey:kDefaultsLastUpdateCheckKey];

    NSString *latestVersion = [result objectForKey:@"latest_version"];
    NSString *releaseURL = [result objectForKey:@"release_url"];
    if ([latestVersion isKindOfClass:[NSString class]]) {
        [defaults setObject:latestVersion forKey:kDefaultsLatestVersionKey];
    }
    if ([releaseURL isKindOfClass:[NSString class]]) {
        [defaults setObject:releaseURL forKey:kDefaultsLatestReleaseURLKey];
    }
    [defaults synchronize];
}

NSString *RoutingPolicyTextInDefaults(id defaults) {
    NSUserDefaults *ud = defaults;
    BOOL enabled = [ud boolForKey:kDefaultsRoutingEnabledKey];
    BOOL bypassLAN = [ud objectForKey:kDefaultsRoutingBypassLANKey] == nil
        ? YES
        : [ud boolForKey:kDefaultsRoutingBypassLANKey];

    NSString *defaultAction = [[ud stringForKey:kDefaultsRoutingDefaultKey] lowercaseString];
    if (![defaultAction isEqualToString:@"proxy"] &&
        ![defaultAction isEqualToString:@"direct"] &&
        ![defaultAction isEqualToString:@"block"]) {
        defaultAction = @"proxy";
    }

    NSMutableString *policy = [NSMutableString stringWithFormat:@"%d;%@;%d",
                               enabled ? 1 : 0,
                               defaultAction,
                               bypassLAN ? 1 : 0];
    NSArray *rules = [ud arrayForKey:kDefaultsRoutingRulesKey];
    NSUInteger count = 0;
    for (id storedRule in rules) {
        if (count >= 24) break;
        if (![storedRule isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *rule = (NSDictionary *)storedRule;
        NSString *action = [[[rule objectForKey:@"action"] description] lowercaseString];
        NSString *type = [[[rule objectForKey:@"type"] description] lowercaseString];
        NSString *value = [[[[rule objectForKey:@"value"] description]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                           lowercaseString];
        BOOL validAction = [action isEqualToString:@"proxy"] ||
                           [action isEqualToString:@"direct"] ||
                           [action isEqualToString:@"block"];
        BOOL validType = [type isEqualToString:@"domain"] ||
                         [type isEqualToString:@"suffix"] ||
                         [type isEqualToString:@"cidr"] ||
                         [type isEqualToString:@"port"];
        if (!validAction || !validType || [value length] == 0 ||
            [value length] > 128 ||
            [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@";,\r\n\t "]].location != NSNotFound) {
            continue;
        }
        [policy appendFormat:@";%@,%@,%@", action, type, value];
        count++;
    }
    return policy;
}

NSString *TrimSimpleString(NSString *s) {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

BOOL VCIsASCIIHexDigit(unichar value) {
    return (value >= '0' && value <= '9') ||
           (value >= 'a' && value <= 'f') ||
           (value >= 'A' && value <= 'F');
}

NSData *VCEncryptSecureStorePayload(NSData *plaintext, const unsigned char key[32]) {
    if (![plaintext isKindOfClass:[NSData class]] || [plaintext length] == 0 || [plaintext length] > INT_MAX) return nil;
    unsigned char nonce[12];
    unsigned char tag[16];
    if (RAND_bytes(nonce, sizeof(nonce)) != 1) return nil;

    NSMutableData *ciphertext = [NSMutableData dataWithLength:[plaintext length] + 16];
    EVP_CIPHER_CTX *context = EVP_CIPHER_CTX_new();
    int count = 0;
    int total = 0;
    BOOL ok = context != NULL &&
              EVP_EncryptInit_ex(context, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1 &&
              EVP_CIPHER_CTX_ctrl(context, EVP_CTRL_GCM_SET_IVLEN, sizeof(nonce), NULL) == 1 &&
              EVP_EncryptInit_ex(context, NULL, NULL, key, nonce) == 1 &&
              EVP_EncryptUpdate(context, NULL, &count, kVCSecureStoreMagic, sizeof(kVCSecureStoreMagic)) == 1 &&
              EVP_EncryptUpdate(context, [ciphertext mutableBytes], &count, [plaintext bytes], (int)[plaintext length]) == 1;
    if (ok) {
        total = count;
        ok = EVP_EncryptFinal_ex(context, (unsigned char *)[ciphertext mutableBytes] + total, &count) == 1;
        total += count;
    }
    if (ok) ok = EVP_CIPHER_CTX_ctrl(context, EVP_CTRL_GCM_GET_TAG, sizeof(tag), tag) == 1;
    if (context) EVP_CIPHER_CTX_free(context);
    if (!ok) return nil;
    [ciphertext setLength:(NSUInteger)total];

    NSMutableData *output = [NSMutableData dataWithCapacity:sizeof(kVCSecureStoreMagic) + sizeof(nonce) + sizeof(tag) + [ciphertext length]];
    [output appendBytes:kVCSecureStoreMagic length:sizeof(kVCSecureStoreMagic)];
    [output appendBytes:nonce length:sizeof(nonce)];
    [output appendBytes:tag length:sizeof(tag)];
    [output appendData:ciphertext];
    return output;
}

NSData *VCDecryptSecureStorePayload(NSData *encrypted, const unsigned char key[32]) {
    NSUInteger headerLength = sizeof(kVCSecureStoreMagic) + kVCSecureStoreNonceLength + kVCSecureStoreTagLength;
    if (![encrypted isKindOfClass:[NSData class]] || [encrypted length] <= headerLength ||
        [encrypted length] - headerLength > INT_MAX) return nil;
    const unsigned char *bytes = (const unsigned char *)[encrypted bytes];
    if (memcmp(bytes, kVCSecureStoreMagic, sizeof(kVCSecureStoreMagic)) != 0) return nil;
    const unsigned char *nonce = bytes + sizeof(kVCSecureStoreMagic);
    const unsigned char *tag = nonce + kVCSecureStoreNonceLength;
    const unsigned char *ciphertext = tag + kVCSecureStoreTagLength;
    NSUInteger ciphertextLength = [encrypted length] - headerLength;

    NSMutableData *plaintext = [NSMutableData dataWithLength:ciphertextLength];
    EVP_CIPHER_CTX *context = EVP_CIPHER_CTX_new();
    int count = 0;
    int total = 0;
    BOOL ok = context != NULL &&
              EVP_DecryptInit_ex(context, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1 &&
              EVP_CIPHER_CTX_ctrl(context, EVP_CTRL_GCM_SET_IVLEN, (int)kVCSecureStoreNonceLength, NULL) == 1 &&
              EVP_DecryptInit_ex(context, NULL, NULL, key, nonce) == 1 &&
              EVP_DecryptUpdate(context, NULL, &count, kVCSecureStoreMagic, sizeof(kVCSecureStoreMagic)) == 1 &&
              EVP_DecryptUpdate(context, [plaintext mutableBytes], &count, ciphertext, (int)ciphertextLength) == 1;
    if (ok) {
        total = count;
        ok = EVP_CIPHER_CTX_ctrl(context, EVP_CTRL_GCM_SET_TAG, (int)kVCSecureStoreTagLength, (void *)tag) == 1 &&
             EVP_DecryptFinal_ex(context, (unsigned char *)[plaintext mutableBytes] + total, &count) == 1;
        total += count;
    }
    if (context) EVP_CIPHER_CTX_free(context);
    if (!ok) return nil;
    [plaintext setLength:(NSUInteger)total];
    return plaintext;
}

BOOL VCAppearanceIsDark(void) {
    return VCAppearanceIsDarkInDefaults([NSUserDefaults standardUserDefaults]);
}

void VCAppearanceSetDark(BOOL dark) {
    VCAppearanceSetDarkInDefaults(dark, [NSUserDefaults standardUserDefaults]);
}

NSArray *VCAppearanceAccentIdentifiers(void) {
    return [NSArray arrayWithObjects:@"blue", @"teal", @"green", @"orange", @"red", @"purple", nil];
}

NSArray *VCAppearanceAccentNames(void) {
    return [NSArray arrayWithObjects:@"Blue", @"Teal", @"Green", @"Orange", @"Red", @"Purple", nil];
}

NSInteger VCAppearanceAccentIndex(void) {
    return VCAppearanceAccentIndexInDefaults([NSUserDefaults standardUserDefaults]);
}

void VCAppearanceSetAccentIndex(NSInteger index) {
    VCAppearanceSetAccentIndexInDefaults(index, [NSUserDefaults standardUserDefaults]);
}

NSString *VCAppearanceAccentName(void) {
    return [VCAppearanceAccentNames() objectAtIndex:VCAppearanceAccentIndex()];
}

BOOL VCXrayVersionIsValid(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    const char *text=[value UTF8String];
    return text && strlen(text) == [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] && vc_xray_version_valid(text);
}

BOOL URLStringUsesPlainHTTP(NSString *urlString) {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"];
}

BOOL SubscriptionDictionaryAllowsInsecureFetch(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    id value = [sub objectForKey:kSubscriptionAllowInsecureFetchKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue] ? YES : NO;
    }
    return NO;
}

NSString *VCValidatedProviderURLString(id rawValue) {
    if (![rawValue isKindOfClass:[NSString class]]) return nil;

    NSString *value = [(NSString *)rawValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value length] == 0 ||
        [value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound ||
        [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:value];
    NSString *scheme = [[url scheme] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;
    if ([[url host] length] == 0) return nil;
    return value;
}

NSDictionary *VCSubscriptionMetadataDictionary(NSDictionary *subscription) {
    id metadata = [subscription objectForKey:kSubscriptionMetadataKey];
    return [metadata isKindOfClass:[NSDictionary class]] ? metadata : nil;
}

NSString *VCSubscriptionDescription(NSDictionary *subscription) {
    id rawDescription = [VCSubscriptionMetadataDictionary(subscription)
        objectForKey:kSubscriptionDescriptionKey];
    if (![rawDescription isKindOfClass:[NSString class]]) return nil;

    NSString *description = [(NSString *)rawDescription
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [description length] > 0 ? description : nil;
}

NSString *VCSubscriptionProviderURL(NSDictionary *subscription, NSString *metadataKey) {
    return VCValidatedProviderURLString(
        [VCSubscriptionMetadataDictionary(subscription) objectForKey:metadataKey]);
}

NSString *VCSubscriptionLastUpdatedText(NSDictionary *subscription) {
    id rawTimestamp = [VCSubscriptionMetadataDictionary(subscription)
        objectForKey:kSubscriptionLastUpdatedKey];
    if (![rawTimestamp isKindOfClass:[NSNumber class]] || [rawTimestamp unsignedLongLongValue] == 0) {
        return @"Updated: Never";
    }

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)[rawTimestamp unsignedLongLongValue]];
    if (!date) return @"Updated: Never";

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setDateFormat:@"dd.MM.yyyy HH:mm"];
    NSString *formatted = [formatter stringFromDate:date];
    return [formatted length] > 0 ? [NSString stringWithFormat:@"Updated: %@", formatted]
                                  : @"Updated: Never";
}

BOOL SubscriptionDictionaryAllowsPlainHTTP(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;
    id value = [sub objectForKey:kSubscriptionAllowPlainHTTPKey];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

BOOL HappURLStringIsEncrypted(NSString *urlString) {
    NSString *lower = [urlString isKindOfClass:[NSString class]] ? [urlString lowercaseString] : nil;
    return [lower hasPrefix:@"happ://crypt4/"] || [lower hasPrefix:@"happ://crypt5/"];
}

BOOL SubscriptionDictionaryUsesHappHeaders(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    id value = [sub objectForKey:kSubscriptionHappSourceKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        if ([value boolValue]) return YES;
    }

    NSString *urlString = [sub objectForKey:@"url"];
    NSString *lower = [urlString isKindOfClass:[NSString class]] ? [urlString lowercaseString] : nil;
    if ([lower hasPrefix:kHappAddPrefix] || HappURLStringIsEncrypted(urlString)) return YES;
    return NO;
}

BOOL SubscriptionDictionaryIsHappEncrypted(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    return HappURLStringIsEncrypted([sub objectForKey:@"url"]);
}

BOOL CurlExitCodeCanRetryInsecurely(int exitCode) {
    return exitCode == 60; /* CURLE_PEER_FAILED_VERIFICATION */
}

BOOL NSURLErrorCanRetryInsecurely(NSError *err) {
    if (![err isKindOfClass:[NSError class]]) return NO;
    if (![[err domain] isEqualToString:NSURLErrorDomain]) return NO;

    NSInteger code = [err code];
    return code == NSURLErrorSecureConnectionFailed ||
           code == NSURLErrorServerCertificateHasBadDate ||
           code == NSURLErrorServerCertificateUntrusted ||
           code == NSURLErrorServerCertificateHasUnknownRoot ||
           code == NSURLErrorServerCertificateNotYetValid;
}

BOOL SubscriptionDataLooksLikeHTML(NSData *data) {
    if (!data || [data length] == 0) return NO;

    NSUInteger len = [data length];
    if (len > 4096) len = 4096;
    NSData *prefix = [NSData dataWithBytes:[data bytes] length:len];
    NSString *text = [[[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:prefix encoding:NSISOLatin1StringEncoding] autorelease];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;

    NSString *trim = TrimSimpleString(text);
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"<!doctype html"] ||
           [lower hasPrefix:@"<html"] ||
           [lower rangeOfString:@"<body"].location != NSNotFound;
}

NSArray *VCNumericVersionComponents(NSString *version) {
    NSString *trimmed = TrimSimpleString(version);
    if ([trimmed length] == 0) return [NSArray array];

    NSMutableArray *components = [NSMutableArray array];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSUInteger index = 0;
    while (index < [trimmed length]) {
        while (index < [trimmed length] && ![digits characterIsMember:[trimmed characterAtIndex:index]]) {
            index++;
        }
        if (index >= [trimmed length]) break;

        NSUInteger start = index;
        while (index < [trimmed length] && [digits characterIsMember:[trimmed characterAtIndex:index]]) {
            index++;
        }
        [components addObject:[NSNumber numberWithLongLong:[[trimmed substringWithRange:NSMakeRange(start, index - start)] longLongValue]]];
    }
    return components;
}

NSString *VCNormalizedReleaseVersion(NSString *version) {
    NSString *trimmed = TrimSimpleString(version);
    if ([trimmed length] > 1) {
        unichar first = [trimmed characterAtIndex:0];
        unichar second = [trimmed characterAtIndex:1];
        if ((first == 'v' || first == 'V') && second >= '0' && second <= '9') {
            return [trimmed substringFromIndex:1];
        }
    }
    return trimmed;
}

NSComparisonResult VCCompareVersions(NSString *left, NSString *right) {
    NSArray *leftParts = VCNumericVersionComponents(left);
    NSArray *rightParts = VCNumericVersionComponents(right);
    NSUInteger count = MAX([leftParts count], [rightParts count]);

    for (NSUInteger i = 0; i < count; i++) {
        long long leftValue = (i < [leftParts count]) ? [[leftParts objectAtIndex:i] longLongValue] : 0;
        long long rightValue = (i < [rightParts count]) ? [[rightParts objectAtIndex:i] longLongValue] : 0;
        if (leftValue < rightValue) return NSOrderedAscending;
        if (leftValue > rightValue) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

BOOL VCUpdateResultIsSuccessful(NSDictionary *result) {
    NSString *status = [result objectForKey:@"status"];
    return [status isEqualToString:@"update"] || [status isEqualToString:@"current"];
}

static int Base64Value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return (int)(c - 'A');
    if (c >= 'a' && c <= 'z') return (int)(c - 'a') + 26;
    if (c >= '0' && c <= '9') return (int)(c - '0') + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

NSData *DecodeBase64String(NSString *input) {
    if (!input) return nil;

    const char *s = [input UTF8String];
    if (!s) return nil;

    size_t in_len = strlen(s);
    if (in_len == 0) return nil;

    size_t cap = (in_len / 4) * 3 + 3;
    unsigned char *out = (unsigned char *)malloc(cap);
    if (!out) return nil;

    int vals[4];
    int vcount = 0;
    size_t out_len = 0;

    for (size_t i = 0; i < in_len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            continue;
        }

        if (c == '=') {
            vals[vcount++] = -2;
        } else {
            int v = Base64Value(c);
            if (v < 0) {
                free(out);
                return nil;
            }
            vals[vcount++] = v;
        }

        if (vcount == 4) {
            if (vals[0] < 0 || vals[1] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));

            if (vals[2] == -2) {
                vcount = 0;
                break;
            }
            if (vals[2] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)(((vals[1] & 0x0F) << 4) | (vals[2] >> 2));

            if (vals[3] == -2) {
                vcount = 0;
                break;
            }
            if (vals[3] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)(((vals[2] & 0x03) << 6) | vals[3]);
            vcount = 0;
        }
    }

    if (vcount == 2) {
        if (vals[0] < 0 || vals[1] < 0) {
            free(out);
            return nil;
        }
        out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));
    } else if (vcount == 3) {
        if (vals[0] < 0 || vals[1] < 0 || vals[2] < 0) {
            free(out);
            return nil;
        }
        out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));
        out[out_len++] = (unsigned char)(((vals[1] & 0x0F) << 4) | (vals[2] >> 2));
    } else if (vcount != 0) {
        free(out);
        return nil;
    }

    return [NSData dataWithBytesNoCopy:out length:out_len freeWhenDone:YES];
}

static NSArray *VCDiagnosticRedactionExpressions(void) {
    static NSArray *expressions = nil;
    @synchronized([NSRegularExpression class]) {
        if (expressions) return expressions;
        NSMutableArray *compiled = [NSMutableArray array];
        NSArray *patterns = [NSArray arrayWithObjects:
                             @"[A-Za-z][A-Za-z0-9+.-]*://\\S+",
                             @"\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b",
                             @"\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b",
                             @"(?i)\\b(?:[0-9a-f]{0,4}:){2,}[0-9a-f:]{0,4}\\b",
                             @"(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",
                             @"\\b(?:[A-Za-z0-9-]+\\.)+[A-Za-z]{2,}\\b",
                             @"\\b[A-Za-z0-9_+/=-]{24,}\\b",
                             nil];
        for (NSString *pattern in patterns) {
            NSError *error = nil;
            NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                          options:0
                                                                                            error:&error];
            if (expression && !error) [compiled addObject:expression];
        }
        expressions = [compiled copy];
    }
    return expressions;
}

NSString *VCSanitizeDiagnosticText(NSString *value, NSUInteger maximumLength) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return @"";
    NSMutableString *safe = [NSMutableString stringWithString:value];
    for (NSRegularExpression *expression in VCDiagnosticRedactionExpressions()) {
        [expression replaceMatchesInString:safe
                                   options:0
                                     range:NSMakeRange(0, [safe length])
                              withTemplate:@"<redacted>"];
    }
    [safe replaceOccurrencesOfString:@"\r" withString:@" " options:0 range:NSMakeRange(0, [safe length])];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, [safe length])];
    [safe replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0, [safe length])];
    if (maximumLength > 0 && [safe length] > maximumLength) {
        [safe deleteCharactersInRange:NSMakeRange(maximumLength, [safe length] - maximumLength)];
    }
    return safe;
}

NSString *VCDiagnosticErrorCategory(NSString *errorText) {
    NSString *lower = [[errorText description] lowercaseString];
    if ([lower rangeOfString:@"timeout"].location != NSNotFound ||
        [lower rangeOfString:@"timed out"].location != NSNotFound) return @"timeout";
    if ([lower rangeOfString:@"resolve"].location != NSNotFound ||
        [lower rangeOfString:@"dns"].location != NSNotFound ||
        [lower rangeOfString:@"name or service"].location != NSNotFound) return @"dns";
    if ([lower rangeOfString:@"tls"].location != NSNotFound ||
        [lower rangeOfString:@"ssl"].location != NSNotFound ||
        [lower rangeOfString:@"certificate"].location != NSNotFound) return @"tls";
    if ([lower rangeOfString:@"http"].location != NSNotFound) return @"http";
    if ([lower rangeOfString:@"decrypt"].location != NSNotFound ||
        [lower rangeOfString:@"happ"].location != NSNotFound) return @"decrypt";
    if ([lower rangeOfString:@"too large"].location != NSNotFound ||
        [lower rangeOfString:@"size"].location != NSNotFound) return @"size_limit";
    if ([lower rangeOfString:@"parse"].location != NSNotFound ||
        [lower rangeOfString:@"invalid"].location != NSNotFound ||
        [lower rangeOfString:@"unsupported"].location != NSNotFound ||
        [lower rangeOfString:@"empty"].location != NSNotFound) return @"format";
    if ([lower rangeOfString:@"curl"].location != NSNotFound ||
        [lower rangeOfString:@"exit"].location != NSNotFound) return @"transport";
    return @"unknown";
}

NSInteger VCDiagnosticIntegerAfterMarker(NSString *text,
                                                NSString *marker,
                                                NSInteger minimum,
                                                NSInteger maximum) {
    if (![text isKindOfClass:[NSString class]] || ![marker isKindOfClass:[NSString class]]) return -1;
    NSString *lower = [text lowercaseString];
    NSRange markerRange = [lower rangeOfString:[marker lowercaseString]];
    if (markerRange.location == NSNotFound) return -1;
    NSUInteger cursor = NSMaxRange(markerRange);
    NSUInteger limit = MIN([text length], cursor + 24);
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    while (cursor < limit && ![digits characterIsMember:[text characterAtIndex:cursor]]) cursor++;
    NSUInteger start = cursor;
    while (cursor < limit && [digits characterIsMember:[text characterAtIndex:cursor]]) cursor++;
    if (cursor == start) return -1;
    NSInteger value = [[text substringWithRange:NSMakeRange(start, cursor - start)] integerValue];
    return value >= minimum && value <= maximum ? value : -1;
}

NSString *VCDiagnosticErrorSummary(NSString *errorText) {
    NSString *category = VCDiagnosticErrorCategory(errorText);
    NSInteger httpStatus = VCDiagnosticIntegerAfterMarker(errorText, @"http", 100, 599);
    if (httpStatus >= 0) {
        return [NSString stringWithFormat:@"%@ http_status=%ld", category, (long)httpStatus];
    }
    NSInteger exitCode = VCDiagnosticIntegerAfterMarker(errorText, @"exited with code", 0, 255);
    if (exitCode >= 0) {
        return [NSString stringWithFormat:@"%@ helper_exit=%ld", category, (long)exitCode];
    }
    return category;
}

void VCIncrementDiagnosticCategory(NSMutableDictionary *counts, NSString *errorText) {
    if (![counts isKindOfClass:[NSMutableDictionary class]]) return;
    NSString *category = VCDiagnosticErrorCategory(errorText);
    NSUInteger count = [[counts objectForKey:category] unsignedIntegerValue];
    [counts setObject:[NSNumber numberWithUnsignedInteger:count + 1] forKey:category];
}

NSString *VCDiagnosticCategoryCountsText(NSDictionary *counts) {
    if (![counts isKindOfClass:[NSDictionary class]] || [counts count] == 0) return @"none";
    NSArray *keys = [[counts allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[keys count]];
    for (NSString *key in keys) {
        [parts addObject:[NSString stringWithFormat:@"%@:%lu",
                          key,
                          (unsigned long)[[counts objectForKey:key] unsignedIntegerValue]]];
    }
    return [parts componentsJoinedByString:@","];
}

NSDictionary *VCMakeAppDiagnosticEvent(long long timestamp,
                                               NSString *category,
                                               NSString *action,
                                               NSString *detail) {
    NSString *safeCategory = VCSanitizeDiagnosticText(category, 24);
    NSString *safeAction = VCSanitizeDiagnosticText(action, 96);
    NSString *safeDetail = VCSanitizeDiagnosticText(detail, 192);
    if ([safeCategory length] == 0 || [safeAction length] == 0 || timestamp <= 0) return nil;
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithLongLong:timestamp], @"timestamp",
                                  @"app", @"source",
                                  safeCategory, @"category",
                                  safeAction, @"action",
                                  nil];
    if ([safeDetail length] > 0) [event setObject:safeDetail forKey:@"detail"];
    return event;
}

BOOL VCIsOptionalAppDiagnosticEvent(NSString *category, NSString *action) {
    if ([category isEqualToString:@"connection"] ||
        [category isEqualToString:@"daemon"] ||
        [category isEqualToString:@"diagnostics"] ||
        [category isEqualToString:@"ping"]) return NO;
    if ([category isEqualToString:@"subscription"] &&
        [action rangeOfString:@"update" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return YES;
}

NSArray *VCCombinedDiagnosticEvents(NSArray *daemonEvents,
                                           NSArray *appEvents,
                                           NSArray *localEvents) {
    NSMutableArray *events = [NSMutableArray array];
    if (daemonEvents) [events addObjectsFromArray:daemonEvents];
    if (appEvents) [events addObjectsFromArray:appEvents];
    if (localEvents) [events addObjectsFromArray:localEvents];
    NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"timestamp"
                                                          ascending:YES] autorelease];
    [events sortUsingDescriptors:[NSArray arrayWithObject:sort]];
    if ([events count] > kVCDiagnosticEventCapacity) {
        [events removeObjectsInRange:
         NSMakeRange(0, [events count] - kVCDiagnosticEventCapacity)];
    }
    return events;
}

NSDictionary *VCParseDaemonDiagnostics(NSString *response) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if (![response isKindOfClass:[NSString class]] || ![response hasPrefix:@"OK "]) {
        [values setObject:(response ? response : @"daemon unavailable") forKey:@"error"];
        return values;
    }

    NSArray *lines = [response componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSRange separator = [line rangeOfString:@"="];
        if (separator.location == NSNotFound || separator.location == 0) continue;
        NSString *key = [line substringToIndex:separator.location];
        NSString *value = [line substringFromIndex:NSMaxRange(separator)];
        if ([key length] > 0 && [value length] > 0) [values setObject:value forKey:key];
    }
    return values;
}

NSArray *VCParseDaemonEvents(NSString *response) {
    NSMutableArray *events = [NSMutableArray array];
    if (![response isKindOfClass:[NSString class]] || ![response hasPrefix:@"OK "]) {
        return events;
    }

    NSArray *lines = [response componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (![line hasPrefix:@"EVENT\t"]) continue;
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if ([parts count] < 3) continue;
        long long timestamp = [[parts objectAtIndex:1] longLongValue];
        NSString *message = [parts objectAtIndex:2];
        if (timestamp <= 0 || [message length] == 0) continue;
        [events addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithLongLong:timestamp], @"timestamp",
                           @"daemon", @"source",
                           message, @"message",
                           nil]];
    }
    return events;
}

NSString *VCNormalizedIPAddress(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [trimmed length] > INET6_ADDRSTRLEN) return nil;

    unsigned char address[sizeof(struct in6_addr)];
    if (inet_pton(AF_INET, [trimmed UTF8String], address) == 1 ||
        inet_pton(AF_INET6, [trimmed UTF8String], address) == 1) {
        return trimmed;
    }
    return nil;
}
