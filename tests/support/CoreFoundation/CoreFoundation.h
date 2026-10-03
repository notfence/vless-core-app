#ifndef VC_HOST_CORE_FOUNDATION_H
#define VC_HOST_CORE_FOUNDATION_H
#import <Foundation/Foundation.h>
#include <stdint.h>
typedef id CFTypeRef;
typedef id CFPropertyListRef;
typedef NSDictionary *CFDictionaryRef;
typedef NSMutableDictionary *CFMutableDictionaryRef;
typedef NSArray *CFArrayRef;
typedef NSString *CFStringRef;
typedef NSData *CFDataRef;
typedef NSNumber *CFNumberRef;
typedef NSError *CFErrorRef;
typedef const void *CFAllocatorRef;
typedef NSInteger CFIndex;
typedef NSUInteger CFTypeID;
typedef NSRange CFRange;
typedef unsigned char Boolean;
#define CFSTR(s) @s
#define kCFAllocatorDefault NULL
#define kCFStringEncodingUTF8 NSUTF8StringEncoding
#define kCFPropertyListBinaryFormat_v1_0 NSPropertyListBinaryFormat_v1_0
#define kCFPropertyListImmutable NSPropertyListImmutable
static const int kCFTypeArrayCallBacks = 0;
static const int kCFTypeDictionaryKeyCallBacks = 0;
static const int kCFTypeDictionaryValueCallBacks = 0;
#define kCFNumberIntType 0
#define kCFBooleanTrue [NSNumber numberWithBool:YES]
#define kCFCompareEqualTo NSOrderedSame
#define kCFNotFound NSNotFound
#define CFRangeMake NSMakeRange
static inline id CFRetain(id value) { return [value retain]; }
static inline void CFRelease(id value) { [value release]; }
static inline Boolean CFEqual(id a, id b) { return [a isEqual:b]; }
static inline CFTypeID CFGetTypeID(id v) {
    if ([v isKindOfClass:[NSDictionary class]]) return 1;
    if ([v isKindOfClass:[NSArray class]]) return 2;
    if ([v isKindOfClass:[NSString class]]) return 3;
    if ([v isKindOfClass:[NSNumber class]]) return 4;
    if ([v isKindOfClass:[NSData class]]) return 5;
    return 0;
}
static inline CFTypeID CFDictionaryGetTypeID(void) { return 1; }
static inline CFTypeID CFArrayGetTypeID(void) { return 2; }
static inline CFTypeID CFStringGetTypeID(void) { return 3; }
static inline CFTypeID CFNumberGetTypeID(void) { return 4; }
static inline CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef a, CFIndex n, const void *k, const void *v) {
    (void)a; (void)n; (void)k; (void)v; return [[NSMutableDictionary alloc] init];
}
static inline CFMutableDictionaryRef CFDictionaryCreateMutableCopy(CFAllocatorRef a, CFIndex n, NSDictionary *d) {
    (void)a; (void)n; return [d mutableCopy];
}
static inline CFDictionaryRef CFDictionaryCreate(CFAllocatorRef a, const void **keys, const void **values, CFIndex n, const void *k, const void *v) {
    (void)a; (void)k; (void)v;
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (CFIndex i = 0; i < n; i++) [d setObject:(id)values[i] forKey:(id)keys[i]];
    return d;
}
static inline id CFDictionaryGetValue(NSDictionary *d, id key) { return [d objectForKey:key]; }
static inline void CFDictionarySetValue(NSMutableDictionary *d, id key, id value) { [d setObject:value forKey:key]; }
static inline void CFDictionaryRemoveValue(NSMutableDictionary *d, id key) { [d removeObjectForKey:key]; }
static inline Boolean CFDictionaryContainsKey(NSDictionary *d, id key) { return [d objectForKey:key] != nil; }
static inline CFIndex CFDictionaryGetCount(NSDictionary *d) { return [d count]; }
static inline void CFDictionaryGetKeysAndValues(NSDictionary *d, const void **keys, const void **values) {
    NSUInteger i = 0;
    for (id key in d) { keys[i] = key; values[i++] = [d objectForKey:key]; }
}
static inline CFArrayRef CFArrayCreate(CFAllocatorRef a, const void **v, CFIndex n, const void *c) {
    (void)a; (void)c; return [[NSArray alloc] initWithObjects:(id const *)v count:n];
}
static inline CFIndex CFArrayGetCount(NSArray *a) { return [a count]; }
static inline id CFArrayGetValueAtIndex(NSArray *a, CFIndex i) { return [a objectAtIndex:i]; }
static inline CFDataRef CFDataCreate(CFAllocatorRef a, const uint8_t *p, CFIndex n) { (void)a; return [[NSData alloc] initWithBytes:p length:n]; }
static inline CFIndex CFDataGetLength(NSData *d) { return [d length]; }
static inline const uint8_t *CFDataGetBytePtr(NSData *d) { return [d bytes]; }
static inline CFDataRef CFPropertyListCreateData(CFAllocatorRef a, id v, NSUInteger f, NSUInteger o, NSError **e) {
    (void)a; return [[NSPropertyListSerialization dataWithPropertyList:v format:f options:o error:e] retain];
}
static inline id CFPropertyListCreateWithData(CFAllocatorRef a, NSData *d, NSUInteger o, void *f, NSError **e) {
    (void)a; return [[NSPropertyListSerialization propertyListWithData:d options:o format:f error:e] retain];
}
static inline CFIndex CFStringGetLength(NSString *s) { return [s length]; }
static inline Boolean CFStringHasPrefix(NSString *s, NSString *p) { return [s hasPrefix:p]; }
static inline Boolean CFStringHasSuffix(NSString *s, NSString *p) { return [s hasSuffix:p]; }
static inline CFStringRef CFStringCreateWithSubstring(CFAllocatorRef a, NSString *s, NSRange r) { (void)a; return [[s substringWithRange:r] copy]; }
static inline CFStringRef CFStringCreateWithFormat(CFAllocatorRef a, void *o, NSString *f, ...) {
    (void)a; (void)o; va_list args; va_start(args, f);
    NSString *s = [[NSString alloc] initWithFormat:f arguments:args]; va_end(args); return s;
}
static inline CFNumberRef CFNumberCreate(CFAllocatorRef a, int t, const int *v) { (void)a; (void)t; return [[NSNumber alloc] initWithInt:*v]; }
static inline Boolean CFNumberGetValue(NSNumber *n, int t, int *v) { (void)t; *v = [n intValue]; return YES; }
static inline NSComparisonResult CFStringCompare(NSString *a, NSString *b, NSUInteger o) { return [a compare:b options:o]; }
static inline CFRange CFStringFind(NSString *s, NSString *p, NSUInteger o) { return [s rangeOfString:p options:o]; }
static inline CFStringRef CFURLCreateStringByAddingPercentEscapes(CFAllocatorRef a, NSString *s, NSString *leave, NSString *force, NSUInteger encoding) {
    (void)a; (void)leave; (void)force;
    NSData *bytes = [s dataUsingEncoding:encoding]; NSMutableString *out = [[NSMutableString alloc] init];
    const uint8_t *p = [bytes bytes];
    for (NSUInteger i = 0; i < [bytes length]; i++) {
        uint8_t c = p[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') [out appendFormat:@"%c", c];
        else [out appendFormat:@"%%%02X", c];
    }
    return out;
}
#endif
