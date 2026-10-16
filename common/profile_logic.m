#import "profile_logic.h"
#import "foundation_logic.h"
#import "app_constants.h"
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>
#include <limits.h>
#include <CoreFoundation/CoreFoundation.h>

static id VCProfileAlias(NSDictionary *object, NSArray *names, BOOL *valid) {
    id result = nil;
    for (NSString *name in names) {
        id value = [object objectForKey:name];
        if (value && result && ![value isEqual:result]) *valid = NO;
        if (value) result = value;
    }
    return result;
}

static BOOL VCProfileText(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    for (NSUInteger i = 0; i < [value length]; i++) {
        unichar c = [value characterAtIndex:i];
        if (c < 0x20 || c == 0x7f) return NO;
    }
    return YES;
}

static BOOL VCProfileUnsigned(id value, unsigned maximum, unsigned *result) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    const char *text = [[value stringValue] UTF8String];
    unsigned parsed = 0;
    if (!text || !*text) return NO;
    for (; *text; text++) {
        unsigned digit = (unsigned)(*text - '0');
        if (digit > 9 || parsed > maximum / 10 || (parsed == maximum / 10 && digit > maximum % 10)) return NO;
        parsed = parsed * 10 + digit;
    }
    *result = parsed;
    return YES;
}

static BOOL VCProfileBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] && strchr("cCB", [value objCType][0]) &&
        ([value intValue] == 0 || [value intValue] == 1);
}

static BOOL VCProfileHeaders(id value) {
    if (![value isKindOfClass:[NSDictionary class]]) return NO;
    for (id key in value) {
        if (!VCProfileText(key) || ![key length] || !VCProfileText([value objectForKey:key])) return NO;
        const char *name = [key UTF8String];
        for (; *name; name++) if (!isalnum((unsigned char)*name) && !strchr("!#$%&'*+-.^_`|~", *name)) return NO;
        NSString *lower = [key lowercaseString];
        if ([lower isEqual:@"connection"] || [lower isEqual:@"upgrade"] || [lower isEqual:@"content-length"] ||
            [lower isEqual:@"transfer-encoding"]) return NO;
    }
    return YES;
}

static void VCProfileUnknown(NSDictionary *object, NSArray *known, NSString *scope) {
    for (id key in object) if (![known containsObject:key]) {
        NSString *safe = [key isKindOfClass:[NSString class]] ? key : @"?";
        NSMutableString *path = [NSMutableString stringWithString:scope];
        for (NSUInteger i = 0; i < [safe length] && i < 64; i++) {
            unichar c = [safe characterAtIndex:i];
            [path appendFormat:@"%C", (unichar)((c >= 0x21 && c < 0x7f) ? c : '?')];
        }
        NSLog(@"HAPP unknown field %@ ignored", path);
    }
}

@implementation VCProfileLogic

- (NSString *)decodedURLComponent:(NSString *)component {
    if (![component isKindOfClass:[NSString class]] || [component length] == 0) return @"";

    NSString *fixed = [component stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
    NSString *decoded = [fixed stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        decoded = fixed;
    }
    return [self safeTrim:decoded];
}

- (NSString *)decodedSubscriptionTitleValue:(NSString *)rawValue {
    if (![rawValue isKindOfClass:[NSString class]]) return nil;

    NSString *value = [self safeTrim:rawValue];
    if ([value length] == 0) return nil;

    if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2) {
        value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
        value = [self safeTrim:value];
    }
    if ([value length] == 0) return nil;

    NSString *lower = [value lowercaseString];
    if ([lower hasPrefix:@"base64:"]) {
        NSString *b64 = [self safeTrim:[value substringFromIndex:7]];
        NSData *decoded = DecodeBase64String(b64);
        if (!decoded || [decoded length] == 0) return nil;

        NSString *txt = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
        if (!txt) txt = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
        txt = [self safeTrim:txt];
        return ([txt length] > 0) ? txt : nil;
    }

    NSString *decoded = [self decodedURLComponent:value];
    return ([decoded length] > 0) ? decoded : nil;
}

- (NSString *)subscriptionTitleFromMetadataText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return nil;

    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *found = nil;
    for (NSString *line in lines) {
        if (![line isKindOfClass:[NSString class]]) continue;
        NSString *trim = [self safeTrim:line];
        if ([trim length] == 0) continue;

        if ([trim hasPrefix:@"#"]) {
            trim = [self safeTrim:[trim substringFromIndex:1]];
            if ([trim length] == 0) continue;
        }

        NSString *lower = [trim lowercaseString];
        if (![lower hasPrefix:@"profile-title"]) continue;

        NSRange sep = [trim rangeOfString:@":"];
        if (sep.location == NSNotFound) {
            sep = [trim rangeOfString:@"="];
        }
        if (sep.location == NSNotFound || sep.location + 1 >= [trim length]) continue;

        NSString *rawValue = [trim substringFromIndex:(sep.location + 1)];
        NSString *decoded = [self decodedSubscriptionTitleValue:rawValue];
        if ([decoded length] > 0) {
            found = decoded;
        }
    }

    return found;
}

- (NSString *)subscriptionTitleFromData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!raw || [raw length] == 0) return nil;

    NSString *title = [self subscriptionTitleFromMetadataText:raw];
    if ([title length] > 0) return title;

    NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSData *decoded = DecodeBase64String(b64);
    if (!decoded || [decoded length] == 0) return nil;

    NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
    if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
    if (!decodedText || [decodedText length] == 0) return nil;

    return [self subscriptionTitleFromMetadataText:decodedText];
}

- (NSString *)subscriptionTitleFromHTTPHeaders:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]]) return nil;

    for (id key in headers) {
        if (![key isKindOfClass:[NSString class]]) continue;
        NSString *keyString = [(NSString *)key lowercaseString];
        if (![keyString isEqualToString:@"profile-title"]) continue;

        id rawHeader = [headers objectForKey:key];
        if (![rawHeader isKindOfClass:[NSString class]]) continue;

        NSString *decoded = [self decodedSubscriptionTitleValue:(NSString *)rawHeader];
        if ([decoded length] > 0) return decoded;
    }

    return nil;
}

- (NSDictionary *)subscriptionMetadataFromMetadataText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return nil;

    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    NSString *description = [self subscriptionHeaderValueNamed:@"announce" fromMetadataText:text];
    if ([description length] == 0) {
        description = [self subscriptionHeaderValueNamed:@"profile-description" fromMetadataText:text];
    }
    description = [self decodedSubscriptionTitleValue:description];
    if ([description length] > 0) [metadata setObject:description forKey:kSubscriptionDescriptionKey];

    NSString *supportURL = [self decodedSubscriptionTitleValue:
                            [self subscriptionHeaderValueNamed:@"support-url" fromMetadataText:text]];
    if ([supportURL length] > 0) [metadata setObject:supportURL forKey:kSubscriptionSupportURLKey];

    NSString *webPageURL = [self decodedSubscriptionTitleValue:
                            [self subscriptionHeaderValueNamed:@"profile-web-page-url" fromMetadataText:text]];
    if ([webPageURL length] > 0) [metadata setObject:webPageURL forKey:kSubscriptionWebPageURLKey];

    NSNumber *updateInterval = [self subscriptionUnsignedNumberFromString:
                                [self subscriptionHeaderValueNamed:@"profile-update-interval" fromMetadataText:text]];
    if (updateInterval) [metadata setObject:updateInterval forKey:kSubscriptionUpdateIntervalKey];

    NSNumber *refillDate = [self subscriptionUnsignedNumberFromString:
                            [self subscriptionHeaderValueNamed:@"subscription-refill-date" fromMetadataText:text]];
    if (refillDate) [metadata setObject:refillDate forKey:kSubscriptionRefillDateKey];
    return ([metadata count] > 0) ? metadata : nil;
}

