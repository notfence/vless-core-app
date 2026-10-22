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

static BOOL VCProfileHost(NSString *host) {
    NSData *data = [host dataUsingEncoding:NSUTF8StringEncoding];
    if (![data length] || [data length] > 255) return NO;
    const unsigned char *bytes = [data bytes];
    for (NSUInteger i=0;i<[data length];i++)
        if (bytes[i] <= 0x20 || bytes[i] == 0x7f || strchr("/?#@[]\\",bytes[i])) return NO;
    if ([host rangeOfString:@":"].location != NSNotFound) {
        struct in6_addr address;
        return inet_pton(AF_INET6,[host UTF8String],&address) == 1;
    }
    return YES;
}

static BOOL VCProfileUnsignedScalar(id value, unsigned maximum, unsigned *result) {
    if ([value isKindOfClass:[NSNumber class]]) return !VCProfileBoolean(value) && VCProfileUnsigned(value,maximum,result);
    if (![value isKindOfClass:[NSString class]] || ![value length]) return NO;
    unsigned number=0;
    for (NSUInteger i=0;i<[value length];i++) {
        unsigned digit=(unsigned)([value characterAtIndex:i]-'0');
        if (digit > 9 || digit > maximum || number > (maximum-digit)/10) return NO;
        number=number*10+digit;
    }
    *result=number; return YES;
}

static BOOL VCProfileCopyAliases(NSDictionary *source, NSMutableDictionary *destination, NSString *key, NSArray *aliases) {
    BOOL valid=YES; id value=VCProfileAlias(source,aliases,&valid);
    if (valid && value) [destination setObject:value forKey:key];
    return valid;
}

static NSString *VCProfileForbidden(NSDictionary *source, NSArray *fields, NSString *scope) {
    for (NSString *field in fields) if ([source objectForKey:field]) return [scope stringByAppendingString:field];
    return nil;
}

static BOOL VCProfilePort(NSString *text, uint16_t *output) {
    if (![text length]) return NO;
    unsigned value=0;
    for (NSUInteger i=0;i<[text length];i++) {
        unsigned digit=(unsigned)([text characterAtIndex:i]-'0');
        if (digit > 9 || value > (65535U-digit)/10U) return NO;
        value=value*10+digit;
    }
    if (!value) return NO;
    *output=(uint16_t)value; return YES;
}

static BOOL VCProfileEndpoint(NSString *endpoint, uint16_t defaultPort, NSString **hostOut, uint16_t *portOut) {
    NSString *host=nil,*portText=nil;
    if ([endpoint hasPrefix:@"["]) {
        NSRange end=[endpoint rangeOfString:@"]"];
        if (end.location == NSNotFound || end.location < 2) return NO;
        host=[endpoint substringWithRange:NSMakeRange(1,end.location-1)];
        struct in6_addr address;
        if (inet_pton(AF_INET6,[host UTF8String],&address) != 1) return NO;
        if (end.location+1 < [endpoint length]) {
            if ([endpoint characterAtIndex:end.location+1] != ':') return NO;
            portText=[endpoint substringFromIndex:end.location+2];
        }
    } else {
        NSRange colon=[endpoint rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location == NSNotFound) host=endpoint;
        else {
            host=[endpoint substringToIndex:colon.location]; portText=[endpoint substringFromIndex:colon.location+1];
            if ([host rangeOfString:@":"].location != NSNotFound) return NO;
        }
    }
    uint16_t port=defaultPort;
    if (!VCProfileHost(host) || (portText ? !VCProfilePort(portText,&port) : !port)) return NO;
    if (hostOut) *hostOut=host;
    if (portOut) *portOut=port;
    return YES;
}

@implementation VCProfileLogic

- (void)dealloc {
    [_profileMetadata release];
    [super dealloc];
}

- (BOOL)isConfigurationURI:(NSString *)uri {
    return [@[@"vless",@"socks5"] containsObject:[self schemeFromURIString:uri]] && [uri rangeOfString:@"://"].location != NSNotFound;
}

