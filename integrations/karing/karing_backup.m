#import "karing_backup.h"

#include <arpa/inet.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

static uint16_t VCReadLE16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t VCReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void VCSetError(NSString **errorText, NSString *message) {
    if (errorText) *errorText = message;
}

BOOL VCKaringBackupDataLooksLikeZip(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || [data length] < 4) return NO;
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    return VCReadLE32(bytes) == 0x04034b50U;
}

static NSData *VCInflateRawData(const uint8_t *input,
                                uint32_t compressedSize,
                                uint32_t uncompressedSize,
                                NSString **errorText) {
    if (uncompressedSize == 0) return [NSData data];

    NSMutableData *output = [NSMutableData dataWithLength:uncompressedSize];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = compressedSize;
    stream.next_out = (Bytef *)[output mutableBytes];
    stream.avail_out = uncompressedSize;

    int rc = inflateInit2(&stream, -MAX_WBITS);
    if (rc != Z_OK) {
        VCSetError(errorText, @"Unable to initialize ZIP decompression");
        return nil;
    }
    rc = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    if (rc != Z_STREAM_END || stream.total_out != uncompressedSize) {
        VCSetError(errorText, @"The Karing backup contains invalid compressed data");
        return nil;
    }
    return output;
}

static NSData *VCZipEntryData(NSData *archive, NSString *wantedName, NSString **errorText) {
    const uint8_t *bytes = (const uint8_t *)[archive bytes];
    NSUInteger length = [archive length];
    if (length < 22) {
        VCSetError(errorText, @"The Karing backup is not a valid ZIP file");
        return nil;
    }

    NSUInteger searchStart = (length > (NSUInteger)(0xffff + 22))
        ? length - (NSUInteger)(0xffff + 22)
        : 0;
    NSUInteger eocd = NSNotFound;
    for (NSUInteger pos = length - 22;; pos--) {
        if (VCReadLE32(bytes + pos) == 0x06054b50U) {
            eocd = pos;
            break;
        }
        if (pos == searchStart) break;
    }
    if (eocd == NSNotFound || eocd + 22 > length) {
        VCSetError(errorText, @"The Karing backup has no ZIP directory");
        return nil;
    }

    uint16_t disk = VCReadLE16(bytes + eocd + 4);
    uint16_t directoryDisk = VCReadLE16(bytes + eocd + 6);
    uint16_t entriesOnDisk = VCReadLE16(bytes + eocd + 8);
    uint16_t entries = VCReadLE16(bytes + eocd + 10);
    uint32_t directorySize = VCReadLE32(bytes + eocd + 12);
    uint32_t directoryOffset = VCReadLE32(bytes + eocd + 16);
    uint16_t zipCommentLength = VCReadLE16(bytes + eocd + 20);
    if (disk != 0 || directoryDisk != 0 || entries != entriesOnDisk ||
        entries == 0xffff || directorySize == 0xffffffffU ||
        directoryOffset == 0xffffffffU ||
        (uint64_t)eocd + 22 + zipCommentLength > length ||
        (uint64_t)directoryOffset + directorySize > eocd) {
        VCSetError(errorText, @"Unsupported Karing backup ZIP layout");
        return nil;
    }

    NSUInteger pos = directoryOffset;
    NSUInteger directoryEnd = directoryOffset + directorySize;
    for (uint16_t index = 0; index < entries; index++) {
        if (pos + 46 > directoryEnd || pos + 46 > length ||
            VCReadLE32(bytes + pos) != 0x02014b50U) {
            VCSetError(errorText, @"The Karing backup ZIP directory is damaged");
            return nil;
        }

        uint16_t flags = VCReadLE16(bytes + pos + 8);
        uint16_t method = VCReadLE16(bytes + pos + 10);
        uint32_t expectedCRC = VCReadLE32(bytes + pos + 16);
        uint32_t compressedSize = VCReadLE32(bytes + pos + 20);
        uint32_t uncompressedSize = VCReadLE32(bytes + pos + 24);
        uint16_t nameLength = VCReadLE16(bytes + pos + 28);
        uint16_t extraLength = VCReadLE16(bytes + pos + 30);
        uint16_t commentLength = VCReadLE16(bytes + pos + 32);
        uint16_t startDisk = VCReadLE16(bytes + pos + 34);
        uint32_t localOffset = VCReadLE32(bytes + pos + 42);
        uint64_t next = (uint64_t)pos + 46 + nameLength + extraLength + commentLength;
        if (startDisk != 0 || next > directoryEnd || next > length) {
            VCSetError(errorText, @"The Karing backup ZIP directory is truncated");
            return nil;
        }

        NSData *nameData = [NSData dataWithBytes:bytes + pos + 46 length:nameLength];
        NSString *name = [[[NSString alloc] initWithData:nameData
                                                 encoding:NSUTF8StringEncoding] autorelease];
        if (!name) {
            name = [[[NSString alloc] initWithData:nameData
                                           encoding:NSISOLatin1StringEncoding] autorelease];
        }
        NSString *lastComponent = [name lastPathComponent];
        if ([lastComponent isEqualToString:wantedName]) {
            if ((flags & 1U) != 0 || (method != 0 && method != 8) ||
                compressedSize == 0xffffffffU || uncompressedSize == 0xffffffffU ||
                compressedSize > 32U * 1024U * 1024U ||
                uncompressedSize > 16U * 1024U * 1024U) {
                VCSetError(errorText, @"Unsupported compression in the Karing backup");
                return nil;
            }
            if ((uint64_t)localOffset + 30 > directoryOffset ||
                VCReadLE32(bytes + localOffset) != 0x04034b50U) {
                VCSetError(errorText, @"The Karing subscription entry is damaged");
                return nil;
            }

            uint16_t localNameLength = VCReadLE16(bytes + localOffset + 26);
            uint16_t localExtraLength = VCReadLE16(bytes + localOffset + 28);
            uint64_t dataOffset = (uint64_t)localOffset + 30 + localNameLength + localExtraLength;
            if (dataOffset + compressedSize > directoryOffset) {
                VCSetError(errorText, @"The Karing subscription entry is truncated");
                return nil;
            }

            NSData *result = nil;
            if (method == 0) {
                if (compressedSize != uncompressedSize) {
                    VCSetError(errorText, @"Invalid stored entry in the Karing backup");
                    return nil;
                }
                result = [NSData dataWithBytes:bytes + dataOffset length:uncompressedSize];
            } else {
                result = VCInflateRawData(bytes + dataOffset,
                                          compressedSize,
                                          uncompressedSize,
                                          errorText);
            }
            if (!result) return nil;

            uLong actualCRC = crc32(0L, Z_NULL, 0);
            actualCRC = crc32(actualCRC, (const Bytef *)[result bytes], (uInt)[result length]);
            if ((uint32_t)actualCRC != expectedCRC) {
                VCSetError(errorText, @"The Karing subscription data failed its integrity check");
                return nil;
            }
            return result;
        }
        pos = (NSUInteger)next;
    }

    VCSetError(errorText, @"This ZIP file does not contain a Karing subscription backup");
    return nil;
}