- (NSDictionary *)subscriptionMetadataFromData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    NSDictionary *metadata = [self subscriptionMetadataFromMetadataText:raw];
    if ([metadata count] > 0) return metadata;

    NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSData *decoded = DecodeBase64String(b64);
    if (!decoded || [decoded length] == 0) return nil;

    NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
    if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
    return [self subscriptionMetadataFromMetadataText:decodedText];
}

- (NSDictionary *)subscriptionMetadataFromHTTPHeaders:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    NSString *description = [self subscriptionHeaderValueNamed:@"announce" fromHTTPHeaders:headers];
    if ([description length] == 0) {
        description = [self subscriptionHeaderValueNamed:@"profile-description" fromHTTPHeaders:headers];
    }
    description = [self decodedSubscriptionTitleValue:description];
    if ([description length] > 0) [metadata setObject:description forKey:kSubscriptionDescriptionKey];

    NSString *supportURL = [self decodedSubscriptionTitleValue:
                            [self subscriptionHeaderValueNamed:@"support-url" fromHTTPHeaders:headers]];
    if ([supportURL length] > 0) [metadata setObject:supportURL forKey:kSubscriptionSupportURLKey];

    NSString *webPageURL = [self decodedSubscriptionTitleValue:
                            [self subscriptionHeaderValueNamed:@"profile-web-page-url" fromHTTPHeaders:headers]];
    if ([webPageURL length] > 0) [metadata setObject:webPageURL forKey:kSubscriptionWebPageURLKey];

    NSNumber *updateInterval = [self subscriptionUnsignedNumberFromString:
                                [self subscriptionHeaderValueNamed:@"profile-update-interval" fromHTTPHeaders:headers]];
    if (updateInterval) [metadata setObject:updateInterval forKey:kSubscriptionUpdateIntervalKey];

    NSNumber *refillDate = [self subscriptionUnsignedNumberFromString:
                            [self subscriptionHeaderValueNamed:@"subscription-refill-date" fromHTTPHeaders:headers]];
    if (refillDate) [metadata setObject:refillDate forKey:kSubscriptionRefillDateKey];
    return ([metadata count] > 0) ? metadata : nil;
}

- (NSString *)formattedSubscriptionBytes:(unsigned long long)bytes {
    static NSString *const units[] = {@"B", @"KB", @"MB", @"GB", @"TB", @"PB"};
    double value = (double)bytes;
    NSUInteger unit = 0;
    while (value >= 1024.0 && unit < 5) {
        value /= 1024.0;
        unit++;
    }

    if (unit == 0 || value >= 10.0) {
        return [NSString stringWithFormat:@"%.0f %@", value, units[unit]];
    }
    return [NSString stringWithFormat:@"%.1f %@", value, units[unit]];
}

- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub {
    NSDictionary *info = [sub objectForKey:kSubscriptionUserInfoKey];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    NSNumber *uploadNumber = [info objectForKey:kSubscriptionUploadKey];
    NSNumber *downloadNumber = [info objectForKey:kSubscriptionDownloadKey];
    NSNumber *totalNumber = [info objectForKey:kSubscriptionTotalKey];
    BOOL hasUsed = [uploadNumber isKindOfClass:[NSNumber class]] || [downloadNumber isKindOfClass:[NSNumber class]];
    BOOL hasTotal = [totalNumber isKindOfClass:[NSNumber class]];
    if (!hasUsed && !hasTotal) return nil;

    unsigned long long upload = [uploadNumber isKindOfClass:[NSNumber class]] ? [uploadNumber unsignedLongLongValue] : 0;
    unsigned long long download = [downloadNumber isKindOfClass:[NSNumber class]] ? [downloadNumber unsignedLongLongValue] : 0;
    unsigned long long used = (ULLONG_MAX - upload < download) ? ULLONG_MAX : upload + download;

    NSString *usedText = [self formattedSubscriptionBytes:used];
    if (hasTotal) {
        unsigned long long total = [totalNumber unsignedLongLongValue];
        NSString *totalText = (total > 0) ? [self formattedSubscriptionBytes:total] : @"∞";
        return [NSString stringWithFormat:@"%@ / %@",
                usedText,
                totalText];
    }
    return [NSString stringWithFormat:@"%@ used", usedText];
}

- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub {
    NSDictionary *info = [sub objectForKey:kSubscriptionUserInfoKey];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    NSNumber *expireNumber = [info objectForKey:kSubscriptionExpireKey];
    if (![expireNumber isKindOfClass:[NSNumber class]]) return nil;

    unsigned long long timestamp = [expireNumber unsignedLongLongValue];
    if (timestamp == 0) return @"No expiry";

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestamp];
    if (!date) return nil;

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setDateFormat:@"dd.MM.yyyy"];
    NSString *formatted = [formatter stringFromDate:date];
    return [formatted length] > 0 ? formatted : nil;
}

- (NSDictionary *)updatedSubscriptionFromSource:(NSDictionary *)sub
                                           data:(NSData *)data
                               nameFromMetadata:(NSString *)nameFromMeta
                           userInfoFromMetadata:(NSDictionary *)userInfoFromMeta
                           metadataFromResponse:(NSDictionary *)metadataFromMeta
                                    nameFromURL:(NSString *)nameFromURL
                                       hostName:(NSString *)hostName
                                        options:(id<VCSubscriptionUpdateOptions>)options
                                      errorText:(NSString **)errorTextOut {
    if ([nameFromMeta length] == 0) {
        nameFromMeta = [self subscriptionTitleFromData:data];
    }
    if ([userInfoFromMeta count] == 0) {
        userInfoFromMeta = [self subscriptionUserInfoFromData:data];
    }
    if ([metadataFromMeta count] == 0) {
        metadataFromMeta = [self subscriptionMetadataFromData:data];
    }

    NSArray *uris = [self parseSubscriptionData:data];
    if ([uris count] == 0) {
        if (errorTextOut) {
            if (SubscriptionDataLooksLikeHTML(data)) {
                *errorTextOut = @"Server returned a web page, not subscription data";
            } else {
                *errorTextOut = @"Subscription has no valid config entries";
            }
        }
        return nil;
    }

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updated setObject:uris forKey:@"items"];
    [updated removeObjectForKey:kSubscriptionUserInfoKey];
    if ([userInfoFromMeta count] > 0) {
        [updated setObject:userInfoFromMeta forKey:kSubscriptionUserInfoKey];
    }
    NSMutableDictionary *storedMetadata = [NSMutableDictionary dictionary];
    if ([metadataFromMeta isKindOfClass:[NSDictionary class]]) {
        [storedMetadata addEntriesFromDictionary:metadataFromMeta];
    }
    [storedMetadata setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)[options subscriptionUpdateTimestamp]]
                       forKey:kSubscriptionLastUpdatedKey];
    [updated setObject:storedMetadata forKey:kSubscriptionMetadataKey];

    NSString *customName = [sub objectForKey:kSubscriptionCustomNameKey];
    BOOL hasCustomName = [customName isKindOfClass:[NSString class]] && [customName length] > 0;
    if ([options preserveCustomSubscriptionNames] && hasCustomName) {
        [updated setObject:customName forKey:@"name"];
    } else if ([nameFromMeta length] > 0) {
        [updated removeObjectForKey:kSubscriptionCustomNameKey];
        [updated setObject:nameFromMeta forKey:@"name"];
    } else {
        [updated removeObjectForKey:kSubscriptionCustomNameKey];
        NSString *name = [updated objectForKey:@"name"];
        BOOL missing = (![name isKindOfClass:[NSString class]] || [name length] == 0);
        BOOL legacyHost = ([name isKindOfClass:[NSString class]] && [name isEqualToString:hostName]);
        if (hasCustomName || missing || legacyHost) {
            [updated setObject:nameFromURL forKey:@"name"];
        }
    }

    return updated;
}