- (NSDictionary *)uncachedMetadataForURI:(NSString *)uri {
    NSString *scheme=[self schemeFromURIString:uri];
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithObject:scheme forKey:@"protocol"];
    NSString *reason=[self configURIQueryValidationReason:uri];
    if (!reason && ![scheme isEqual:@"vless"] && ![scheme isEqual:@"socks5"]) reason=@"unsupported protocol";
    NSRange prefix=[uri rangeOfString:@"://"];
    NSString *host=nil; uint16_t port=0;
    if (!reason && prefix.location != NSNotFound) {
        NSString *authority=[uri substringFromIndex:prefix.location+3];
        NSRange end=[authority rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
        if (end.location != NSNotFound) authority=[authority substringToIndex:end.location];
        NSRange at=[authority rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) authority=[authority substringFromIndex:at.location+1];
        else if (![scheme isEqual:@"socks5"]) reason=@"missing configuration credentials";
        if (!reason && !VCProfileEndpoint(authority,[scheme isEqual:@"socks5"] ? 1080 : 0,&host,&port)) reason=@"invalid server address or port";
    } else if (!reason) reason=@"invalid configuration URI";
    if (host) { [result setObject:host forKey:@"host"]; [result setObject:@(port) forKey:@"port"]; }
    NSString *transport=[[self queryValueForURLString:uri key:@"type"] lowercaseString];
    if (![transport length] || [transport isEqual:@"raw"] || [scheme isEqual:@"socks5"]) transport=@"tcp";
    if ([transport isEqual:@"websocket"]) transport=@"ws";
    if ([transport isEqual:@"splithttp"]) transport=@"xhttp";
    NSString *security=[[self queryValueForURLString:uri key:@"security"] lowercaseString];
    if (![security length]) security=@"none";
    if (!reason && ![@[@"tcp",@"ws",@"grpc",@"xhttp"] containsObject:transport]) reason=@"unsupported transport";
    if (!reason && ![@[@"none",@"tls",@"reality"] containsObject:security]) reason=@"unsupported security";
    if (!reason && [scheme isEqual:@"socks5"] && ![security isEqual:@"none"]) reason=@"SOCKS5 supports only security=none";
    if (!reason && [transport isEqual:@"ws"] && [security isEqual:@"reality"]) reason=@"WebSocket does not support REALITY";
    NSString *flow=[self queryValueForURLString:uri key:@"flow"];
    if (!reason && [flow length] && ![flow isEqual:@"xtls-rprx-vision"]) reason=@"unsupported flow";
    NSString *encryption=[self queryValueForURLString:uri key:@"encryption"];
    if (!reason && [flow length] && [transport isEqual:@"tcp"] && [security isEqual:@"none"] && (![encryption length] || [encryption isEqual:@"none"])) reason=@"Vision requires TLS, REALITY or VLESS Encryption";
    NSString *fp=[[self queryValueForURLString:uri key:@"fp"] lowercaseString];
    if (![fp length]) fp=@"chrome";
    if (!reason && ![security isEqual:@"none"] && ![self isSupportedRealityFingerprint:fp]) reason=@"unsupported fp";
    NSString *mode=[[self queryValueForURLString:uri key:@"mode"] lowercaseString];
    if (!reason && [mode length] && [transport isEqual:@"xhttp"] && ![@[@"auto",@"packet-up",@"stream-up",@"stream-one"] containsObject:mode]) reason=@"unsupported XHTTP mode";
    if (!reason && [mode length] && [transport isEqual:@"grpc"] && ![@[@"auto",@"gun",@"multi"] containsObject:mode]) reason=@"unsupported gRPC mode";
    if (!reason && [transport isEqual:@"ws"]) {
        NSString *wsHost=[self queryValueForURLString:uri key:@"host"];
        if (![wsHost length] && ![security isEqual:@"none"]) wsHost=[self queryValueForURLString:uri key:@"sni"];
        if (![wsHost length]) wsHost=host;
        if (!VCProfileHost(wsHost) && !VCProfileEndpoint(wsHost,443,NULL,NULL)) reason=@"invalid WebSocket host";
    }
    [result setObject:transport forKey:@"transport"]; [result setObject:[scheme isEqual:@"socks5"] ? @"plain" : security forKey:@"security"];
    NSRange fragment=[uri rangeOfString:@"#"];
    if (fragment.location != NSNotFound) {
        NSString *title=[uri substringFromIndex:fragment.location+1];
        title=[self safeTrim:[title stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        if ([title length]) [result setObject:title forKey:@"title"];
    }
    if (reason) [result setObject:reason forKey:@"reason"];
    return [[result copy] autorelease];
}

- (NSDictionary *)metadataForURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]]) return @{@"reason":@"invalid configuration URI",@"protocol":@"unknown"};
    @synchronized(self) {
        NSDictionary *cached=[_profileMetadata objectForKey:uri];
        if (cached) return [[cached retain] autorelease];
    }
    return [self uncachedMetadataForURI:uri];
}