static NSString *VCTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *VCPercentEncode(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    NSMutableString *encoded = [NSMutableString string];
    for (NSUInteger i = 0; i < [data length]; i++) {
        uint8_t c = bytes[i];
        BOOL unreserved = (c >= 'A' && c <= 'Z') ||
                          (c >= 'a' && c <= 'z') ||
                          (c >= '0' && c <= '9') ||
                          c == '-' || c == '.' || c == '_' || c == '~';
        if (unreserved) {
            [encoded appendFormat:@"%c", c];
        } else {
            [encoded appendFormat:@"%%%02X", c];
        }
    }
    return encoded;
}

static NSString *VCStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return VCTrimmedString(value);
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return @"";
}

static NSDictionary *VCDictionaryValue(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *VCFirstHeaderValue(id value) {
    if ([value isKindOfClass:[NSArray class]] && [value count] > 0) {
        return VCStringValue([value objectAtIndex:0]);
    }
    return VCStringValue(value);
}

static void VCAddQueryPart(NSMutableArray *parts, NSString *key, NSString *value) {
    if ([value length] == 0) return;
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, VCPercentEncode(value)]];
}

static NSString *VCVLESSURIFromKaringServer(NSDictionary *server) {
    if (![[VCStringValue([server objectForKey:@"type"]) lowercaseString] isEqualToString:@"vless"]) return nil;

    NSString *address = VCStringValue([server objectForKey:@"server"]);
    NSInteger port = [[server objectForKey:@"server_port"] integerValue];
    NSString *uuid = VCStringValue([server objectForKey:@"uuid"]);
    if ([address length] == 0 || port < 1 || port > 65535 || [uuid length] == 0) return nil;

    NSMutableArray *query = [NSMutableArray arrayWithObject:@"encryption=none"];
    VCAddQueryPart(query, @"flow", VCStringValue([server objectForKey:@"flow"]));

    NSDictionary *tls = VCDictionaryValue([server objectForKey:@"tls"]);
    NSDictionary *reality = VCDictionaryValue([tls objectForKey:@"reality"]);
    NSString *publicKey = VCStringValue([reality objectForKey:@"public_key"]);
    BOOL tlsEnabled = tls && (![tls objectForKey:@"enabled"] || [[tls objectForKey:@"enabled"] boolValue]);
    NSString *security = ([publicKey length] > 0) ? @"reality" : (tlsEnabled ? @"tls" : @"none");
    VCAddQueryPart(query, @"security", security);
    if (tlsEnabled || [publicKey length] > 0) {
        VCAddQueryPart(query, @"sni", VCStringValue([tls objectForKey:@"server_name"]));
        if ([[tls objectForKey:@"insecure"] boolValue]) VCAddQueryPart(query, @"allowInsecure", @"1");

        NSDictionary *utls = VCDictionaryValue([tls objectForKey:@"utls"]);
        VCAddQueryPart(query, @"fp", VCStringValue([utls objectForKey:@"fingerprint"]));
        id alpnValue = [tls objectForKey:@"alpn"];
        if ([alpnValue isKindOfClass:[NSArray class]]) {
            VCAddQueryPart(query, @"alpn", [alpnValue componentsJoinedByString:@","]);
        } else {
            VCAddQueryPart(query, @"alpn", VCStringValue(alpnValue));
        }
    }
    if ([publicKey length] > 0) {
        VCAddQueryPart(query, @"pbk", publicKey);
        VCAddQueryPart(query, @"sid", VCStringValue([reality objectForKey:@"short_id"]));
    }

    NSDictionary *transport = VCDictionaryValue([server objectForKey:@"transport"]);
    NSString *transportType = [VCStringValue([transport objectForKey:@"type"]) lowercaseString];
    if ([transportType length] == 0) transportType = @"tcp";
    if ([transportType isEqualToString:@"tcp"]) {
        VCAddQueryPart(query, @"type", @"tcp");
    } else if ([transportType isEqualToString:@"ws"]) {
        VCAddQueryPart(query, @"type", @"ws");
        VCAddQueryPart(query, @"path", VCStringValue([transport objectForKey:@"path"]));
        NSDictionary *headers = VCDictionaryValue([transport objectForKey:@"headers"]);
        NSString *host = VCFirstHeaderValue([headers objectForKey:@"Host"]);
        if ([host length] == 0) host = VCFirstHeaderValue([headers objectForKey:@"host"]);
        VCAddQueryPart(query, @"host", host);
    } else if ([transportType isEqualToString:@"grpc"]) {
        VCAddQueryPart(query, @"type", @"grpc");
        NSString *serviceName = VCStringValue([transport objectForKey:@"service_name"]);
        if ([serviceName length] == 0) serviceName = VCStringValue([transport objectForKey:@"serviceName"]);
        VCAddQueryPart(query, @"serviceName", serviceName);
        VCAddQueryPart(query, @"authority", VCStringValue([transport objectForKey:@"authority"]));
        if ([[transport objectForKey:@"multi_mode"] boolValue] ||
            [[transport objectForKey:@"multiMode"] boolValue]) {
            VCAddQueryPart(query, @"mode", @"multi");
        }
    } else if ([transportType isEqualToString:@"xhttp"] ||
               [transportType isEqualToString:@"splithttp"]) {
        VCAddQueryPart(query, @"type", @"xhttp");
        VCAddQueryPart(query, @"path", VCStringValue([transport objectForKey:@"path"]));
        VCAddQueryPart(query, @"host", VCFirstHeaderValue([transport objectForKey:@"host"]));
        VCAddQueryPart(query, @"mode", VCStringValue([transport objectForKey:@"mode"]));
    } else {
        return nil;
    }

    NSString *authority = address;
    if ([address rangeOfString:@":"].location != NSNotFound && ![address hasPrefix:@"["]) {
        authority = [NSString stringWithFormat:@"[%@]", address];
    }
    NSString *tag = VCStringValue([server objectForKey:@"tag"]);
    NSString *fragment = ([tag length] > 0)
        ? [NSString stringWithFormat:@"#%@", VCPercentEncode(tag)]
        : @"";
    return [NSString stringWithFormat:@"vless://%@@%@:%ld?%@%@",
            VCPercentEncode(uuid),
            authority,
            (long)port,
            [query componentsJoinedByString:@"&"],
            fragment];
}