- (NSString *)decodeImportTextData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger len = [data length];

    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!text && len >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        text = [[[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding] autorelease];
    }
    if (!text && len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        text = [[[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding] autorelease];
    }
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
    return text;
}

- (BOOL)parseSOCKS5Host:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    NSString *trim = [self safeTrim:uri];
    NSString *lower = [trim lowercaseString];
    if (![lower hasPrefix:@"socks5://"]) return NO;

    NSString *authority = [trim substringFromIndex:9];
    NSCharacterSet *endSet = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
    NSRange end = [authority rangeOfCharacterFromSet:endSet];
    if (end.location != NSNotFound) {
        authority = [authority substringToIndex:end.location];
    }
    authority = [self safeTrim:authority];
    if ([authority length] == 0) return NO;

    NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound && at.location + 1 < [authority length]) {
        authority = [authority substringFromIndex:(at.location + 1)];
    }
    authority = [self safeTrim:authority];
    if ([authority length] == 0) return NO;

    NSString *host = nil;
    uint16_t port = 1080;
    if ([authority hasPrefix:@"["]) {
        NSRange rb = [authority rangeOfString:@"]"];
        if (rb.location == NSNotFound || rb.location <= 1) return NO;
        host = [authority substringWithRange:NSMakeRange(1, rb.location - 1)];
        if (rb.location + 1 < [authority length] && [authority characterAtIndex:(rb.location + 1)] == ':') {
            NSString *rawPort = [authority substringFromIndex:(rb.location + 2)];
            NSInteger p = [rawPort integerValue];
            if (p <= 0 || p > 65535) return NO;
            port = (uint16_t)p;
        }
    } else {
        NSRange colon = [authority rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound) {
            host = [authority substringToIndex:colon.location];
            NSString *rawPort = [authority substringFromIndex:(colon.location + 1)];
            NSInteger p = [rawPort integerValue];
            if (p <= 0 || p > 65535) return NO;
            port = (uint16_t)p;
        } else {
            host = authority;
        }
    }

    host = [self safeTrim:host];
    if ([host length] == 0) return NO;
    if (hostOut) *hostOut = host;
    if (portOut) *portOut = port;
    return YES;
}

- (NSString *)strictDecodedConfigQueryComponent:(NSString *)component {
    if (![component isKindOfClass:[NSString class]]) return nil;

    NSUInteger length = [component length];
    for (NSUInteger i = 0; i < length; i++) {
        if ([component characterAtIndex:i] != '%') continue;
        if (i + 2 >= length ||
            !VCIsASCIIHexDigit([component characterAtIndex:(i + 1)]) ||
            !VCIsASCIIHexDigit([component characterAtIndex:(i + 2)])) {
            return nil;
        }
        i += 2;
    }

    NSString *escaped = [component stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
    NSString *decoded = [escaped stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (![decoded isKindOfClass:[NSString class]]) return nil;
    for (NSUInteger i = 0; i < [decoded length]; i++) {
        unichar value = [decoded characterAtIndex:i];
        if (value < 0x20 || value == 0x7f) return nil;
    }
    return decoded;
}

- (NSString *)canonicalConfigQueryKey:(NSString *)encodedKey {
    NSString *decoded = [self strictDecodedConfigQueryComponent:encodedKey];
    NSData *bytes = [decoded dataUsingEncoding:NSUTF8StringEncoding];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0 ||
        !bytes || [bytes length] > kVCMaximumConfigQueryKeyBytes) {
        return nil;
    }

    for (NSUInteger i = 0; i < [decoded length]; i++) {
        unichar c = [decoded characterAtIndex:i];
        if (c <= 0x20 || c >= 0x7f || c == '&' || c == '=' || c == '#') return nil;
    }

    NSString *key = [decoded lowercaseString];
    if ([key isEqualToString:@"type"] || [key isEqualToString:@"network"] ||
        [key isEqualToString:@"transport"] || [key isEqualToString:@"net"]) {
        return @"transport";
    }
    if ([key isEqualToString:@"allowinsecure"] || [key isEqualToString:@"insecure"]) {
        return @"allowinsecure";
    }
    if ([key isEqualToString:@"servicename"] || [key isEqualToString:@"service_name"]) {
        return @"servicename";
    }
    if ([key isEqualToString:@"xpaddingbytes"] || [key isEqualToString:@"x_padding_bytes"]) {
        return @"xpaddingbytes";
    }
    if ([key isEqualToString:@"scmaxeachpostbytes"] || [key isEqualToString:@"sc_max_each_post_bytes"]) {
        return @"scmaxeachpostbytes";
    }
    return key;
}

- (NSString *)configURIQueryValidationReason:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) {
        return @"empty configuration URI";
    }

    NSData *uriBytes = [uri dataUsingEncoding:NSUTF8StringEncoding];
    if (!uriBytes || [uriBytes length] > kVCMaximumConfigURIBytes) {
        return @"configuration URI is too long";
    }
    if (![[self schemeFromURIString:uri] isEqualToString:@"vless"]) return nil;

    NSRange question = [uri rangeOfString:@"?"];
    NSRange fragment = [uri rangeOfString:@"#"];
    if (question.location == NSNotFound ||
        (fragment.location != NSNotFound && question.location > fragment.location) ||
        question.location + 1 >= [uri length]) {
        return nil;
    }
    NSUInteger queryEnd = fragment.location == NSNotFound ? [uri length] : fragment.location;
    NSString *query = [uri substringWithRange:NSMakeRange(question.location + 1,
                                                           queryEnd - question.location - 1)];
    if ([query length] == 0) return nil;

    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    if ([pairs count] > kVCMaximumConfigQueryParameters) return @"too many query parameters";

    NSMutableSet *seen = [NSMutableSet setWithCapacity:[pairs count]];
    for (id object in pairs) {
        if (![object isKindOfClass:[NSString class]] || [(NSString *)object length] == 0) {
            return @"invalid query parameter";
        }
        NSString *pair = (NSString *)object;
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location == NSNotFound || equals.location == 0) {
            return @"invalid query parameter";
        }

        NSString *key = [self canonicalConfigQueryKey:[pair substringToIndex:equals.location]];
        if (![key isKindOfClass:[NSString class]] || [key length] == 0) {
            return @"invalid query parameter name";
        }
        if ([seen containsObject:key]) return @"duplicate query parameter";
        [seen addObject:key];

        NSString *value = [pair substringFromIndex:(equals.location + 1)];
        if (![self strictDecodedConfigQueryComponent:value]) {
            return @"invalid query parameter encoding";
        }
    }
    return nil;
}

