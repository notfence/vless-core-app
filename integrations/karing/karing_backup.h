#ifndef VLESS_CORE_KARING_BACKUP_H
#define VLESS_CORE_KARING_BACKUP_H

#import <Foundation/Foundation.h>

BOOL VCKaringBackupDataLooksLikeZip(NSData *data);
NSArray *VCKaringSubscriptionsFromBackupData(NSData *data, NSString **errorText);
NSDictionary *VCKaringLANDownloadDescriptor(NSString *payload, NSString **errorText);

#endif