static NSString *VCSOCKSURIFromKaringServer(NSDictionary *server) {
    NSString *type = [VCStringValue([server objectForKey:@"type"]) lowercaseString];
    if (![type isEqualToString:@"socks"] && ![type isEqualToString:@"socks5"]) return nil;

    NSString *address = VCStringValue([server objectForKey:@"server"]);
    NSInteger port = [[server objectForKey:@"server_port"] integerValue];
    if ([address length] == 0 || port < 1 || port > 65535) return nil;

    NSString *authority = address;
    if ([address rangeOfString:@":"].location != NSNotFound && ![address hasPrefix:@"["]) {
        authority = [NSString stringWithFormat:@"[%@]", address];
    }
    NSString *user = VCStringValue([server objectForKey:@"username"]);
    NSString *password = VCStringValue([server objectForKey:@"password"]);
    NSString *credentials = ([user length] > 0 || [password length] > 0)
        ? [NSString stringWithFormat:@"%@:%@@", VCPercentEncode(user), VCPercentEncode(password)]
        : @"";
    NSString *tag = VCStringValue([server objectForKey:@"tag"]);
    NSString *fragment = ([tag length] > 0)
        ? [NSString stringWithFormat:@"#%@", VCPercentEncode(tag)]
        : @"";
    return [NSString stringWithFormat:@"socks5://%@%@:%ld%@",
            credentials, authority, (long)port, fragment];
}