- (NSString *)queryValueForURLString:(NSString *)urlString key:(NSString *)key {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return nil;
    if (![key isKindOfClass:[NSString class]] || [key length] == 0) return nil;

    NSRange q = [urlString rangeOfString:@"?"];
    if (q.location == NSNotFound || q.location + 1 >= [urlString length]) return nil;

    NSString *query = [urlString substringFromIndex:(q.location + 1)];
    NSRange hash = [query rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        query = [query substringToIndex:hash.location];
    }

    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSString *wanted = [self canonicalConfigQueryKey:key];
    if ([wanted length] == 0) return nil;
    for (NSString *pair in pairs) {
        if (![pair isKindOfClass:[NSString class]] || [pair length] == 0) continue;

        NSRange eq = [pair rangeOfString:@"="];
        NSString *rawKey = nil;
        NSString *rawValue = nil;
        if (eq.location == NSNotFound) {
            rawKey = pair;
            rawValue = @"";
        } else {
            rawKey = [pair substringToIndex:eq.location];
            rawValue = [pair substringFromIndex:(eq.location + 1)];
        }

        NSString *decodedKey = [self canonicalConfigQueryKey:rawKey];
        if (![decodedKey isEqualToString:wanted]) continue;

        NSString *decodedValue = [self strictDecodedConfigQueryComponent:rawValue];
        decodedValue = [self safeTrim:decodedValue];
        if ([decodedValue length] > 0) return decodedValue;
    }

    return nil;
}

- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    NSRange at = [uri rangeOfString:@"@"];
    if (at.location == NSNotFound) return NO;

    NSUInteger hostStart = at.location + 1;
    NSUInteger i = hostStart;
    while (i < [uri length]) {
        unichar c = [uri characterAtIndex:i];
        if (c == ':' || c == '?' || c == '/' || c == '#') break;
        i++;
    }
    if (i <= hostStart) return NO;

    NSString *host = [uri substringWithRange:NSMakeRange(hostStart, i - hostStart)];
    uint16_t port = 443;
    if (i < [uri length] && [uri characterAtIndex:i] == ':') {
        NSUInteger pStart = i + 1;
        NSUInteger j = pStart;
        while (j < [uri length]) {
            unichar c = [uri characterAtIndex:j];
            if (c < '0' || c > '9') break;
            j++;
        }
        if (j > pStart) {
            NSInteger p = [[uri substringWithRange:NSMakeRange(pStart, j - pStart)] integerValue];
            if (p > 0 && p <= 65535) port = (uint16_t)p;
        }
    }

    if (hostOut) *hostOut = host;
    if (portOut) *portOut = port;
    return YES;
}

- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri {
    NSString *queryReason = [self configURIQueryValidationReason:uri];
    if ([queryReason length] > 0) return queryReason;

    NSString *scheme = [[self schemeFromURIString:uri] lowercaseString];
    NSString *transport = [[self transportTypeFromURI:uri] lowercaseString];
    NSString *security = [[self securityTypeFromURI:uri] lowercaseString];

    if ([scheme isEqualToString:@"socks5"]) {
        NSString *requestedSecurity = [[self queryValueForURLString:uri key:@"security"] lowercaseString];
        if ([requestedSecurity length] && ![requestedSecurity isEqualToString:@"none"]) return @"SOCKS5 supports only security=none";
        NSString *host = nil;
        uint16_t port = 0;
        if (![self parseSOCKS5Host:&host port:&port fromURI:uri] || [host length] == 0 || port == 0) {
            return @"invalid socks5 endpoint";
        }
        return nil;
    }

    if (![scheme isEqualToString:@"vless"]) {
        return @"protocol must be vless or socks5";
    }

    NSString *flowValue = [self realityFlowFromURI:uri];
    if ([flowValue length] && ![flowValue isEqualToString:@"xtls-rprx-vision"]) return @"unsupported flow";
    if (([security isEqualToString:@"tls"] || [security isEqualToString:@"reality"]) &&
        ![self isSupportedRealityFingerprint:[self realityFingerprintFromURI:uri]]) return @"unsupported fp";

    if ([transport isEqualToString:@"tcp"] && [security isEqualToString:@"none"]) {
        NSString *flow = [self realityFlowFromURI:uri];
        NSString *encryption = [self queryValueForURLString:uri key:@"encryption"];
        if ([flow length] > 0 && (![encryption length] || [encryption isEqualToString:@"none"])) {
            return [NSString stringWithFormat:@"unsupported flow=%@ without security", flow];
        }
        return nil;
    }

    // Supported tuple #1: [vless/tcp/reality] and [vless/tcp/tls]
    BOOL vision = [transport isEqualToString:@"tcp"] &&
                  ([security isEqualToString:@"reality"] || [security isEqualToString:@"tls"]);
    if (vision) {
        NSString *flow = [self realityFlowFromURI:uri];
        if ([flow length] > 0 && ![flow isEqualToString:@"xtls-rprx-vision"]) {
            return [NSString stringWithFormat:@"unsupported flow=%@", flow];
        }

        NSString *fp = [self realityFingerprintFromURI:uri];
        if (![self isSupportedRealityFingerprint:fp]) {
            return [NSString stringWithFormat:@"unsupported fp=%@", fp];
        }

        return nil;
    }

    BOOL xhttpTransport = [transport isEqualToString:@"xhttp"] ||
                          [transport isEqualToString:@"splithttp"];

    if (xhttpTransport && [security isEqualToString:@"none"]) {
        NSString *mode = [[[self queryValueForURLString:uri key:@"mode"] lowercaseString]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([mode length] > 0 &&
            ![mode isEqualToString:@"auto"] &&
            ![mode isEqualToString:@"packet-up"] &&
            ![mode isEqualToString:@"stream-one"] &&
            ![mode isEqualToString:@"stream-up"]) {
            return [NSString stringWithFormat:@"unsupported xhttp/none mode=%@", mode];
        }
        return nil;
    }

    // Supported tuple #2: [vless/xhttp/tls]
    if (xhttpTransport && [security isEqualToString:@"tls"]) {
        NSString *mode = [[[self queryValueForURLString:uri key:@"mode"] lowercaseString]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([mode length] > 0 &&
            ![mode isEqualToString:@"auto"] &&
            ![mode isEqualToString:@"packet-up"] &&
            ![mode isEqualToString:@"stream-one"] &&
            ![mode isEqualToString:@"stream-up"]) {
            return [NSString stringWithFormat:@"unsupported xhttp/tls mode=%@", mode];
        }
        return nil;
    }

    // Supported tuple #3: [vless/xhttp/reality]
    if (xhttpTransport && [security isEqualToString:@"reality"]) {
        NSString *mode = [[[self queryValueForURLString:uri key:@"mode"] lowercaseString]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([mode length] > 0 &&
            ![mode isEqualToString:@"auto"] &&
            ![mode isEqualToString:@"packet-up"] &&
            ![mode isEqualToString:@"stream-one"] &&
            ![mode isEqualToString:@"stream-up"]) {
            return [NSString stringWithFormat:@"unsupported xhttp/reality mode=%@", mode];
        }

        NSString *fp = [self realityFingerprintFromURI:uri];
        if (![self isSupportedRealityFingerprint:fp]) {
            return [NSString stringWithFormat:@"unsupported fp=%@", fp];
        }
        return nil;
    }

    BOOL grpcTransport = [transport isEqualToString:@"grpc"];
    if (grpcTransport &&
        ([security isEqualToString:@"none"] || [security isEqualToString:@"tls"] || [security isEqualToString:@"reality"])) {
        NSString *mode = [[[self queryValueForURLString:uri key:@"mode"] lowercaseString]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([mode length] > 0 && ![mode isEqualToString:@"auto"] &&
            ![mode isEqualToString:@"gun"] && ![mode isEqualToString:@"multi"]) {
            return [NSString stringWithFormat:@"unsupported grpc mode=%@", mode];
        }
        if ([security isEqualToString:@"reality"]) {
            NSString *fp = [self realityFingerprintFromURI:uri];
            if (![self isSupportedRealityFingerprint:fp]) {
                return [NSString stringWithFormat:@"unsupported fp=%@", fp];
            }
        }
        return nil;
    }

    // Supported tuple #4: [vless/ws/tls] and [vless/ws/none]
    if (([transport isEqualToString:@"ws"] || [transport isEqualToString:@"websocket"]) &&
        ([security isEqualToString:@"tls"] || [security isEqualToString:@"none"])) {
        return nil;
    }

    return @"supported sets are vless/tcp/none, vless/tcp/reality, vless/tcp/tls, vless/xhttp/none, vless/xhttp/tls and vless/xhttp/reality with auto, packet-up, stream-one, or stream-up mode, vless/grpc/none, vless/grpc/tls, vless/grpc/reality, vless/ws/tls, vless/ws/none, and [socks5]";
}

- (NSArray *)extractConfigURIsFromText:(NSString *)text {
    if (!text || [text length] == 0) return [NSArray array];

    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *fallbackLines = [NSMutableArray array];
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [self safeTrim:line];
        NSString *lower = [trimmed lowercaseString];
        if ([lower hasPrefix:@"vless://"] || [lower hasPrefix:@"socks5://"]) {
            if (![out containsObject:trimmed]) {
                [out addObject:trimmed];
            }
        } else if ([line length] > 0) {
            [fallbackLines addObject:line];
        }
    }

    NSString *fallbackText = [fallbackLines componentsJoinedByString:@"\n"];
    if ([fallbackText length] == 0) return out;

    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:vless://|socks5://)[^\\s\"'<>]+"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&reErr];
    if (!re || reErr) {
        return out;
    }

    NSArray *matches = [re matchesInString:fallbackText options:0 range:NSMakeRange(0, [fallbackText length])];
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location == NSNotFound || m.range.length == 0) continue;
        NSString *uri = [fallbackText substringWithRange:m.range];

        while ([uri hasSuffix:@","] || [uri hasSuffix:@";"] || [uri hasSuffix:@")"] || [uri hasSuffix:@"]"]) {
            if ([uri length] <= 1) break;
            uri = [uri substringToIndex:([uri length] - 1)];
        }

        if ([uri length] == 0) continue;
        NSString *lower = [uri lowercaseString];
        if (![lower hasPrefix:@"vless://"] && ![lower hasPrefix:@"socks5://"]) continue;
        if (![out containsObject:uri]) {
            [out addObject:uri];
        }
    }
    return out;
}

- (NSArray *)extractImportLinksFromText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
        return [NSArray array];
    }

    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:vless://|socks5://|happ://(?:add|crypt4|crypt5)/|https?://)[^\\s\"'<>]+"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&reErr];
    if (!re || reErr) {
        return [NSArray array];
    }

    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, [text length])];
    NSMutableArray *out = [NSMutableArray array];
    NSCharacterSet *trailSet = [NSCharacterSet characterSetWithCharactersInString:@",;)]}>\"'"];
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location == NSNotFound || m.range.length == 0) continue;
        NSString *link = [text substringWithRange:m.range];
        link = [self safeTrim:link];
        while ([link length] > 0) {
            unichar c = [link characterAtIndex:([link length] - 1)];
            if (![trailSet characterIsMember:c]) break;
            link = [link substringToIndex:([link length] - 1)];
        }
        if ([link length] == 0) continue;

        NSString *lower = [link lowercaseString];
        if (![lower hasPrefix:@"vless://"] &&
            ![lower hasPrefix:@"socks5://"] &&
            ![lower hasPrefix:kHappAddPrefix] &&
            ![lower hasPrefix:@"happ://crypt4/"] &&
            ![lower hasPrefix:@"happ://crypt5/"] &&
            ![lower hasPrefix:@"http://"] &&
            ![lower hasPrefix:@"https://"]) {
            continue;
        }

        if (![out containsObject:link]) {
            [out addObject:link];
        }
    }
    return out;
}

