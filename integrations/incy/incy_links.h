#ifndef VC_INCY_LINKS_H
#define VC_INCY_LINKS_H
#import <Foundation/Foundation.h>

BOOL VCIncyIsLink(NSString *text);
BOOL VCIncyIsCryptLink(NSString *text);
NSMutableData *VCIncyDecodeBase64(NSString *text, BOOL urlOnly, NSUInteger maximum);
NSDictionary *VCIncyImportDescriptor(NSString *link, NSString **error);
NSDictionary *VCIncySubscriptionDescriptor(NSString *link, NSString **error);
NSString *VCIncySafeFetchError(NSString *error);
void VCIncyClearData(NSMutableData *data);
#endif