- (void)prepareMetadataForConfigurations:(NSArray *)configs subscriptions:(NSArray *)subscriptions {
    NSMutableSet *uris=[NSMutableSet set];
    for (id config in configs) if ([config isKindOfClass:[NSDictionary class]] && [[config objectForKey:@"uri"] isKindOfClass:[NSString class]]) [uris addObject:[config objectForKey:@"uri"]];
    for (id sub in subscriptions) if ([sub isKindOfClass:[NSDictionary class]] && [[sub objectForKey:@"items"] isKindOfClass:[NSArray class]])
        for (id uri in [sub objectForKey:@"items"]) if ([uri isKindOfClass:[NSString class]]) [uris addObject:uri];
    NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithCapacity:[uris count]];
    for (NSString *uri in uris) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        [metadata setObject:[self metadataForURI:uri] forKey:uri];
        [pool drain];
    }
    @synchronized(self) { [_profileMetadata release]; _profileMetadata=[metadata copy]; }
}

- (BOOL)parseServerHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    NSDictionary *metadata=[self metadataForURI:uri];
    if ([metadata objectForKey:@"reason"] || ![metadata objectForKey:@"host"]) return NO;
    if (hostOut) *hostOut=[metadata objectForKey:@"host"];
    if (portOut) *portOut=(uint16_t)[[metadata objectForKey:@"port"] unsignedIntValue];
    return YES;
}

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

    NSDictionary *importReport=[self subscriptionImportReportFromData:data];
    NSArray *uris = [importReport objectForKey:@"uris"];
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
    [updated removeObjectForKey:@"import_skipped"]; [updated removeObjectForKey:@"import_issues"];
    if ([[importReport objectForKey:@"skipped"] unsignedIntegerValue]) {
        [updated setObject:[importReport objectForKey:@"skipped"] forKey:@"import_skipped"];
        [updated setObject:[importReport objectForKey:@"issues"] forKey:@"import_issues"];
    }
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
    return [[self schemeFromURIString:uri] isEqual:@"socks5"] && [self parseServerHost:hostOut port:portOut fromURI:uri];
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
    if ([key isEqual:@"sessionidplacement"]) return @"sessionplacement";
    if ([key isEqual:@"sessionidkey"]) return @"sessionkey";
    if ([key isEqual:@"maxearlydata"]) return @"ed";
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
        if ([decodedValue length] > 0) return decodedValue;
    }

    return nil;
}

- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    return [[self schemeFromURIString:uri] isEqual:@"vless"] && [self parseServerHost:hostOut port:portOut fromURI:uri];
}

- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri {
    return [[self metadataForURI:uri] objectForKey:@"reason"];
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

- (NSDictionary *)importReportFromHappJSONData:(NSData *)data {
    NSMutableArray *uris=[NSMutableArray array],*issues=[NSMutableArray array];
    NSUInteger skipped=0;
    id root=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *configs=[self happJSONArrayValue:root];
    if (!configs && [root isKindOfClass:[NSDictionary class]]) {
        configs=[self happJSONArrayValue:[root objectForKey:@"configs"]];
        if (!configs && [root objectForKey:@"outbounds"]) configs=@[root];
    }
    for (id value in configs) {
        NSString *uri=[self vlessURIFromHappJSONConfig:[self happJSONDictionaryValue:value]];
        if (![uri length]) {
            skipped++;
            if ([issues count] < 16) [issues addObject:@"configs[]: invalid or unsupported profile settings"];
        } else if (![uris containsObject:uri]) [uris addObject:uri];
    }
    return @{@"uris":uris,@"skipped":@(skipped),@"issues":issues};
}

- (NSArray *)extractConfigURIsFromHappJSONData:(NSData *)data {
    return [[self importReportFromHappJSONData:data] objectForKey:@"uris"];
}

- (NSDictionary *)subscriptionImportReportFromData:(NSData *)data {
    if (!data || ![data length]) return @{@"uris":@[],@"skipped":@0,@"issues":@[]};
    NSString *raw=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw=[[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    NSString *trim=[self safeTrim:raw];
    if ([trim hasPrefix:@"{"] || [trim hasPrefix:@"["]) return [self importReportFromHappJSONData:data];
    NSArray *uris=[self extractConfigURIsFromText:raw];
    if (![uris count]) {
        NSString *base64=[[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        NSData *decoded=DecodeBase64String(base64);
        NSString *text=[[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
        if (!text) text=[[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
        NSString *trimmed=[self safeTrim:text];
        if ([trimmed hasPrefix:@"{"] || [trimmed hasPrefix:@"["]) return [self importReportFromHappJSONData:decoded];
        uris=[self extractConfigURIsFromText:text];
    }
    return @{@"uris":[self sanitizeSubscriptionURIs:uris],@"skipped":@0,@"issues":@[]};
}

- (NSArray *)parseSubscriptionData:(NSData *)data {
    return [[self subscriptionImportReportFromData:data] objectForKey:@"uris"];
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
    return [[self metadataForURI:uri] objectForKey:@"transport"];
}

- (NSString *)securityTypeFromURI:(NSString *)uri {
    return [[self metadataForURI:uri] objectForKey:@"security"];
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
    NSDictionary *mux=[self happJSONDictionaryValue:[proxy objectForKey:@"mux"]];
    if (([proxy objectForKey:@"mux"] && !mux) || ([mux objectForKey:@"enabled"] && !VCProfileBoolean([mux objectForKey:@"enabled"]))) return nil;
    if ([[mux objectForKey:@"enabled"] boolValue] || [proxy objectForKey:@"proxySettings"]) return nil;

    NSDictionary *settings = [self happJSONDictionaryValue:[proxy objectForKey:@"settings"]];
    NSArray *vnext = [self happJSONArrayValue:[settings objectForKey:@"vnext"]];
    NSDictionary *server = ([vnext count] > 0) ? [self happJSONDictionaryValue:[vnext objectAtIndex:0]] : nil;
    NSArray *users = [self happJSONArrayValue:[server objectForKey:@"users"]];
    NSDictionary *user = ([users count] > 0) ? [self happJSONDictionaryValue:[users objectAtIndex:0]] : nil;
    if ([vnext count] != 1 || [users count] != 1) return nil;

    NSString *address = [self happJSONStringValue:[server objectForKey:@"address"]];
    unsigned parsedPort=0;
    if (!VCProfileUnsignedScalar([server objectForKey:@"port"],65535,&parsedPort) || !parsedPort) return nil;
    NSString *portText = [NSString stringWithFormat:@"%u",parsedPort];
    NSString *uuid = [self safeTrim:[self happJSONStringValue:[user objectForKey:@"id"]]];
    if (!VCProfileText([server objectForKey:@"address"]) || !VCProfileHost(address) || !VCProfileText([user objectForKey:@"id"])) return nil;
    id encryptionValue = [user objectForKey:@"encryption"];
    if (encryptionValue && !VCProfileText(encryptionValue)) return nil;
    NSString *encryption = encryptionValue;
    if ([address length] == 0 || [portText length] == 0 || [uuid length] == 0) return nil;
    for (NSUInteger i = 0; i < [portText length]; i++) if ([portText characterAtIndex:i] < '0' || [portText characterAtIndex:i] > '9') return nil;
    if ([portText length] > 5) return nil;
    NSInteger port = [portText integerValue];
    if (port <= 0 || port > 65535) return nil;
    if ([encryption length] == 0) encryption = @"none";

    NSMutableArray *query = [NSMutableArray array];
    [self addHappURIQueryValue:encryption key:@"encryption" toParts:query];
    id flow = [user objectForKey:@"flow"];
    if (flow && (!VCProfileText(flow) || ([flow length] && ![flow isEqual:@"xtls-rprx-vision"]))) return nil;
    [self addHappURIQueryValue:flow key:@"flow" toParts:query];
    id stream = [proxy objectForKey:@"streamSettings"];
    if (![self appendTransportSettings:stream query:query]) return nil;

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
    return [self unsupportedConfigReasonForURI:result] ? nil : result;
}

- (NSDictionary *)happJSONDictionaryValue:(id)value {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

- (BOOL)appendTransportSettings:(NSDictionary *)stream query:(NSMutableArray *)query {
    if (stream && ![stream isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *field in @[@"network",@"security"]) if ([stream objectForKey:field] && !VCProfileText([stream objectForKey:field])) return NO;
    for (NSString *field in @[@"sockopt",@"tcpSettings",@"rawSettings"]) {
        id value=[stream objectForKey:field];
        if (value && (![value isKindOfClass:[NSDictionary class]] || [value count])) return NO;
    }
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
    if (!tcpSupported && !xhttpSupported && !wsSupported && !grpcSupported) return NO;

    [self addHappURIQueryValue:network key:@"type" toParts:query];
    [self addHappURIQueryValue:security key:@"security" toParts:query];
    NSDictionary *securitySettings = nil;
    if ([security isEqualToString:@"reality"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"realitySettings"]];
    } else if ([security isEqualToString:@"tls"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"tlsSettings"]];
    }
    NSString *securityField = [security isEqualToString:@"tls"] ? @"tlsSettings" : [security isEqualToString:@"reality"] ? @"realitySettings" : nil;
    if (securityField && [stream objectForKey:securityField] && !securitySettings) return NO;
    if (VCProfileForbidden(securitySettings,@[@"certificates",@"pinnedPeerCertificateChainSha256",@"pinnedPeerCertificatePublicKeySha256",@"verifyPeerCertInNames",@"disableSystemRoot",@"minVersion",@"maxVersion",@"cipherSuites",@"echConfigList",@"echForceQuery"],@"security.")) return NO;
    VCProfileUnknown(securitySettings,@[@"serverName",@"fingerprint",@"alpn",@"allowInsecure",@"publicKey",@"password",@"shortId",@"spiderX"],securityField ? [securityField stringByAppendingString:@"."] : @"security.");

    NSString *sni = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"serverName"]]];
    NSString *fingerprint = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"fingerprint"]]];
    for (NSString *field in @[@"serverName", @"fingerprint", @"shortId", @"spiderX"]) if ([securitySettings objectForKey:field] && !VCProfileText([securitySettings objectForKey:field])) return NO;
    [self addHappURIQueryValue:sni key:@"sni" toParts:query];
    [self addHappURIQueryValue:fingerprint key:@"fp" toParts:query];

    NSArray *alpnValues = [self happJSONArrayValue:[securitySettings objectForKey:@"alpn"]];
    if ([securitySettings objectForKey:@"alpn"] && !alpnValues) return NO;
    NSMutableArray *cleanALPN = [NSMutableArray array];
    for (id value in alpnValues) {
        if (!VCProfileText(value)) return NO;
        NSString *alpn = [self safeTrim:[self happJSONStringValue:value]];
        if ([alpn length] > 0) [cleanALPN addObject:alpn];
    }
    if ([cleanALPN count] > 0) {
        [self addHappURIQueryValue:[cleanALPN componentsJoinedByString:@","] key:@"alpn" toParts:query];
    }

    id allowInsecure = [securitySettings objectForKey:@"allowInsecure"];
    if (allowInsecure && !VCProfileBoolean(allowInsecure)) return NO;
    if ([allowInsecure respondsToSelector:@selector(boolValue)] && [allowInsecure boolValue]) {
        [query addObject:@"allowInsecure=1"];
    }

    if ([security isEqualToString:@"reality"]) {
        BOOL valid = YES;
        id rawKey = VCProfileAlias(securitySettings, @[@"publicKey", @"password"], &valid);
        if (!valid || !VCProfileText(rawKey)) return NO;
        NSString *publicKey = [self safeTrim:rawKey];
        NSString *shortID = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"shortId"]]];
        NSString *spiderX = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"spiderX"]]];
        if ([publicKey length] == 0) return NO;
        [self addHappURIQueryValue:publicKey key:@"pbk" toParts:query];
        [self addHappURIQueryValue:shortID key:@"sid" toParts:query];
        [self addHappURIQueryValue:spiderX key:@"spx" toParts:query];
    }

    if (xhttpSupported) {
        BOOL valid = YES;
        id raw = VCProfileAlias(stream, @[@"xhttpSettings", @"splithttpSettings"], &valid);
        if (!valid || (raw && ![raw isKindOfClass:[NSDictionary class]])) return NO;
        NSDictionary *xhttp = raw;
        NSString *path = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"path"]]];
        NSString *host = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"host"]]];
        NSString *mode = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"mode"]]];
        id rawExtra = [xhttp objectForKey:@"extra"];
        if (rawExtra && ![rawExtra isKindOfClass:[NSDictionary class]]) return NO;
        NSMutableDictionary *extra = [[(rawExtra ? rawExtra : (xhttp ? xhttp : @{})) mutableCopy] autorelease];
        for (NSString *field in @[@"host", @"path", @"mode", @"extra"]) [extra removeObjectForKey:field];
        for (NSString *field in @[@"host", @"path", @"mode"]) if ([xhttp objectForKey:field] && !VCProfileText([xhttp objectForKey:field])) return NO;
        if ([extra objectForKey:@"headers"] && !VCProfileHeaders([extra objectForKey:@"headers"])) return NO;
        if ([extra objectForKey:@"headers"]) {
            NSMutableDictionary *headers = [[[extra objectForKey:@"headers"] mutableCopy] autorelease];
            NSString *headerHost = nil;
            for (NSString *key in [headers allKeys]) if ([[key lowercaseString] isEqual:@"host"]) {
                if (headerHost && ![headerHost isEqual:[headers objectForKey:key]]) return NO;
                headerHost = [headers objectForKey:key];
                [headers removeObjectForKey:key];
            }
            if (![host length]) host = headerHost;
            [extra setObject:headers forKey:@"headers"];
        }
        for (NSString *field in @[@"downloadSettings", @"xmux"]) if ([extra objectForKey:field] && ![[extra objectForKey:field] isKindOfClass:[NSDictionary class]]) return NO;
        for (NSString *field in @[@"noGRPCHeader", @"noSSEHeader", @"xPaddingObfsMode"]) if ([extra objectForKey:field] && !VCProfileBoolean([extra objectForKey:field])) return NO;
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
        [self addHappURIQueryValue:mode key:@"mode" toParts:query];
        [self addHappURIQueryValue:[self happJSONStringFromDictionary:extra] key:@"extra" toParts:query];
    } else if (wsSupported) {
        id rawWS = [stream objectForKey:@"wsSettings"];
        if (rawWS && ![rawWS isKindOfClass:[NSDictionary class]]) return NO;
        NSDictionary *ws = rawWS;
        NSString *path = [self safeTrim:[self happJSONStringValue:[ws objectForKey:@"path"]]];
        id rawHeaders = [ws objectForKey:@"headers"];
        if (rawHeaders && !VCProfileHeaders(rawHeaders)) return NO;
        for (NSString *key in rawHeaders) if ([[key lowercaseString] hasPrefix:@"sec-websocket-"]) return NO;
        NSMutableDictionary *headers = rawHeaders ? [[rawHeaders mutableCopy] autorelease] : [NSMutableDictionary dictionary];
        NSString *host = [self safeTrim:[self happJSONStringValue:[ws objectForKey:@"host"]]];
        NSString *headerHost = nil;
        for (NSString *key in [headers allKeys]) if ([[key lowercaseString] isEqual:@"host"]) {
            if (headerHost && ![headerHost isEqual:[headers objectForKey:key]]) return NO;
            headerHost = [headers objectForKey:key];
            [headers removeObjectForKey:key];
        }
        if (![host length]) host = headerHost;
        for (NSString *field in @[@"host", @"path"]) if ([ws objectForKey:field] && !VCProfileText([ws objectForKey:field])) return NO;
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
        if ([headers count]) [self addHappURIQueryValue:[self happJSONStringFromDictionary:headers] key:@"headers" toParts:query];
        BOOL valid = YES;
        id early = VCProfileAlias(ws, @[@"ed", @"maxEarlyData"], &valid);
        unsigned number = 0;
        if (!valid || (early && !VCProfileUnsigned(early, 16384, &number))) return NO;
        if (early) [self addHappURIQueryValue:[NSString stringWithFormat:@"%u", number] key:@"ed" toParts:query];
        id heartbeat = [ws objectForKey:@"heartbeatPeriod"];
        if (heartbeat && !VCProfileUnsigned(heartbeat, INT_MAX, &number)) return NO;
        if (heartbeat) [self addHappURIQueryValue:[NSString stringWithFormat:@"%u", number] key:@"heartbeatPeriod" toParts:query];
        VCProfileUnknown(ws, @[@"host", @"path", @"headers", @"ed", @"maxEarlyData", @"heartbeatPeriod"], @"wsSettings.");
    } else if (grpcSupported) {
        id rawGRPC = [stream objectForKey:@"grpcSettings"];
        if (rawGRPC && ![rawGRPC isKindOfClass:[NSDictionary class]]) return NO;
        NSDictionary *grpc = rawGRPC;
        BOOL valid = YES;
        id multiMode = VCProfileAlias(grpc, @[@"multiMode", @"multi_mode"], &valid);
        if (!valid || (multiMode && !VCProfileBoolean(multiMode))) return NO;
        if ([multiMode boolValue]) {
            [self addHappURIQueryValue:@"multi" key:@"mode" toParts:query];
        }

        id rawService = VCProfileAlias(grpc, @[@"serviceName", @"service_name"], &valid);
        if (!valid || (rawService && !VCProfileText(rawService))) return NO;
        NSString *serviceName = [self safeTrim:rawService];
        NSString *authority = [self safeTrim:[self happJSONStringValue:[grpc objectForKey:@"authority"]]];
        if ([grpc objectForKey:@"authority"] && !VCProfileText([grpc objectForKey:@"authority"])) return NO;
        [self addHappURIQueryValue:serviceName key:@"serviceName" toParts:query];
        [self addHappURIQueryValue:authority key:@"authority" toParts:query];
        NSArray *fields = @[@"idleTimeout", @"healthCheckTimeout", @"permitWithoutStream", @"initialWindowsSize", @"userAgent"];
        NSArray *aliases = @[@"idle_timeout", @"health_check_timeout", @"permit_without_stream", @"initial_windows_size", @"user_agent"];
        for (NSUInteger i = 0; i < [fields count]; i++) {
            NSString *key = [fields objectAtIndex:i];
            id value = VCProfileAlias(grpc, @[key, [aliases objectAtIndex:i]], &valid);
            if (!valid) return NO;
            if (!value) continue;
            NSString *text = nil;
            unsigned number;
            if (i == 2) { if (!VCProfileBoolean(value)) return NO; text = [value boolValue] ? @"1" : @"0"; }
            else if (i == 4) { if (!VCProfileText(value) || ![value length]) return NO; text = value; }
            else { if (!VCProfileUnsigned(value, i == 3 ? 262144 : INT_MAX, &number)) return NO; if (i == 3 && !number) continue; text = [NSString stringWithFormat:@"%u", number]; }
            [self addHappURIQueryValue:text key:key toParts:query];
        }
        NSMutableArray *known = [NSMutableArray arrayWithArray:fields]; [known addObjectsFromArray:aliases];
        [known addObjectsFromArray:@[@"serviceName", @"service_name", @"authority", @"multiMode", @"multi_mode"]];
        VCProfileUnknown(grpc, known, @"grpcSettings.");
    }
    return YES;
}