- (NSArray *)extractConfigURIsFromHappJSONData:(NSData *)data {
    if (!data || [data length] == 0) return [NSArray array];

    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!root || error) return [NSArray array];

    NSArray *configs = [self happJSONArrayValue:root];
    if (!configs && [root isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)root;
        configs = [self happJSONArrayValue:[dictionary objectForKey:@"configs"]];
        if (!configs && [dictionary objectForKey:@"outbounds"]) {
            configs = [NSArray arrayWithObject:dictionary];
        }
    }
    if (![configs isKindOfClass:[NSArray class]]) return [NSArray array];

    NSMutableArray *uris = [NSMutableArray array];
    for (id value in configs) {
        NSString *uri = [self vlessURIFromHappJSONConfig:[self happJSONDictionaryValue:value]];
        if ([uri length] == 0 || [uris containsObject:uri]) continue;
        if ([self isSupportedConfigTupleForURI:uri]) [uris addObject:uri];
    }
    return uris;
}

- (NSArray *)parseSubscriptionData:(NSData *)data {
    if (!data || [data length] == 0) return [NSArray array];

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];

    NSArray *uris = [NSArray array];
    if (raw) {
        uris = [self extractConfigURIsFromText:raw];
        if ([uris count] > 0) return [self sanitizeSubscriptionURIs:uris];

        uris = [self extractConfigURIsFromHappJSONData:data];
        if ([uris count] > 0) return [self sanitizeSubscriptionURIs:uris];

        NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        NSData *decoded = DecodeBase64String(b64);
        if (decoded && [decoded length] > 0) {
            NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
            if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
            if (decodedText) {
                uris = [self extractConfigURIsFromText:decodedText];
                if ([uris count] > 0) return [self sanitizeSubscriptionURIs:uris];
            }
        }
    }

    return [NSArray array];
}

- (NSArray *)sanitizeSubscriptionURIs:(NSArray *)uris {
    if (![uris isKindOfClass:[NSArray class]] || [uris count] == 0) {
        return [NSArray array];
    }

    NSMutableArray *clean = [NSMutableArray array];
    BOOL hasReal = NO;
    for (id it in uris) {
        if (![it isKindOfClass:[NSString class]]) continue;
        NSString *uri = (NSString *)it;
        if ([uri length] == 0) continue;
        [clean addObject:uri];
        if (![self isLikelySubscriptionPlaceholderURI:uri]) {
            hasReal = YES;
        }
    }

    if (!hasReal) return clean;

    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *uri in clean) {
        if (![self isLikelySubscriptionPlaceholderURI:uri]) {
            [filtered addObject:uri];
        }
    }

    return ([filtered count] > 0) ? filtered : clean;
}

- (NSDictionary *)subscriptionUserInfoFromHeaderValue:(NSString *)headerValue {
    if (![headerValue isKindOfClass:[NSString class]] || [headerValue length] == 0) return nil;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSArray *parts = [headerValue componentsSeparatedByString:@";"];
    for (NSString *part in parts) {
        if (![part isKindOfClass:[NSString class]]) continue;

        NSRange eq = [part rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;

        NSString *key = [[self safeTrim:[part substringToIndex:eq.location]] lowercaseString];
        BOOL knownKey = [key isEqualToString:kSubscriptionUploadKey] ||
                        [key isEqualToString:kSubscriptionDownloadKey] ||
                        [key isEqualToString:kSubscriptionTotalKey] ||
                        [key isEqualToString:kSubscriptionExpireKey];
        if (!knownKey) continue;

        NSNumber *number = [self subscriptionUnsignedNumberFromString:[part substringFromIndex:(eq.location + 1)]];
        if (number) {
            [info setObject:number forKey:key];
        }
    }
    return ([info count] > 0) ? info : nil;
}

- (NSString *)safeTrim:(NSString *)s {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)schemeFromURIString:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return @"vless";

    NSRange sep = [uri rangeOfString:@"://"];
    if (sep.location == NSNotFound || sep.location == 0) return @"vless";

    NSString *scheme = [self safeTrim:[uri substringToIndex:sep.location]];
    if ([scheme length] == 0) return @"vless";
    return [scheme lowercaseString];
}