static NSArray *VCConfigURIsFromKaringGroup(NSDictionary *item) {
    id serversValue = [item objectForKey:@"servers"];
    if (![serversValue isKindOfClass:[NSArray class]]) return [NSArray array];

    NSMutableArray *uris = [NSMutableArray array];
    for (id value in (NSArray *)serversValue) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSString *uri = VCVLESSURIFromKaringServer(value);
        if ([uri length] == 0) uri = VCSOCKSURIFromKaringServer(value);
        if ([uri length] > 0 && ![uris containsObject:uri]) [uris addObject:uri];
    }
    return uris;
}

NSArray *VCKaringSubscriptionsFromBackupData(NSData *data, NSString **errorText) {
    if (errorText) *errorText = nil;
    if (!VCKaringBackupDataLooksLikeZip(data)) {
        VCSetError(errorText, @"The selected file is not a Karing backup");
        return nil;
    }

    NSData *jsonData = VCZipEntryData(data, @"karing_subscribe.json", errorText);
    if (!jsonData) return nil;

    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    if (![root isKindOfClass:[NSDictionary class]] || jsonError) {
        VCSetError(errorText, @"The Karing subscription backup contains invalid JSON");
        return nil;
    }

    id itemsValue = [(NSDictionary *)root objectForKey:@"items"];
    if (![itemsValue isKindOfClass:[NSArray class]]) {
        VCSetError(errorText, @"The Karing backup has no subscription list");
        return nil;
    }

    NSMutableArray *subscriptions = [NSMutableArray array];
    NSMutableSet *seenURLs = [NSMutableSet set];
    for (id value in (NSArray *)itemsValue) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *item = (NSDictionary *)value;
        NSString *url = VCTrimmedString([item objectForKey:@"urlOrPath"]);
        if ([url length] == 0) url = VCTrimmedString([item objectForKey:@"url"]);
        NSURL *parsedURL = [NSURL URLWithString:url];
        NSString *scheme = [[parsedURL scheme] lowercaseString];
        if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) continue;
        if ([seenURLs containsObject:url]) continue;

        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject:url forKey:@"url"];
        NSArray *configs = VCConfigURIsFromKaringGroup(item);
        if ([configs count] > 0) [entry setObject:configs forKey:@"items"];
        [subscriptions addObject:entry];
        [seenURLs addObject:url];
    }

    if ([subscriptions count] == 0) {
        VCSetError(errorText, @"The Karing backup has no HTTP or HTTPS subscriptions");
        return nil;
    }
    return subscriptions;
}