- (NSString *)URIFromKaringServer:(NSDictionary *)server error:(NSString **)error {
    if (error) *error=@"invalid or unsupported Karing profile";
    if (![server isKindOfClass:[NSDictionary class]]) return nil;
    NSString *protocol=[[server objectForKey:@"type"] isKindOfClass:[NSString class]] ? [[server objectForKey:@"type"] lowercaseString] : nil;
    if (![protocol isEqual:@"vless"] && ![protocol isEqual:@"socks"] && ![protocol isEqual:@"socks5"]) return nil;
    unsigned port=0;
    if (!VCProfileText([server objectForKey:@"server"]) || !VCProfileUnsignedScalar([server objectForKey:@"server_port"],65535,&port) || !port) return nil;
    if ([protocol isEqual:@"socks"] || [protocol isEqual:@"socks5"]) {
        id username=[server objectForKey:@"username"] ?: @"",password=[server objectForKey:@"password"] ?: @"";
        if (![username isKindOfClass:[NSString class]] || ![password isKindOfClass:[NSString class]]) return nil;
        NSString *host=[server objectForKey:@"server"];
        if ([host rangeOfString:@":"].location != NSNotFound) host=[NSString stringWithFormat:@"[%@]",host];
        NSString *credentials=[username length] || [password length] ? [NSString stringWithFormat:@"%@:%@@",[self percentEncodedHappURIValue:username],[self percentEncodedHappURIValue:password]] : @"";
        NSString *title=[server objectForKey:@"tag"];
        if (title && !VCProfileText(title)) return nil;
        NSString *uri=[NSString stringWithFormat:@"socks5://%@%@:%u%@",credentials,host,port,[title length] ? [@"#" stringByAppendingString:[self percentEncodedHappURIValue:title]] : @""];
        if ([self unsupportedConfigReasonForURI:uri]) return nil;
        if (error) *error=nil;
        return uri;
    }
    NSMutableDictionary *user=[NSMutableDictionary dictionary];
    for (NSString *field in @[@"uuid",@"encryption",@"flow"]) {
        id value=[server objectForKey:field];
        if (value) [user setObject:value forKey:[field isEqual:@"uuid"] ? @"id" : field];
    }
    id rawTLS=[server objectForKey:@"tls"],rawTransport=[server objectForKey:@"transport"];
    if ((rawTLS && ![rawTLS isKindOfClass:[NSDictionary class]]) || (rawTransport && ![rawTransport isKindOfClass:[NSDictionary class]])) return nil;
    NSDictionary *tls=rawTLS,*transport=rawTransport;
    NSString *forbidden=VCProfileForbidden(tls,@[@"certificate",@"certificate_path",@"certificate_public_key_sha256",@"disable_sni",@"min_version",@"max_version",@"cipher_suites",@"ech",@"fragment",@"record_fragment"],@"tls.");
    if (forbidden) { if (error) *error=[@"unsupported field " stringByAppendingString:forbidden]; return nil; }
    for (NSString *field in @[@"enabled",@"insecure"]) if ([tls objectForKey:field] && !VCProfileBoolean([tls objectForKey:field])) return nil;
    NSDictionary *reality=[self happJSONDictionaryValue:[tls objectForKey:@"reality"]];
    NSDictionary *utls=[self happJSONDictionaryValue:[tls objectForKey:@"utls"]];
    if (([tls objectForKey:@"reality"] && !reality) || ([tls objectForKey:@"utls"] && !utls)) return nil;
    for (NSDictionary *settings in @[reality ?: @{},utls ?: @{}]) if ([settings objectForKey:@"enabled"] && !VCProfileBoolean([settings objectForKey:@"enabled"])) return nil;
    if ([utls objectForKey:@"enabled"] && ![[utls objectForKey:@"enabled"] boolValue]) return nil;
    BOOL tlsEnabled=tls && (![tls objectForKey:@"enabled"] || [[tls objectForKey:@"enabled"] boolValue]);
    BOOL useReality=reality && (![reality objectForKey:@"enabled"] || [[reality objectForKey:@"enabled"] boolValue]);
    if (useReality && !tlsEnabled) return nil;
    NSMutableDictionary *security=[NSMutableDictionary dictionary];
    if (!VCProfileCopyAliases(tls,security,@"serverName",@[@"server_name",@"serverName"])) return nil;
    if ([tls objectForKey:@"insecure"]) [security setObject:[tls objectForKey:@"insecure"] forKey:@"allowInsecure"];
    if ([utls objectForKey:@"fingerprint"]) [security setObject:[utls objectForKey:@"fingerprint"] forKey:@"fingerprint"];
    if ([tls objectForKey:@"alpn"]) {
        id alpn=[tls objectForKey:@"alpn"];
        if ([alpn isKindOfClass:[NSString class]]) alpn=[alpn componentsSeparatedByString:@","];
        [security setObject:alpn forKey:@"alpn"];
    }
    if (useReality) {
        if (!VCProfileCopyAliases(reality,security,@"publicKey",@[@"public_key",@"publicKey"]) ||
            !VCProfileCopyAliases(reality,security,@"shortId",@[@"short_id",@"shortId"]) ||
            !VCProfileCopyAliases(reality,security,@"spiderX",@[@"spider_x",@"spiderX"])) return nil;
    }
    id rawType=[transport objectForKey:@"type"];
    if (rawType && !VCProfileText(rawType)) return nil;
    NSString *network=[rawType lowercaseString] ?: @"tcp";
    if ([network isEqual:@"raw"]) network=@"tcp";
    if ([network isEqual:@"splithttp"]) network=@"xhttp";
    if ([network isEqual:@"websocket"]) network=@"ws";
    NSMutableDictionary *settings=transport ? [[transport mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    [settings removeObjectForKey:@"type"];
    NSArray *pairs=@[@[@"maxEarlyData",@"max_early_data",@"maxEarlyData",@"ed"],@[@"heartbeatPeriod",@"heartbeat_period",@"heartbeatPeriod"],@[@"serviceName",@"service_name",@"serviceName"],@[@"multiMode",@"multi_mode",@"multiMode"],@[@"idleTimeout",@"idle_timeout",@"idleTimeout"],@[@"healthCheckTimeout",@"health_check_timeout",@"healthCheckTimeout"],@[@"permitWithoutStream",@"permit_without_stream",@"permitWithoutStream"],@[@"initialWindowsSize",@"initial_windows_size",@"initialWindowsSize"],@[@"userAgent",@"user_agent",@"userAgent"]];
    for (NSArray *pair in pairs) {
        NSArray *aliases=[pair subarrayWithRange:NSMakeRange(1,[pair count]-1)];
        for (NSString *alias in aliases) [settings removeObjectForKey:alias];
        if (!VCProfileCopyAliases(transport,settings,[pair objectAtIndex:0],aliases)) return nil;
    }
    id earlyHeader=[settings objectForKey:@"early_data_header_name"];
    if (earlyHeader && ![earlyHeader isEqual:@"Sec-WebSocket-Protocol"]) return nil;
    [settings removeObjectForKey:@"early_data_header_name"];
    id rawHeaders=[settings objectForKey:@"headers"];
    if (rawHeaders && ![rawHeaders isKindOfClass:[NSDictionary class]]) return nil;
    if (rawHeaders) {
        NSMutableDictionary *headers=[NSMutableDictionary dictionary];
        for (id key in rawHeaders) {
            id value=[rawHeaders objectForKey:key];
            if ([value isKindOfClass:[NSArray class]]) { if ([value count] != 1) return nil; value=[value objectAtIndex:0]; }
            if (!VCProfileText(key) || !VCProfileText(value)) return nil;
            [headers setObject:value forKey:key];
        }
        [settings setObject:headers forKey:@"headers"];
    }
    NSMutableDictionary *stream=[NSMutableDictionary dictionaryWithObjectsAndKeys:network,@"network",useReality ? @"reality" : tlsEnabled ? @"tls" : @"none",@"security",nil];
    [stream setObject:security forKey:useReality ? @"realitySettings" : @"tlsSettings"];
    NSString *settingsKey=[@{@"tcp":@"tcpSettings",@"ws":@"wsSettings",@"grpc":@"grpcSettings",@"xhttp":@"xhttpSettings"} objectForKey:network];
    if (!settingsKey) return nil;
    if ([network isEqual:@"tcp"] && [settings count]) return nil;
    [stream setObject:settings forKey:settingsKey];
    NSDictionary *outbound=@{@"protocol":protocol,@"settings":@{@"vnext":@[@{@"address":[server objectForKey:@"server"],@"port":@(port),@"users":@[user]}]},@"streamSettings":stream};
    NSDictionary *config=@{@"remarks":[server objectForKey:@"tag"] ?: @"",@"outbounds":@[outbound]};
    NSString *uri=[self vlessURIFromHappJSONConfig:config];
    if (uri && error) *error=nil;
    return uri;
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