- (NSString *)transportTypeFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"tcp";

    NSString *transport = [self queryValueForURLString:uri key:@"type"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"transport"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"network"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"net"];

    transport = [[self safeTrim:transport] lowercaseString];
    if ([transport length] == 0 || [transport isEqualToString:@"raw"]) return @"tcp";
    return transport;
}

- (NSString *)securityTypeFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"plain";

    NSString *security = [self queryValueForURLString:uri key:@"security"];
    security = [self safeTrim:security];
    if ([security length] == 0) return @"none";
    return [security lowercaseString];
}

- (NSString *)realityFlowFromURI:(NSString *)uri {
    NSString *flow = [self queryValueForURLString:uri key:@"flow"];
    return [self safeTrim:flow];
}

- (NSString *)realityFingerprintFromURI:(NSString *)uri {
    NSString *fp = [self queryValueForURLString:uri key:@"fp"];
    fp = [self safeTrim:fp];
    if ([fp length] == 0) return @"chrome";
    return [fp lowercaseString];
}

- (BOOL)isSupportedRealityFingerprint:(NSString *)fp {
    if (![fp isKindOfClass:[NSString class]] || [fp length] == 0) return NO;
    return [fp isEqualToString:@"chrome"] ||
           [fp isEqualToString:@"firefox"] ||
           [fp isEqualToString:@"edge"] ||
           [fp isEqualToString:@"random"] ||
           [fp isEqualToString:@"randomized"] ||
           [fp isEqualToString:@"qq"];
}

- (NSArray *)happJSONArrayValue:(id)value {
    return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : nil;
}