static NSDictionary *VCQueryParameters(NSString *query) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *part in [query componentsSeparatedByString:@"&"]) {
        NSRange equals = [part rangeOfString:@"="];
        NSString *key = (equals.location == NSNotFound) ? part : [part substringToIndex:equals.location];
        NSString *value = (equals.location == NSNotFound) ? @"" : [part substringFromIndex:equals.location + 1];
        key = [key stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        value = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if ([key length] > 0 && value) [result setObject:value forKey:key];
    }
    return result;
}

static BOOL VCPrivateIPv4(NSString *host) {
    struct in_addr address;
    if (inet_pton(AF_INET, [host UTF8String], &address) != 1) return NO;
    uint32_t ip = ntohl(address.s_addr);
    return ((ip & 0xff000000U) == 0x0a000000U) ||
           ((ip & 0xffc00000U) == 0x64400000U) ||
           ((ip & 0xfff00000U) == 0xac100000U) ||
           ((ip & 0xffff0000U) == 0xc0a80000U) ||
           ((ip & 0xffff0000U) == 0xa9fe0000U);
}

NSDictionary *VCKaringLANDownloadDescriptor(NSString *payload, NSString **errorText) {
    if (errorText) *errorText = nil;
    NSString *text = VCTrimmedString(payload);
    NSURL *url = [NSURL URLWithString:text];
    if (![[[url scheme] lowercaseString] isEqualToString:@"karing"] ||
        ![[[url host] lowercaseString] isEqualToString:@"sync-download"]) {
        return nil;
    }

    NSDictionary *query = VCQueryParameters([url query]);
    NSString *ips = VCTrimmedString([query objectForKey:@"ips"]);
    NSInteger port = [VCTrimmedString([query objectForKey:@"port"]) integerValue];
    if ([ips length] == 0 || port < 1 || port > 65535) {
        VCSetError(errorText, @"The Karing LAN sync QR code is incomplete");
        return nil;
    }

    NSMutableArray *hosts = [NSMutableArray array];
    for (NSString *candidate in [ips componentsSeparatedByString:@","]) {
        NSString *host = VCTrimmedString(candidate);
        if (VCPrivateIPv4(host) && ![hosts containsObject:host]) [hosts addObject:host];
    }
    if ([hosts count] == 0) {
        VCSetError(errorText, @"The Karing QR code has no private LAN address");
        return nil;
    }

    return [NSDictionary dictionaryWithObjectsAndKeys:
            hosts, @"hosts",
            [NSNumber numberWithInteger:port], @"port",
            nil];
}