- (NSString *)vlessURIFromHappJSONConfig:(NSDictionary *)config {
    if (![config isKindOfClass:[NSDictionary class]]) return nil;

    NSArray *outbounds = [self happJSONArrayValue:[config objectForKey:@"outbounds"]];
    NSDictionary *proxy = nil;
    for (id value in outbounds) {
        NSDictionary *candidate = [self happJSONDictionaryValue:value];
        NSString *protocol = [[self happJSONStringValue:[candidate objectForKey:@"protocol"]] lowercaseString];
        NSString *tag = [[self happJSONStringValue:[candidate objectForKey:@"tag"]] lowercaseString];
        if ([protocol isEqualToString:@"vless"] && [tag isEqualToString:@"proxy"]) {
            proxy = candidate;
            break;
        }
        if (!proxy && [protocol isEqualToString:@"vless"]) proxy = candidate;
    }
    if (!proxy) return nil;

    NSDictionary *settings = [self happJSONDictionaryValue:[proxy objectForKey:@"settings"]];
    NSArray *vnext = [self happJSONArrayValue:[settings objectForKey:@"vnext"]];
    NSDictionary *server = ([vnext count] > 0) ? [self happJSONDictionaryValue:[vnext objectAtIndex:0]] : nil;
    NSArray *users = [self happJSONArrayValue:[server objectForKey:@"users"]];
    NSDictionary *user = ([users count] > 0) ? [self happJSONDictionaryValue:[users objectAtIndex:0]] : nil;

    NSString *address = [self safeTrim:[self happJSONStringValue:[server objectForKey:@"address"]]];
    NSString *portText = [self safeTrim:[self happJSONStringValue:[server objectForKey:@"port"]]];
    NSString *uuid = [self safeTrim:[self happJSONStringValue:[user objectForKey:@"id"]]];
    if (!VCProfileText([server objectForKey:@"address"]) || !VCProfileText([user objectForKey:@"id"])) return nil;
    id encryptionValue = [user objectForKey:@"encryption"];
    if (encryptionValue && !VCProfileText(encryptionValue)) return nil;
    NSString *encryption = [self safeTrim:encryptionValue];
    if ([address length] == 0 || [portText length] == 0 || [uuid length] == 0) return nil;
    for (NSUInteger i = 0; i < [portText length]; i++) if ([portText characterAtIndex:i] < '0' || [portText characterAtIndex:i] > '9') return nil;
    if ([portText length] > 5) return nil;
    NSInteger port = [portText integerValue];
    if (port <= 0 || port > 65535) return nil;
    if ([encryption length] == 0) encryption = @"none";

    NSDictionary *stream = [self happJSONDictionaryValue:[proxy objectForKey:@"streamSettings"]];
    if ([proxy objectForKey:@"streamSettings"] && !stream) return nil;
    NSString *network = [[self safeTrim:[self happJSONStringValue:[stream objectForKey:@"network"]]] lowercaseString];
    NSString *security = [[self safeTrim:[self happJSONStringValue:[stream objectForKey:@"security"]]] lowercaseString];
    if ([network isEqualToString:@"splithttp"]) network = @"xhttp";
    if ([network length] == 0 || [network isEqualToString:@"raw"]) network = @"tcp";
    if ([security length] == 0) security = @"none";

    BOOL tcpSupported = [network isEqualToString:@"tcp"] &&
                        ([security isEqualToString:@"none"] || [security isEqualToString:@"tls"] || [security isEqualToString:@"reality"]);
    BOOL xhttpSupported = [network isEqualToString:@"xhttp"] &&
                          ([security isEqualToString:@"none"] || [security isEqualToString:@"tls"] || [security isEqualToString:@"reality"]);
    BOOL wsSupported = [network isEqualToString:@"ws"] &&
                       ([security isEqualToString:@"tls"] || [security isEqualToString:@"none"]);
    BOOL grpcSupported = [network isEqualToString:@"grpc"] &&
                         ([security isEqualToString:@"none"] || [security isEqualToString:@"tls"] || [security isEqualToString:@"reality"]);
    if (!tcpSupported && !xhttpSupported && !wsSupported && !grpcSupported) return nil;

    NSMutableArray *query = [NSMutableArray array];
    [self addHappURIQueryValue:encryption key:@"encryption" toParts:query];
    [self addHappURIQueryValue:network key:@"type" toParts:query];
    [self addHappURIQueryValue:security key:@"security" toParts:query];

    NSString *flow = [self safeTrim:[self happJSONStringValue:[user objectForKey:@"flow"]]];
    if ([user objectForKey:@"flow"] && !VCProfileText([user objectForKey:@"flow"])) return nil;
    if ([flow length] > 0) {
        if (tcpSupported && [security isEqualToString:@"none"] && [encryption isEqualToString:@"none"]) return nil;
        if (![flow isEqualToString:@"xtls-rprx-vision"]) return nil;
        [self addHappURIQueryValue:flow key:@"flow" toParts:query];
    }

    NSDictionary *securitySettings = nil;
    if ([security isEqualToString:@"reality"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"realitySettings"]];
    } else if ([security isEqualToString:@"tls"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"tlsSettings"]];
    }
    NSString *securityField = [security isEqualToString:@"tls"] ? @"tlsSettings" : [security isEqualToString:@"reality"] ? @"realitySettings" : nil;
    if (securityField && [stream objectForKey:securityField] && !securitySettings) return nil;

    NSString *sni = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"serverName"]]];
    NSString *fingerprint = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"fingerprint"]]];
    for (NSString *field in @[@"serverName", @"fingerprint", @"shortId", @"spiderX"]) if ([securitySettings objectForKey:field] && !VCProfileText([securitySettings objectForKey:field])) return nil;
    [self addHappURIQueryValue:sni key:@"sni" toParts:query];
    [self addHappURIQueryValue:fingerprint key:@"fp" toParts:query];

    NSArray *alpnValues = [self happJSONArrayValue:[securitySettings objectForKey:@"alpn"]];
    if ([securitySettings objectForKey:@"alpn"] && !alpnValues) return nil;
    NSMutableArray *cleanALPN = [NSMutableArray array];
    for (id value in alpnValues) {
        if (!VCProfileText(value)) return nil;
        NSString *alpn = [self safeTrim:[self happJSONStringValue:value]];
        if ([alpn length] > 0) [cleanALPN addObject:alpn];
    }
    if ([cleanALPN count] > 0) {
        [self addHappURIQueryValue:[cleanALPN componentsJoinedByString:@","] key:@"alpn" toParts:query];
    }

    id allowInsecure = [securitySettings objectForKey:@"allowInsecure"];
    if (allowInsecure && !VCProfileBoolean(allowInsecure)) return nil;
    if ([allowInsecure respondsToSelector:@selector(boolValue)] && [allowInsecure boolValue]) {
        [query addObject:@"allowInsecure=1"];
    }

    if ([security isEqualToString:@"reality"]) {
        BOOL valid = YES;
        id rawKey = VCProfileAlias(securitySettings, @[@"publicKey", @"password"], &valid);
        if (!valid || !VCProfileText(rawKey)) return nil;
        NSString *publicKey = [self safeTrim:rawKey];
        NSString *shortID = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"shortId"]]];
        NSString *spiderX = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"spiderX"]]];
        if ([publicKey length] == 0) return nil;
        [self addHappURIQueryValue:publicKey key:@"pbk" toParts:query];
        [self addHappURIQueryValue:shortID key:@"sid" toParts:query];
        [self addHappURIQueryValue:spiderX key:@"spx" toParts:query];
    }

    if (xhttpSupported) {
        BOOL valid = YES;
        id raw = VCProfileAlias(stream, @[@"xhttpSettings", @"splithttpSettings"], &valid);
        if (!valid || (raw && ![raw isKindOfClass:[NSDictionary class]])) return nil;
        NSDictionary *xhttp = raw;
        NSString *path = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"path"]]];
        NSString *host = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"host"]]];
        NSString *mode = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"mode"]]];
        id rawExtra = [xhttp objectForKey:@"extra"];
        if (rawExtra && ![rawExtra isKindOfClass:[NSDictionary class]]) return nil;
        NSMutableDictionary *extra = [[(rawExtra ? rawExtra : (xhttp ? xhttp : @{})) mutableCopy] autorelease];
        for (NSString *field in @[@"host", @"path", @"mode", @"extra"]) [extra removeObjectForKey:field];
        for (NSString *field in @[@"host", @"path", @"mode"]) if ([xhttp objectForKey:field] && !VCProfileText([xhttp objectForKey:field])) return nil;
        if ([extra objectForKey:@"headers"] && !VCProfileHeaders([extra objectForKey:@"headers"])) return nil;
        if ([extra objectForKey:@"headers"]) {
            NSMutableDictionary *headers = [[[extra objectForKey:@"headers"] mutableCopy] autorelease];
            NSString *headerHost = nil;
            for (NSString *key in [headers allKeys]) if ([[key lowercaseString] isEqual:@"host"]) {
                if (headerHost && ![headerHost isEqual:[headers objectForKey:key]]) return nil;
                headerHost = [headers objectForKey:key];
                [headers removeObjectForKey:key];
            }
            if (![host length]) host = headerHost;
            [extra setObject:headers forKey:@"headers"];
        }
        for (NSString *field in @[@"downloadSettings", @"xmux"]) if ([extra objectForKey:field] && ![[extra objectForKey:field] isKindOfClass:[NSDictionary class]]) return nil;
        for (NSString *field in @[@"noGRPCHeader", @"noSSEHeader", @"xPaddingObfsMode"]) if ([extra objectForKey:field] && !VCProfileBoolean([extra objectForKey:field])) return nil;
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
        [self addHappURIQueryValue:mode key:@"mode" toParts:query];
        [self addHappURIQueryValue:[self happJSONStringFromDictionary:extra] key:@"extra" toParts:query];
    } else if (wsSupported) {
        id rawWS = [stream objectForKey:@"wsSettings"];
        if (rawWS && ![rawWS isKindOfClass:[NSDictionary class]]) return nil;
        NSDictionary *ws = rawWS;
        NSString *path = [self safeTrim:[self happJSONStringValue:[ws objectForKey:@"path"]]];
        id rawHeaders = [ws objectForKey:@"headers"];
        if (rawHeaders && !VCProfileHeaders(rawHeaders)) return nil;
        for (NSString *key in rawHeaders) if ([[key lowercaseString] hasPrefix:@"sec-websocket-"]) return nil;
        NSMutableDictionary *headers = rawHeaders ? [[rawHeaders mutableCopy] autorelease] : [NSMutableDictionary dictionary];
        NSString *host = [self safeTrim:[self happJSONStringValue:[ws objectForKey:@"host"]]];
        NSString *headerHost = nil;
        for (NSString *key in [headers allKeys]) if ([[key lowercaseString] isEqual:@"host"]) {
            if (headerHost && ![headerHost isEqual:[headers objectForKey:key]]) return nil;
            headerHost = [headers objectForKey:key];
            [headers removeObjectForKey:key];
        }
        if (![host length]) host = headerHost;
        for (NSString *field in @[@"host", @"path"]) if ([ws objectForKey:field] && !VCProfileText([ws objectForKey:field])) return nil;
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
        if ([headers count]) [self addHappURIQueryValue:[self happJSONStringFromDictionary:headers] key:@"headers" toParts:query];
        BOOL valid = YES;
        id early = VCProfileAlias(ws, @[@"ed", @"maxEarlyData"], &valid);
        unsigned number = 0;
        if (!valid || (early && !VCProfileUnsigned(early, 16384, &number))) return nil;
        if (early) [self addHappURIQueryValue:[NSString stringWithFormat:@"%u", number] key:@"ed" toParts:query];
        id heartbeat = [ws objectForKey:@"heartbeatPeriod"];
        if (heartbeat && !VCProfileUnsigned(heartbeat, INT_MAX, &number)) return nil;
        if (heartbeat) [self addHappURIQueryValue:[NSString stringWithFormat:@"%u", number] key:@"heartbeatPeriod" toParts:query];
        VCProfileUnknown(ws, @[@"host", @"path", @"headers", @"ed", @"maxEarlyData", @"heartbeatPeriod"], @"wsSettings.");
    } else if (grpcSupported) {
        id rawGRPC = [stream objectForKey:@"grpcSettings"];
        if (rawGRPC && ![rawGRPC isKindOfClass:[NSDictionary class]]) return nil;
        NSDictionary *grpc = rawGRPC;
        BOOL valid = YES;
        id multiMode = VCProfileAlias(grpc, @[@"multiMode", @"multi_mode"], &valid);
        if (!valid || (multiMode && !VCProfileBoolean(multiMode))) return nil;
        if ([multiMode boolValue]) {
            [self addHappURIQueryValue:@"multi" key:@"mode" toParts:query];
        }

        id rawService = VCProfileAlias(grpc, @[@"serviceName", @"service_name"], &valid);
        if (!valid || (rawService && !VCProfileText(rawService))) return nil;
        NSString *serviceName = [self safeTrim:rawService];
        NSString *authority = [self safeTrim:[self happJSONStringValue:[grpc objectForKey:@"authority"]]];
        if ([grpc objectForKey:@"authority"] && !VCProfileText([grpc objectForKey:@"authority"])) return nil;
        [self addHappURIQueryValue:serviceName key:@"serviceName" toParts:query];
        [self addHappURIQueryValue:authority key:@"authority" toParts:query];
        NSArray *fields = @[@"idleTimeout", @"healthCheckTimeout", @"permitWithoutStream", @"initialWindowsSize", @"userAgent"];
        NSArray *aliases = @[@"idle_timeout", @"health_check_timeout", @"permit_without_stream", @"initial_windows_size", @"user_agent"];
        for (NSUInteger i = 0; i < [fields count]; i++) {
            NSString *key = [fields objectAtIndex:i];
            id value = VCProfileAlias(grpc, @[key, [aliases objectAtIndex:i]], &valid);
            if (!valid) return nil;
            if (!value) continue;
            NSString *text = nil;
            unsigned number;
            if (i == 2) { if (!VCProfileBoolean(value)) return nil; text = [value boolValue] ? @"1" : @"0"; }
            else if (i == 4) { if (!VCProfileText(value) || ![value length]) return nil; text = value; }
            else { if (!VCProfileUnsigned(value, i == 3 ? 262144 : INT_MAX, &number)) return nil; if (i == 3 && !number) continue; text = [NSString stringWithFormat:@"%u", number]; }
            [self addHappURIQueryValue:text key:key toParts:query];
        }
        NSMutableArray *known = [NSMutableArray arrayWithArray:fields]; [known addObjectsFromArray:aliases];
        [known addObjectsFromArray:@[@"serviceName", @"service_name", @"authority", @"multiMode", @"multi_mode"]];
        VCProfileUnknown(grpc, known, @"grpcSettings.");
    }

    NSString *authorityHost = address;
    if ([address rangeOfString:@":"].location != NSNotFound && ![address hasPrefix:@"["]) {
        authorityHost = [NSString stringWithFormat:@"[%@]", address];
    }
    NSString *title = [self safeTrim:[self happJSONStringValue:[config objectForKey:@"remarks"]]];
    NSString *fragment = ([title length] > 0)
                             ? [NSString stringWithFormat:@"#%@", [self percentEncodedHappURIValue:title]]
                             : @"";
    NSString *result = [NSString stringWithFormat:@"vless://%@@%@:%ld?%@%@",
                                      uuid,
                                      authorityHost,
                                      (long)port,
                                      [query componentsJoinedByString:@"&"],
                                      fragment];
    return [self configURIQueryValidationReason:result] ? nil : result;
}

- (NSDictionary *)happJSONDictionaryValue:(id)value {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri {
    return ([self unsupportedConfigReasonForURI:uri] == nil);
}

- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    return [uri rangeOfString:@"@0.0.0.0:1?"].location != NSNotFound;
}

- (NSNumber *)subscriptionUnsignedNumberFromString:(NSString *)text {
    NSString *value = [self safeTrim:text];
    if ([value length] == 0) return nil;

    const char *raw = [value UTF8String];
    if (!raw || !*raw || *raw == '-') return nil;

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(raw, &end, 10);
    if (errno == ERANGE || end == raw) return nil;
    while (end && (*end == ' ' || *end == '\t')) end++;
    if (!end || *end != '\0') return nil;
    return [NSNumber numberWithUnsignedLongLong:parsed];
}

- (NSString *)happJSONStringValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return nil;
}

- (void)addHappURIQueryValue:(NSString *)value key:(NSString *)key toParts:(NSMutableArray *)parts {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;
    if (![key isKindOfClass:[NSString class]] || [key length] == 0) return;
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, [self percentEncodedHappURIValue:value]]];
}

- (NSString *)happJSONStringFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]] || [dictionary count] == 0) return nil;
    if (![NSJSONSerialization isValidJSONObject:dictionary]) return nil;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!data || error) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (NSString *)percentEncodedHappURIValue:(NSString *)value {
    if (![value isKindOfClass:[NSString class]]) return @"";
    CFStringRef encoded = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                  (CFStringRef)value,
                                                                  NULL,
                                                                  CFSTR(":/?#[]@!$&'()*+,;=%"),
                                                                  kCFStringEncodingUTF8);
    if (!encoded) return @"";
    return [(NSString *)encoded autorelease];
}

- (NSDictionary *)subscriptionUserInfoFromMetadataText:(NSString *)text {
    NSString *value = [self subscriptionHeaderValueNamed:@"subscription-userinfo" fromMetadataText:text];
    return [self subscriptionUserInfoFromHeaderValue:value];
}

- (NSDictionary *)subscriptionUserInfoFromData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    NSDictionary *info = [self subscriptionUserInfoFromMetadataText:raw];
    if ([info count] > 0) return info;

    NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSData *decoded = DecodeBase64String(b64);
    if (!decoded || [decoded length] == 0) return nil;

    NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
    if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
    return [self subscriptionUserInfoFromMetadataText:decodedText];
}

- (NSDictionary *)subscriptionUserInfoFromHTTPHeaders:(NSDictionary *)headers {
    NSString *value = [self subscriptionHeaderValueNamed:@"subscription-userinfo" fromHTTPHeaders:headers];
    return [self subscriptionUserInfoFromHeaderValue:value];
}

- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromMetadataText:(NSString *)text {
    if (![headerName isKindOfClass:[NSString class]] || [headerName length] == 0) return nil;
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return nil;

    NSString *wanted = [headerName lowercaseString];
    NSString *found = nil;
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (![line isKindOfClass:[NSString class]]) continue;

        NSString *trim = [self safeTrim:line];
        if ([trim hasPrefix:@"#"]) {
            trim = [self safeTrim:[trim substringFromIndex:1]];
        }

        NSRange sep = [trim rangeOfString:@":"];
        if (sep.location == NSNotFound) continue;

        NSString *name = [[self safeTrim:[trim substringToIndex:sep.location]] lowercaseString];
        if (![name isEqualToString:wanted]) continue;

        NSString *value = [self safeTrim:[trim substringFromIndex:(sep.location + 1)]];
        if ([value length] > 0) {
            found = value;
        }
    }
    return found;
}

- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromHTTPHeaders:(NSDictionary *)headers {
    if (![headerName isKindOfClass:[NSString class]] || [headerName length] == 0) return nil;
    if (![headers isKindOfClass:[NSDictionary class]]) return nil;

    NSString *wanted = [headerName lowercaseString];
    for (id key in headers) {
        if (![key isKindOfClass:[NSString class]]) continue;
        if (![[((NSString *)key) lowercaseString] isEqualToString:wanted]) continue;

        id rawValue = [headers objectForKey:key];
        if (![rawValue isKindOfClass:[NSString class]]) continue;
        NSString *value = [self safeTrim:(NSString *)rawValue];
        if ([value length] > 0) return value;
    }
    return nil;
}

@end

VCProfileLogic *VCProfiles(void) {
    static VCProfileLogic *logic = nil;
    @synchronized([VCProfileLogic class]) {
        if (!logic) logic = [[VCProfileLogic alloc] init];
    }
    return logic;
}
