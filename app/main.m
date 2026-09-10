#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include "happ_crypto.h"
#include "karing_backup.h"
#include <zbar.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <Block.h>
#include <sqlite3.h>

#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/utsname.h>
#include <spawn.h>
#include "../daemon/vpnctld_protocol.h"

extern char **environ;

static NSString *const kDefaultsConfigsKey = @"vlesscore.configs";
static NSString *const kDefaultsSubsKey = @"vlesscore.subscriptions";
static NSString *const kDefaultsAutoUpdateSubsKey = @"vlesscore.auto_update_subs";
static NSString *const kDefaultsPreserveCustomSubscriptionNamesKey = @"vlesscore.preserve_custom_subscription_names";
static NSString *const kDefaultsStealthModeKey = @"vlesscore.stealth_mode";
static NSString *const kDefaultsDarkThemeKey = @"vlesscore.dark_theme";
static NSString *const kDefaultsAutomaticUpdateChecksKey = @"vlesscore.update.automatic";
static NSString *const kDefaultsPingTypeKey = @"vlesscore.ping.type";
static NSString *const kDefaultsXrayVersionSpoofEnabledKey = @"vlesscore.xray.version.spoof.enabled";
static NSString *const kDefaultsXrayVersionKey = @"vlesscore.xray.version";
static NSString *const kDefaultsLastSelectionKey = @"vlesscore.last_selection";
static NSString *const kDefaultsConfigurationsExpandedKey = @"vlesscore.configurations_expanded";
static NSString *const kDefaultsSubscriptionsExpandedKey = @"vlesscore.subscriptions_expanded";
static NSString *const kDefaultsExpandedSubscriptionKey = @"vlesscore.expanded_subscription";
static NSString *const kDefaultsLastUpdateCheckKey = @"vlesscore.update.last_check";
static NSString *const kDefaultsLatestVersionKey = @"vlesscore.update.latest_version";
static NSString *const kDefaultsLatestReleaseURLKey = @"vlesscore.update.latest_release_url";
static NSString *const kDefaultsRoutingEnabledKey = @"vlesscore.routing.enabled";
static NSString *const kDefaultsRoutingDefaultKey = @"vlesscore.routing.default";
static NSString *const kDefaultsRoutingBypassLANKey = @"vlesscore.routing.bypass_lan";
static NSString *const kDefaultsRoutingRulesKey = @"vlesscore.routing.rules";
static NSString *const kDefaultsSubHWIDKey = @"vlesscore.subscription_hwid";
static NSString *const kDefaultsDiagnosticAppActivityKey = @"vlesscore.diagnostics.app_activity";
static NSString *const kDefaultsPreferGitHubLegacyKey = @"vlesscore.links.prefer_github_legacy";
static NSString *const kSubscriptionAllowInsecureFetchKey = @"allow_insecure_fetch";
static NSString *const kSubscriptionAllowPlainHTTPKey = @"allow_plain_http";
static NSString *const kSubscriptionHappSourceKey = @"happ_source";
static NSString *const kHappSubscriptionUserAgent = @"Happ/3.26.3/iOS";
static NSString *const kHappAddPrefix = @"happ://add/";
static NSString *const kSubscriptionUserInfoKey = @"subscription_userinfo";
static NSString *const kSubscriptionUploadKey = @"upload";
static NSString *const kSubscriptionDownloadKey = @"download";
static NSString *const kSubscriptionTotalKey = @"total";
static NSString *const kSubscriptionExpireKey = @"expire";
static NSString *const kSubscriptionMetadataKey = @"metadata";
static NSString *const kSubscriptionDescriptionKey = @"description";
static NSString *const kSubscriptionSupportURLKey = @"support_url";
static NSString *const kSubscriptionWebPageURLKey = @"web_page_url";
static NSString *const kSubscriptionUpdateIntervalKey = @"update_interval_hours";
static NSString *const kSubscriptionRefillDateKey = @"refill_date";
static NSString *const kSubscriptionLastUpdatedKey = @"last_updated";
static NSString *const kSubscriptionCustomNameKey = @"custom_name";
static NSString *const kHiddenLinkText = @"**link is hidden**";
static NSString *const kDefaultXrayVersion = @"26.3.27";
static NSString *const kVCQRMetadataType = @"org.iso.QRCode";
static NSString *const kUpdateAPIURL = @"https://api.github.com/repos/notfence/vless-core-app/releases/latest";
static NSString *const kUpdateReleasesURL = @"https://github.com/notfence/vless-core-app/releases";
static NSString *const kProjectURL = @"https://github.com/notfence/vless-core-app";
static NSString *const kGitHubLegacyProjectURL = @"githublegacy://repo/notfence/vless-core-app";
static NSString *const kGitHubLegacyLatestReleaseURL = @"githublegacy://release/notfence/vless-core-app/latest";
static const NSTimeInterval kAutomaticUpdateCheckInterval = 24.0 * 60.0 * 60.0;
static NSString *const kImportDirectoryPath = @"/var/mobile/vless-core-import";
static NSString *const kSecureStoreDirectoryPath = @"/private/var/mobile/Library/Application Support/vless-core";
static NSString *const kSecureStoreFilePath = @"/private/var/mobile/Library/Application Support/vless-core/configs.dat";
static NSString *const kDiagnosticEventDatabasePath = @"/private/var/mobile/Library/Application Support/vless-core/diagnostic-events.sqlite3";
static NSString *const kVCDiagnosticEventsClearedNotification = @"VCDiagnosticEventsClearedNotification";
static const NSUInteger kVCDiagnosticEventCapacity = 250;
static const NSUInteger kVCMaximumConfigURIBytes = 4095;
static const NSUInteger kVCMaximumConfigQueryParameters = 128;
static const NSUInteger kVCMaximumConfigQueryKeyBytes = 127;
static const NSUInteger kVCMaximumSubscriptionURLBytes = 8192;
static const NSUInteger kVCMaximumSubscriptionBytes = 32U * 1024U * 1024U;
static const CGFloat kVCMainContentStartY = 246.0f;
static const CGFloat kVCMainCompactContentStartY = 112.0f;
static BOOL gVCSecureStoreWritable = YES;
static NSString *SendCommand(NSString *cmdLine);
static void VCRecordAppEvent(NSString *category, NSString *action, NSString *detail);

static CGFloat VCMainStatusBarInset(void) {
    if ([[UIDevice currentDevice].systemVersion integerValue] < 7 ||
        [UIApplication sharedApplication].statusBarHidden) {
        return 0.0f;
    }

    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    CGFloat inset = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame));
    return (inset > 0.0f && inset < 64.0f) ? inset : 0.0f;
}

static CGFloat VCClampUnit(CGFloat value) {
    if (value < 0.0f) return 0.0f;
    if (value > 1.0f) return 1.0f;
    return value;
}

static BOOL VCIsASCIIHexDigit(unichar value) {
    return (value >= '0' && value <= '9') ||
           (value >= 'a' && value <= 'f') ||
           (value >= 'A' && value <= 'F');
}

static const unsigned char kVCSecureStoreMagic[8] = {'V', 'C', 'S', 'A', 'F', 'E', '0', '1'};
static const size_t kVCSecureStoreKeyLength = 32;
static const size_t kVCSecureStoreNonceLength = 12;
static const size_t kVCSecureStoreTagLength = 16;
static const NSUInteger kVCSecureStoreMaximumBytes = 64U * 1024U * 1024U;

static BOOL VCWriteAllToFileDescriptor(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = (const uint8_t *)bytes;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        cursor += (size_t)written;
        length -= (size_t)written;
    }
    return YES;
}

static BOOL VCEnsureSecureStoreDirectory(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0700]
                                                             forKey:NSFilePosixPermissions];
    if (![manager createDirectoryAtPath:kSecureStoreDirectoryPath
            withIntermediateDirectories:YES
                             attributes:attributes
                                  error:nil]) {
        return NO;
    }

    struct stat st;
    const char *path = [kSecureStoreDirectoryPath fileSystemRepresentation];
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != geteuid()) return NO;
    return chmod(path, 0700) == 0;
}

static NSData *VCReadSecureStoreFile(BOOL *existsOut) {
    if (existsOut) *existsOut = NO;
    const char *path = [kSecureStoreFilePath fileSystemRepresentation];
    struct stat before;
    if (lstat(path, &before) != 0) return nil;
    if (existsOut) *existsOut = YES;
    if (!S_ISREG(before.st_mode) || S_ISLNK(before.st_mode) || before.st_uid != geteuid() || before.st_nlink != 1 ||
        before.st_size < 0 || (uint64_t)before.st_size > kVCSecureStoreMaximumBytes) {
        return nil;
    }

    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return nil;
    struct stat after;
    if (fstat(fd, &after) != 0 || !S_ISREG(after.st_mode) || after.st_uid != geteuid() || after.st_nlink != 1 ||
        after.st_dev != before.st_dev || after.st_ino != before.st_ino || after.st_size != before.st_size) {
        close(fd);
        return nil;
    }
    if ((after.st_mode & 0077) != 0 && fchmod(fd, 0600) != 0) {
        close(fd);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)after.st_size];
    uint8_t *output = (uint8_t *)[data mutableBytes];
    size_t remaining = (size_t)after.st_size;
    while (remaining > 0) {
        ssize_t count = read(fd, output, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            close(fd);
            return nil;
        }
        output += (size_t)count;
        remaining -= (size_t)count;
    }
    close(fd);
    return data;
}

static BOOL VCWriteSecureStoreFile(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || [data length] == 0 || [data length] > kVCSecureStoreMaximumBytes ||
        !VCEnsureSecureStoreDirectory()) {
        return NO;
    }

    char temporary[PATH_MAX];
    int length = snprintf(temporary, sizeof(temporary), "%s/configs.dat.tmp.XXXXXX",
                          [kSecureStoreDirectoryPath fileSystemRepresentation]);
    if (length <= 0 || (size_t)length >= sizeof(temporary)) return NO;
    int fd = mkstemp(temporary);
    if (fd < 0) return NO;

    BOOL ok = fchmod(fd, 0600) == 0 && VCWriteAllToFileDescriptor(fd, [data bytes], [data length]) && fsync(fd) == 0;
    if (close(fd) != 0) ok = NO;
    NSString *temporaryPath = [NSString stringWithUTF8String:temporary];
    if (ok) ok = temporaryPath != nil;
    if (ok) {
        NSDictionary *protectionAttributes = [NSDictionary dictionaryWithObject:NSFileProtectionComplete
                                                                          forKey:NSFileProtectionKey];
        NSError *attributeError = nil;
        if (![[NSFileManager defaultManager] setAttributes:protectionAttributes
                                              ofItemAtPath:temporaryPath
                                                     error:&attributeError]) {
            BOOL knownPermissionFailure = [[attributeError domain] isEqualToString:NSCocoaErrorDomain] &&
                                          [attributeError code] == NSFileReadNoPermissionError;
            if (!knownPermissionFailure) ok = NO;
        }
    }
    if (ok) ok = rename(temporary, [kSecureStoreFilePath fileSystemRepresentation]) == 0;
    if (!ok) {
        unlink(temporary);
        return NO;
    }
    int directoryFD = open([kSecureStoreDirectoryPath fileSystemRepresentation], O_RDONLY | O_NOFOLLOW);
    if (directoryFD >= 0) {
        (void)fsync(directoryFD);
        close(directoryFD);
    }
    return YES;
}

static BOOL VCLoadSecureStoreKey(unsigned char key[32], BOOL createIfMissing) {
    NSString *response = SendCommand(createIfMissing ? @"STORE_KEY\tCREATE\n" : @"STORE_KEY\tGET\n");
    if (![response hasPrefix:@"OK "]) return NO;
    NSString *hex = [response substringFromIndex:3];
    hex = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hex length] != kVCSecureStoreKeyLength * 2) return NO;
    for (NSUInteger i = 0; i < kVCSecureStoreKeyLength; i++) {
        unichar high = [hex characterAtIndex:i * 2];
        unichar low = [hex characterAtIndex:i * 2 + 1];
        if (!VCIsASCIIHexDigit(high) || !VCIsASCIIHexDigit(low)) return NO;
        int highValue = high >= '0' && high <= '9' ? (int)(high - '0') : (int)((high | 0x20) - 'a' + 10);
        int lowValue = low >= '0' && low <= '9' ? (int)(low - '0') : (int)((low | 0x20) - 'a' + 10);
        key[i] = (unsigned char)((highValue << 4) | lowValue);
    }
    return YES;
}

static NSData *VCEncryptSecureStorePayload(NSData *plaintext, const unsigned char key[32]) {
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

static NSData *VCDecryptSecureStorePayload(NSData *encrypted, const unsigned char key[32]) {
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

static BOOL VCSaveProtectedConfigurationData(NSArray *configs, NSArray *subscriptions) {
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             configs ? configs : [NSArray array], @"configs",
                             subscriptions ? subscriptions : [NSArray array], @"subscriptions",
                             nil];
    NSString *serializationError = nil;
    NSData *plaintext = [NSPropertyListSerialization dataFromPropertyList:payload
                                                                    format:NSPropertyListBinaryFormat_v1_0
                                                          errorDescription:&serializationError];
    [serializationError release];
    if (!plaintext) return NO;

    unsigned char key[32];
    if (!VCLoadSecureStoreKey(key, YES)) return NO;
    NSData *encrypted = VCEncryptSecureStorePayload(plaintext, key);
    OPENSSL_cleanse(key, sizeof(key));
    return encrypted != nil && VCWriteSecureStoreFile(encrypted);
}

static NSDictionary *VCLoadProtectedConfigurationData(BOOL *fileExistsOut) {
    NSData *encrypted = VCReadSecureStoreFile(fileExistsOut);
    if (!encrypted) return nil;
    unsigned char key[32];
    if (!VCLoadSecureStoreKey(key, NO)) return nil;
    NSData *plaintext = VCDecryptSecureStorePayload(encrypted, key);
    OPENSSL_cleanse(key, sizeof(key));
    if (!plaintext) return nil;

    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    NSString *serializationError = nil;
    id payload = [NSPropertyListSerialization propertyListFromData:plaintext
                                                   mutabilityOption:NSPropertyListImmutable
                                                             format:&format
                                                   errorDescription:&serializationError];
    [serializationError release];
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *configs = [payload objectForKey:@"configs"];
    NSArray *subscriptions = [payload objectForKey:@"subscriptions"];
    if (![configs isKindOfClass:[NSArray class]] || ![subscriptions isKindOfClass:[NSArray class]]) return nil;
    return payload;
}

static CGRect VCInterpolateRect(CGRect from, CGRect to, CGFloat progress) {
    CGFloat p = VCClampUnit(progress);
    return CGRectMake(from.origin.x + (to.origin.x - from.origin.x) * p,
                      from.origin.y + (to.origin.y - from.origin.y) * p,
                      from.size.width + (to.size.width - from.size.width) * p,
                      from.size.height + (to.size.height - from.size.height) * p);
}

static BOOL VCAppearanceIsDark(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsDarkThemeKey];
}

static void VCAppearanceSetDark(BOOL dark) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:dark forKey:kDefaultsDarkThemeKey];
    [ud synchronize];
}

static UIColor *VCBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.065f alpha:1.0f]
                                : [UIColor colorWithWhite:0.97f alpha:1.0f];
}

static UIColor *VCCellBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.13f alpha:1.0f]
                                : [UIColor whiteColor];
}

static UIColor *VCPrimaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.92f alpha:1.0f]
                                : [UIColor colorWithWhite:0.08f alpha:1.0f];
}

static UIColor *VCSecondaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.67f alpha:1.0f]
                                : [UIColor colorWithWhite:0.42f alpha:1.0f];
}

static UIColor *VCSeparatorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                : [UIColor colorWithWhite:0.78f alpha:1.0f];
}

static UIColor *VCSelectedCellColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.12f green:0.24f blue:0.38f alpha:1.0f]
                                : [UIColor colorWithRed:0.82f green:0.89f blue:0.98f alpha:1.0f];
}

static UIColor *VCAccentColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.28f green:0.62f blue:1.0f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.44f blue:0.86f alpha:1.0f];
}

static UIColor *VCSuccessColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.32f green:0.82f blue:0.42f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.50f blue:0.15f alpha:1.0f];
}

static UIColor *VCErrorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:1.0f green:0.38f blue:0.38f alpha:1.0f]
                                : [UIColor colorWithRed:0.78f green:0.12f blue:0.12f alpha:1.0f];
}

static BOOL IsPadDevice(void) {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    }

    NSString *model = [[UIDevice currentDevice] model];
    if (model && [model rangeOfString:@"iPad" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return NO;
}

static BOOL VCPreferGitHubLegacy(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:kDefaultsPreferGitHubLegacyKey] == nil ||
           [defaults boolForKey:kDefaultsPreferGitHubLegacyKey];
}

static void VCOpenURLWithFallback(NSString *preferredURLString, NSString *fallbackURLString) {
    UIApplication *application = [UIApplication sharedApplication];
    NSURL *preferredURL = [NSURL URLWithString:preferredURLString];
    BOOL opened = NO;

    if (VCPreferGitHubLegacy() && preferredURL && [application canOpenURL:preferredURL]) {
        opened = [application openURL:preferredURL];
    }

    if (!opened) {
        NSURL *fallbackURL = [NSURL URLWithString:fallbackURLString];
        if (fallbackURL) {
            [application openURL:fallbackURL];
        }
    }
}

static void VCOpenGitHubProject(void) {
    VCOpenURLWithFallback(kGitHubLegacyProjectURL, kProjectURL);
}

static void VCOpenGitHubLatestRelease(NSString *fallbackURLString) {
    NSString *fallback = [fallbackURLString length] > 0 ? fallbackURLString : kUpdateReleasesURL;
    VCOpenURLWithFallback(kGitHubLegacyLatestReleaseURL, fallback);
}

static UIInterfaceOrientation CurrentInterfaceOrientation(void) {
    UIInterfaceOrientation o = [[UIApplication sharedApplication] statusBarOrientation];
    if (o == UIInterfaceOrientationLandscapeLeft ||
        o == UIInterfaceOrientationLandscapeRight ||
        o == UIInterfaceOrientationPortraitUpsideDown ||
        o == UIInterfaceOrientationPortrait) {
        return o;
    }
    return UIInterfaceOrientationPortrait;
}

typedef NS_ENUM(NSInteger, VCAlertTag) {
    VCAlertTagImportManual = 1001,
    VCAlertTagImportInsecureSubscription = 1002,
    VCAlertTagUpdateAvailable = 1003,
    VCAlertTagPlainHTTPSubscription = 1004,
};

typedef NS_ENUM(NSInteger, VCActionSheetTag) {
    VCActionSheetTagImport = 2001,
};

typedef NS_ENUM(NSInteger, VCPingType) {
    VCPingTypeProxyGET = 0,
    VCPingTypeTCP = 1,
    VCPingTypeICMP = 2,
};

static VCPingType VCSelectedPingType(void) {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsPingTypeKey];
    if (value < VCPingTypeProxyGET || value > VCPingTypeICMP) {
        return VCPingTypeProxyGET;
    }
    return (VCPingType)value;
}

static NSString *VCPingTypeName(VCPingType type) {
    if (type == VCPingTypeTCP) return @"TCP";
    if (type == VCPingTypeICMP) return @"ICMP";
    return @"Proxy GET";
}

static NSString *VCSelectedPingTypeText(void) {
    return [NSString stringWithFormat:@"Selected: %@", VCPingTypeName(VCSelectedPingType())];
}

static BOOL VCXrayVersionIsValid(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSArray *parts = [value componentsSeparatedByString:@"."];
    if ([parts count] != 3) return NO;

    for (NSString *part in parts) {
        NSUInteger length = [part length];
        if (length == 0 || length > 3) return NO;
        for (NSUInteger i = 0; i < length; i++) {
            unichar c = [part characterAtIndex:i];
            if (c < '0' || c > '9') return NO;
        }
        if ([part integerValue] > 255) return NO;
    }
    return YES;
}

static NSString *VCSelectedXrayVersion(void) {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsXrayVersionKey];
    return VCXrayVersionIsValid(value) ? value : kDefaultXrayVersion;
}

static BOOL VCXrayVersionSpoofEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsXrayVersionSpoofEnabledKey];
}

static NSString *VCActiveXrayVersion(void) {
    return VCXrayVersionSpoofEnabled() ? VCSelectedXrayVersion() : nil;
}

static NSString *VCSelectedXrayVersionText(void) {
    if (!VCXrayVersionSpoofEnabled()) return @"Disabled";
    return [NSString stringWithFormat:@"Enabled: %@", VCSelectedXrayVersion()];
}

static NSInteger const kVCSubscriptionDeleteAlertTag = 3101;
static NSInteger const kVCSubscriptionRenameAlertTag = 3102;
static NSInteger const kVCSettingsUpdateAlertTag = 3103;
static NSInteger const kVCSettingsPingTypeActionSheetTag = 3104;

typedef NS_ENUM(NSInteger, VCIconType) {
    VCIconTypeAdd = 1,
    VCIconTypeTerminal = 2,
    VCIconTypeRefresh = 3,
    VCIconTypeSettings = 4,
    VCIconTypeChevronRight = 5,
    VCIconTypeChevronDown = 6,
    VCIconTypeWifi = 7,
    VCIconTypeCheck = 8,
    VCIconTypeList = 9,
    VCIconTypeReorder = 10,
    VCIconTypeStop = 11,
};

static NSInteger const kVCSettingsTitleMarqueeTag = 7400;
static NSInteger const kVCSettingsDetailMarqueeTag = 7401;
static NSInteger const kVCMainDetailContainerTag = 7410;
static NSInteger const kVCMainDetailPrefixTag = 7411;
static NSInteger const kVCMainDetailTailTag = 7412;
static NSInteger const kVCMainSectionHeaderButtonTagBase = 7420;
static NSInteger const kVCMainSectionHeaderCountTagBase = 7430;
static NSInteger const kVCMainSectionHeaderChevronTagBase = 7440;
static NSInteger const kVCMainSectionHeaderOrderButtonTagBase = 7450;
static NSInteger const kVCSubscriptionInfoButtonTagBase = 30000;
static NSInteger const kVCSubscriptionPingButtonTagBase = 40000;
static NSString *const kVCPingLoadingValue = @"__loading__";
static NSString *const kVCPingFailureValue = @"Failed";
static const char *kVCProxyPingHost = "www.gstatic.com";
static const uint16_t kVCProxyPingPort = 80;
static const char *kVCProxyPingRequest =
    "GET /generate_204 HTTP/1.1\r\n"
    "Host: www.gstatic.com\r\n"
    "User-Agent: vless-core-app-ping\r\n"
    "Connection: close\r\n\r\n";
static CGFloat const kVCMainSectionHeaderHeight = 46.0f;
static CGFloat const kVCDetailMarqueeGap = 4.0f;
static NSTimeInterval const kVCMarqueePauseSeconds = 1.0;
static CGFloat const kVCMarqueePixelsPerSecond = 28.0f;

static int TryBootstrapDaemon(void) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    char *argv[] = {
        "/usr/bin/vpnctld-bootstrap",
        NULL
    };

    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/usr/bin/vpnctld-bootstrap", &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc == 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
            }
        });
    }
    return (rc == 0) ? 0 : -1;
}

static int ConnectWithTimeout(int fd, const struct sockaddr *sa, socklen_t sa_len, int timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        return -1;
    }
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
        return -1;
    }

    int rc = connect(fd, sa, sa_len);
    if (rc == 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return 0;
    }
    if (errno != EINPROGRESS) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (rc <= 0) {
        errno = (rc == 0) ? ETIMEDOUT : errno;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    int soerr = 0;
    socklen_t sl = (socklen_t)sizeof(soerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) != 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }
    if (soerr != 0) {
        errno = soerr;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    (void)fcntl(fd, F_SETFL, flags);
    return 0;
}

static int OpenDaemonSocket(const struct timeval *rw_tv, int connect_timeout_ms, int *fd_out, int *last_errno_out) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        if (last_errno_out) *last_errno_out = errno;
        return -1;
    }

    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, rw_tv, sizeof(*rw_tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, rw_tv, sizeof(*rw_tv));

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", VC_DAEMON_SOCKET_PATH);
    sa.sun_len = (uint8_t)SUN_LEN(&sa);

    if (ConnectWithTimeout(fd, (struct sockaddr *)&sa, (socklen_t)sa.sun_len, connect_timeout_ms) == 0) {
        *fd_out = fd;
        if (last_errno_out) *last_errno_out = 0;
        return 0;
    }

    if (last_errno_out) *last_errno_out = errno;
    close(fd);
    return -1;
}

static int WriteAll(int fd, const void *bytes, size_t length) {
    const unsigned char *data = (const unsigned char *)bytes;
    size_t written = 0;
    while (written < length) {
        ssize_t count = write(fd, data + written, length - written);
        if (count < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (count == 0) {
            errno = EPIPE;
            return -1;
        }
        written += (size_t)count;
    }
    return 0;
}

static ssize_t SendRawCommand(NSData *outData, const struct timeval *rw_tv, int connect_timeout_ms, char *buf, size_t buf_cap, int *last_errno_out, BOOL *connected_out) {
    if (connected_out) *connected_out = NO;
    int fd = -1;
    int last_errno = 0;
    if (OpenDaemonSocket(rw_tv, connect_timeout_ms, &fd, &last_errno) != 0 || fd < 0) {
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }
    if (connected_out) *connected_out = YES;

    if (WriteAll(fd, [outData bytes], [outData length]) != 0) {
        last_errno = errno;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    size_t used = 0;
    for (;;) {
        if (used + 1 >= buf_cap) {
            close(fd);
            if (last_errno_out) *last_errno_out = EMSGSIZE;
            return -1;
        }
        ssize_t rd = read(fd, buf + used, buf_cap - used - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd < 0) {
            last_errno = errno;
            close(fd);
            if (last_errno_out) *last_errno_out = last_errno;
            return -1;
        }
        if (rd == 0) break;
        used += (size_t)rd;
    }
    close(fd);
    if (used == 0) {
        if (last_errno_out) *last_errno_out = ECONNRESET;
        return -1;
    }
    buf[used] = '\0';
    if (last_errno_out) *last_errno_out = 0;
    return (ssize_t)used;
}

static NSString *SendCommand(NSString *cmdLine) {
    BOOL isConnectCommand = [cmdLine hasPrefix:@"CONNECT\t"] ||
                            [cmdLine hasPrefix:@"CONNECT_PRIVATE\t"];

    struct timeval cmd_tv;
    cmd_tv.tv_sec = isConnectCommand ? 8 : 2;
    cmd_tv.tv_usec = 0;

    NSData *outData = [cmdLine dataUsingEncoding:NSUTF8StringEncoding];
    int last_errno = 0;
    NSString *last_io_error = nil;

    for (int phase = 0; phase < 2; phase++) {
        if (phase == 1) {
            (void)TryBootstrapDaemon();
        }

        int ready_attempts = (phase == 1) ? 10 : 1;
        for (int attempt = 0; attempt < ready_attempts; attempt++) {
            BOOL connected = NO;
            char buf[65536];
            ssize_t rd = SendRawCommand(outData, &cmd_tv, 500, buf, sizeof(buf), &last_errno, &connected);
            if (rd > 0) {
                return [NSString stringWithUTF8String:buf];
            }

            if (connected) {
                last_io_error = (last_errno == EPIPE || last_errno == ECONNRESET) ?
                    @"no response from daemon" :
                    [NSString stringWithFormat:@"write/read failed: %s", strerror(last_errno)];
                return last_io_error;
            }
            if (attempt + 1 < ready_attempts) usleep(120 * 1000);
        }
    }

    if (last_io_error) {
        return last_io_error;
    }
    if (last_errno == 0) {
        last_errno = ECONNREFUSED;
    }
    return [NSString stringWithFormat:@"daemon offline (%s)", strerror(last_errno)];
}

static NSString *ConnectCommandForURI(NSString *uri, BOOL protectLogs) {
    NSString *command = protectLogs ? @"CONNECT_PRIVATE" : @"CONNECT";
    NSString *xrayVersion = VCActiveXrayVersion();
    if (xrayVersion) {
        return [NSString stringWithFormat:@"%@\t0\t%@\t%@\n",
                command, xrayVersion, (uri ? uri : @"")];
    }
    return [NSString stringWithFormat:@"%@\t0\t%@\n", command, (uri ? uri : @"")];
}

static NSString *RoutingPolicyText(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
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

static NSString *SyncRoutingPolicyToDaemon(void) {
    return SendCommand([NSString stringWithFormat:@"ROUTING\t%@\n", RoutingPolicyText()]);
}

static int ConnectLatencyMs(const char *host, uint16_t port, int timeout_ms, int *latency_ms) {
    if (!host || !*host) return -1;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        return -2;
    }

    int rc_out = -3;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;

        int flags = fcntl(fd, F_GETFL, 0);
        if (flags >= 0) {
            (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        }

        struct timeval t0, t1;
        gettimeofday(&t0, NULL);
        int cr = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (cr != 0 && errno != EINPROGRESS) {
            close(fd);
            continue;
        }

        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(fd, &wfds);
        struct timeval tv;
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        int sr = select(fd + 1, NULL, &wfds, NULL, &tv);
        if (sr > 0 && FD_ISSET(fd, &wfds)) {
            int soerr = 0;
            socklen_t sl = (socklen_t)sizeof(soerr);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) == 0 && soerr == 0) {
                gettimeofday(&t1, NULL);
                long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
                if (ms < 0) ms = 0;
                if (latency_ms) *latency_ms = (int)ms;
                rc_out = 0;
                close(fd);
                break;
            }
        }

        close(fd);
    }

    freeaddrinfo(res);
    return rc_out;
}

static int ConnectLatencyBestOfNMs(const char *host, uint16_t port, int timeout_ms, int attempts, int *latency_ms) {
    if (attempts <= 0) attempts = 1;

    int best = -1;
    for (int i = 0; i < attempts; i++) {
        int ms = 0;
        if (ConnectLatencyMs(host, port, timeout_ms, &ms) == 0) {
            if (best < 0 || ms < best) best = ms;
        }
    }

    if (best < 0) return -1;
    if (latency_ms) *latency_ms = best;
    return 0;
}

static int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *p = (const unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t wr = write(fd, p, left);
        if (wr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (wr == 0) return -1;
        p += (size_t)wr;
        left -= (size_t)wr;
    }
    return 0;
}

static int read_full(int fd, void *buf, size_t len) {
    unsigned char *p = (unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t rd = read(fd, p, left);
        if (rd < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (rd == 0) return -1;
        p += (size_t)rd;
        left -= (size_t)rd;
    }
    return 0;
}

static int pick_free_loopback_port(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons(0);

    if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        return -1;
    }

    socklen_t sl = (socklen_t)sizeof(sa);
    if (getsockname(fd, (struct sockaddr *)&sa, &sl) != 0) {
        close(fd);
        return -1;
    }
    close(fd);
    return (int)ntohs(sa.sin_port);
}

static int connect_loopback_port(uint16_t port, int timeout_ms) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int wait_for_loopback_listener(uint16_t port, pid_t pid, int timeout_ms) {
    int waited = 0;
    while (waited < timeout_ms) {
        int ms = 0;
        if (ConnectLatencyMs("127.0.0.1", port, 250, &ms) == 0) {
            return 0;
        }
        if (pid > 0) {
            int st = 0;
            pid_t wr = waitpid(pid, &st, WNOHANG);
            if (wr == pid) return -2;
        }
        usleep(100 * 1000);
        waited += 100;
    }
    return -1;
}

static void stop_child_process(pid_t pid) {
    if (pid <= 0) return;

    int st = 0;
    pid_t wr = waitpid(pid, &st, WNOHANG);
    if (wr == pid) return;
    if (wr < 0 && errno == ECHILD) return;

    kill(pid, SIGTERM);
    for (int i = 0; i < 20; i++) {
        wr = waitpid(pid, &st, WNOHANG);
        if (wr == pid) return;
        if (wr < 0 && errno == ECHILD) return;
        usleep(50 * 1000);
    }
    kill(pid, SIGKILL);
    wr = waitpid(pid, &st, 0);
    if (wr < 0 && errno == ECHILD) return;
}

static pid_t spawn_temp_core_for_ping(const char *uri, uint16_t port, const char *xray_version) {
    if (!uri || !*uri) return -1;
    size_t uri_length = strlen(uri);
    if (uri_length > kVCMaximumConfigURIBytes) return -1;
    const char *core = VC_CORE_EXECUTABLE_PATH;
    if (access(core, X_OK) != 0) {
        return -1;
    }

    int uri_pipe[2];
    if (pipe(uri_pipe) != 0) return -1;
    if (write_all(uri_pipe[1], uri, uri_length) != 0) {
        close(uri_pipe[0]);
        close(uri_pipe[1]);
        return -1;
    }
    close(uri_pipe[1]);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    pid_t pid = fork();
    if (pid < 0) {
        close(uri_pipe[0]);
        return -1;
    }
    if (pid == 0) {
        if (uri_pipe[0] != STDIN_FILENO) {
            if (dup2(uri_pipe[0], STDIN_FILENO) < 0) _exit(126);
            close(uri_pipe[0]);
        }
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) {
            (void)dup2(dn, STDOUT_FILENO);
            (void)dup2(dn, STDERR_FILENO);
            if (dn > STDERR_FILENO) close(dn);
        }
        if (xray_version && *xray_version) {
            execl(core, VC_CORE_EXECUTABLE_NAME, "--uri-fd", "0", "--listen-port", port_str,
                  "--xray-version", xray_version, (char *)NULL);
        } else {
            execl(core, VC_CORE_EXECUTABLE_NAME, "--uri-fd", "0", "--listen-port", port_str,
                  (char *)NULL);
        }
        _exit(127);
    }
    close(uri_pipe[0]);
    return pid;
}

static int socks5_negotiate_noauth(int fd) {
    unsigned char hello[3] = {0x05, 0x01, 0x00};
    if (write_all(fd, hello, sizeof(hello)) != 0) return -1;

    unsigned char hello_resp[2];
    if (read_full(fd, hello_resp, sizeof(hello_resp)) != 0) return -1;
    if (hello_resp[0] != 0x05 || hello_resp[1] != 0x00) return -1;
    return 0;
}

static int socks5_read_connect_response(int fd) {
    unsigned char resp[4];
    if (read_full(fd, resp, sizeof(resp)) != 0) return -1;
    if (resp[0] != 0x05 || resp[1] != 0x00) return -1;

    size_t tail = 0;
    if (resp[3] == 0x01) {
        tail = 4 + 2;
    } else if (resp[3] == 0x04) {
        tail = 16 + 2;
    } else if (resp[3] == 0x03) {
        unsigned char domain_len = 0;
        if (read_full(fd, &domain_len, 1) != 0) return -1;
        tail = (size_t)domain_len + 2;
    } else {
        return -1;
    }

    unsigned char bound_address[257];
    if (tail > sizeof(bound_address)) return -1;
    return read_full(fd, bound_address, tail);
}

static int socks5_connect_ipv4(int fd, uint32_t ipv4_be, uint16_t port) {
    if (socks5_negotiate_noauth(fd) != 0) return -1;

    unsigned char req[10];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    req[n++] = 0x01;
    memcpy(&req[n], &ipv4_be, 4);
    n += 4;
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (write_all(fd, req, n) != 0) return -1;

    return socks5_read_connect_response(fd);
}

static int socks5_connect_domain(int fd, const char *host, uint16_t port) {
    if (!host || !*host) return -1;
    size_t host_len = strlen(host);
    if (host_len > 255) return -1;
    if (socks5_negotiate_noauth(fd) != 0) return -1;

    unsigned char req[4 + 1 + 255 + 2];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    req[n++] = 0x03;
    req[n++] = (unsigned char)host_len;
    memcpy(&req[n], host, host_len);
    n += host_len;
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (write_all(fd, req, n) != 0) return -1;

    return socks5_read_connect_response(fd);
}

static int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    int fd = connect_loopback_port(local_port, timeout_ms);
    if (fd < 0) return -1;

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    uint32_t target = inet_addr("1.1.1.1");
    if (target == INADDR_NONE || socks5_connect_ipv4(fd, target, 80) != 0) {
        close(fd);
        return -2;
    }
    gettimeofday(&t1, NULL);
    close(fd);

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

static int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    int fd = connect_loopback_port(local_port, timeout_ms);
    if (fd < 0) {
        return -1;
    }

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);

    if (socks5_connect_domain(fd, kVCProxyPingHost, kVCProxyPingPort) != 0 ||
        write_all(fd, kVCProxyPingRequest, strlen(kVCProxyPingRequest)) != 0) {
        close(fd);
        return -2;
    }

    char response[512];
    size_t response_len = 0;
    BOOL got_first_byte = NO;
    while (response_len + 1 < sizeof(response)) {
        ssize_t rd = read(fd, response + response_len, sizeof(response) - response_len - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd <= 0) break;
        if (!got_first_byte) {
            gettimeofday(&t1, NULL);
            got_first_byte = YES;
        }
        response_len += (size_t)rd;
        response[response_len] = '\0';
        if (strstr(response, "\r\n") != NULL) break;
    }
    close(fd);

    if (!got_first_byte || response_len < 5 || strncmp(response, "HTTP/", 5) != 0) {
        return -3;
    }

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

static int ProxyGetViaTempCoreMs(const char *uri, const char *xray_version,
                                 int timeout_ms, int attempts, int *latency_ms) {
    if (!uri || !*uri) return -1;
    if (attempts <= 0) attempts = 1;

    int port = pick_free_loopback_port();
    if (port <= 0 || port > 65535) return -2;

    pid_t pid = spawn_temp_core_for_ping(uri, (uint16_t)port, xray_version);
    if (pid <= 0) return -3;

    int rc = -4;
    if (wait_for_loopback_listener((uint16_t)port, pid, 6000) != 0) {
        stop_child_process(pid);
        return rc;
    }

    int best = -1;
    for (int i = 0; i < attempts; i++) {
        int ms = 0;
        if (ProxyGetConnectOnceMs((uint16_t)port, timeout_ms, &ms) == 0) {
            if (best < 0 || ms < best) best = ms;
        }
    }
    stop_child_process(pid);

    if (best < 0) {
        return -5;
    }
    if (latency_ms) *latency_ms = best;
    return 0;
}

static uint16_t ICMPChecksum(const void *bytes, size_t length) {
    const unsigned char *cursor = (const unsigned char *)bytes;
    uint32_t sum = 0;
    while (length >= 2) {
        uint16_t word = 0;
        memcpy(&word, cursor, sizeof(word));
        sum += word;
        cursor += 2;
        length -= 2;
    }
    if (length == 1) {
        uint16_t word = 0;
        memcpy(&word, cursor, 1);
        sum += word;
    }
    while ((sum >> 16) != 0) {
        sum = (sum & 0xFFFFU) + (sum >> 16);
    }
    return (uint16_t)~sum;
}

static int ICMPLatencyOnceMs(const struct sockaddr_in *target,
                             int timeout_ms,
                             uint16_t sequence,
                             int *latency_ms) {
    if (!target) return -1;

    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (fd < 0) {
        fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    }
    if (fd < 0) return -2;

    unsigned char packet[24];
    memset(packet, 0, sizeof(packet));
    packet[0] = 8;  // ICMP echo request
    uint16_t identifier = htons((uint16_t)(getpid() & 0xFFFF));
    uint16_t network_sequence = htons(sequence);
    memcpy(packet + 4, &identifier, sizeof(identifier));
    memcpy(packet + 6, &network_sequence, sizeof(network_sequence));
    for (size_t i = 8; i < sizeof(packet); i++) {
        packet[i] = (unsigned char)i;
    }
    uint16_t checksum = ICMPChecksum(packet, sizeof(packet));
    memcpy(packet + 2, &checksum, sizeof(checksum));

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    ssize_t sent = sendto(fd,
                          packet,
                          sizeof(packet),
                          0,
                          (const struct sockaddr *)target,
                          (socklen_t)sizeof(*target));
    if (sent != (ssize_t)sizeof(packet)) {
        close(fd);
        return -3;
    }

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    int selected = select(fd + 1, &rfds, NULL, NULL, &timeout);
    if (selected <= 0 || !FD_ISSET(fd, &rfds)) {
        close(fd);
        return -4;
    }

    unsigned char reply[512];
    struct sockaddr_in source;
    socklen_t source_len = (socklen_t)sizeof(source);
    ssize_t received = recvfrom(fd,
                                reply,
                                sizeof(reply),
                                0,
                                (struct sockaddr *)&source,
                                &source_len);
    gettimeofday(&t1, NULL);
    close(fd);
    if (received < 8 || source.sin_addr.s_addr != target->sin_addr.s_addr) return -5;

    size_t offset = 0;
    if ((reply[0] >> 4) == 4) {
        offset = (size_t)(reply[0] & 0x0F) * 4;
    }
    if (offset + 8 > (size_t)received || reply[offset] != 0 || reply[offset + 1] != 0) {
        return -6;
    }
    uint16_t reply_sequence = 0;
    memcpy(&reply_sequence, reply + offset + 6, sizeof(reply_sequence));
    if (ntohs(reply_sequence) != sequence) return -7;

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

static int ICMPLatencyBestOfNMs(const char *host,
                                int timeout_ms,
                                int attempts,
                                int *latency_ms) {
    if (!host || !*host) return -1;
    if (attempts <= 0) attempts = 1;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    struct addrinfo *result = NULL;
    if (getaddrinfo(host, NULL, &hints, &result) != 0 || !result) return -2;

    struct sockaddr_in target;
    memset(&target, 0, sizeof(target));
    memcpy(&target, result->ai_addr, sizeof(target));
    freeaddrinfo(result);

    struct timeval sequence_time;
    gettimeofday(&sequence_time, NULL);
    uint16_t first_sequence = (uint16_t)(sequence_time.tv_usec & 0xFFFF);
    int best = -1;
    for (int i = 0; i < attempts; i++) {
        int ms = 0;
        uint16_t sequence = (uint16_t)(first_sequence + i);
        if (ICMPLatencyOnceMs(&target, timeout_ms, sequence, &ms) == 0) {
            if (best < 0 || ms < best) best = ms;
        }
    }
    if (best < 0) return -3;
    if (latency_ms) *latency_ms = best;
    return 0;
}

static NSString *RunCommandFirstLine(const char *cmdLine) {
    if (!cmdLine || !*cmdLine) return nil;

    FILE *fp = popen(cmdLine, "r");
    if (!fp) return nil;

    char buf[256];
    char *got = fgets(buf, sizeof(buf), fp);
    pclose(fp);
    if (!got) return nil;

    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ' || buf[len - 1] == '\t')) {
        buf[len - 1] = '\0';
        len--;
    }
    if (len == 0) return nil;

    return [NSString stringWithUTF8String:buf];
}

static NSString *DetectCoreBinaryVersion(void) {
    NSString *v = RunCommandFirstLine(VC_CORE_EXECUTABLE_PATH " -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine(VC_CORE_EXECUTABLE_NAME " -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"unknown";
    }
    return v;
}

static NSString *VersionTokenAfterPrefix(NSString *line, NSString *prefix) {
    if (!line || !prefix) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part hasPrefix:prefix] && [part length] > [prefix length]) {
            return [part substringFromIndex:[prefix length]];
        }
    }
    return @"unknown";
}

static NSString *CurlVersionFromVersionLine(NSString *line) {
    if (!line) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part length] > 0) {
            [tokens addObject:part];
        }
    }

    if ([tokens count] >= 2 && [[tokens objectAtIndex:0] isEqualToString:@"curl"]) {
        return [tokens objectAtIndex:1];
    }
    return VersionTokenAfterPrefix(line, @"libcurl/");
}

static NSDictionary *DetectCurlDependencyVersions(void) {
    NSString *line = RunCommandFirstLine("/usr/bin/vless-core-curl --version 2>/dev/null");
    if (!line || [line length] == 0) {
        line = RunCommandFirstLine("vless-core-curl --version 2>/dev/null");
    }

    NSString *curlVersion = CurlVersionFromVersionLine(line);
    NSString *opensslVersion = VersionTokenAfterPrefix(line, @"OpenSSL/");
    NSString *zlibVersion = VersionTokenAfterPrefix(line, @"zlib/");

    return [NSDictionary dictionaryWithObjectsAndKeys:
            curlVersion, @"curl",
            opensslVersion, @"openssl",
            zlibVersion, @"zlib",
            nil];
}

static NSString *TrimSimpleString(NSString *s) {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ReadTextFileBestEffort(NSString *path) {
    if (!path || [path length] == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] == 0) return nil;

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return txt;
}

static NSString *NormalizeOpenSSLPatchStatus(NSString *status) {
    NSString *trimmed = TrimSimpleString(status);
    if ([trimmed isEqualToString:@"patched"]) return @"patched";
    if ([trimmed isEqualToString:@"unpatched"]) return @"unpatched";
    return @"unpatched";
}

static NSString *DetectOpenSSLPatchStatus(void) {
    NSString *status = ReadTextFileBestEffort(@"/usr/share/vless-core/openssl-patch-status");
    if (!status || [status length] == 0) {
        status = RunCommandFirstLine(VC_CORE_EXECUTABLE_PATH " --openssl-patch-status 2>/dev/null");
    }
    return NormalizeOpenSSLPatchStatus(status);
}

static NSString *DetectRedsocksVersion(void) {
    NSString *v = RunCommandFirstLine("/usr/bin/redsocks-vless-core -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine("redsocks-vless-core -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"bundled helper";
    }
    return v;
}

static NSString *AppDisplayName(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *name = [info objectForKey:@"CFBundleDisplayName"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = [info objectForKey:@"CFBundleName"];
    }
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = @"vless-core";
    }
    return name;
}

static NSString *AppShortVersion(void) {
    NSString *ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (![ver isKindOfClass:[NSString class]] || [ver length] == 0) {
        ver = @"0.0.0";
    }
    return ver;
}

static NSString *AppUserAgent(void) {
    return [NSString stringWithFormat:@"vless-core-app/%@/iOS", AppShortVersion()];
}

typedef struct {
    const char *identifier;
    const char *name;
} VCDeviceModelEntry;

static NSString *DeviceModelName(void) {
    struct utsname info;
    if (uname(&info) != 0 || info.machine[0] == '\0') {
        return TrimSimpleString([[UIDevice currentDevice] model]);
    }

    static const VCDeviceModelEntry models[] = {
        { "iPhone1,1", "iPhone" },
        { "iPhone1,2", "iPhone 3G" },
        { "iPhone2,1", "iPhone 3GS" },
        { "iPhone3,1", "iPhone 4" },
        { "iPhone3,2", "iPhone 4" },
        { "iPhone3,3", "iPhone 4" },
        { "iPhone4,1", "iPhone 4s" },
        { "iPhone5,1", "iPhone 5" },
        { "iPhone5,2", "iPhone 5" },
        { "iPhone5,3", "iPhone 5c" },
        { "iPhone5,4", "iPhone 5c" },
        { "iPhone6,1", "iPhone 5s" },
        { "iPhone6,2", "iPhone 5s" },
        { "iPhone7,1", "iPhone 6 Plus" },
        { "iPhone7,2", "iPhone 6" },
        { "iPhone8,1", "iPhone 6s" },
        { "iPhone8,2", "iPhone 6s Plus" },
        { "iPhone8,4", "iPhone SE" },
        { "iPhone9,1", "iPhone 7" },
        { "iPhone9,2", "iPhone 7 Plus" },
        { "iPhone9,3", "iPhone 7" },
        { "iPhone9,4", "iPhone 7 Plus" },
        { "iPhone10,1", "iPhone 8" },
        { "iPhone10,2", "iPhone 8 Plus" },
        { "iPhone10,3", "iPhone X" },
        { "iPhone10,4", "iPhone 8" },
        { "iPhone10,5", "iPhone 8 Plus" },
        { "iPhone10,6", "iPhone X" },
        { "iPhone11,2", "iPhone XS" },
        { "iPhone11,4", "iPhone XS Max" },
        { "iPhone11,6", "iPhone XS Max" },
        { "iPhone11,8", "iPhone XR" },
        { "iPhone12,1", "iPhone 11" },
        { "iPhone12,3", "iPhone 11 Pro" },
        { "iPhone12,5", "iPhone 11 Pro Max" },
        { "iPhone12,8", "iPhone SE (2nd generation)" },
        { "iPhone13,1", "iPhone 12 mini" },
        { "iPhone13,2", "iPhone 12" },
        { "iPhone13,3", "iPhone 12 Pro" },
        { "iPhone13,4", "iPhone 12 Pro Max" },
        { "iPad1,1", "iPad" },
        { "iPad2,1", "iPad 2" },
        { "iPad2,2", "iPad 2" },
        { "iPad2,3", "iPad 2" },
        { "iPad2,4", "iPad 2" },
        { "iPad2,5", "iPad mini" },
        { "iPad2,6", "iPad mini" },
        { "iPad2,7", "iPad mini" },
        { "iPad3,1", "iPad 3" },
        { "iPad3,2", "iPad 3" },
        { "iPad3,3", "iPad 3" },
        { "iPad3,4", "iPad 4" },
        { "iPad3,5", "iPad 4" },
        { "iPad3,6", "iPad 4" },
        { "iPad4,1", "iPad Air" },
        { "iPad4,2", "iPad Air" },
        { "iPad4,3", "iPad Air" },
        { "iPad4,4", "iPad mini 2" },
        { "iPad4,5", "iPad mini 2" },
        { "iPad4,6", "iPad mini 2" },
        { "iPad4,7", "iPad mini 3" },
        { "iPad4,8", "iPad mini 3" },
        { "iPad4,9", "iPad mini 3" },
        { "iPad5,1", "iPad mini 4" },
        { "iPad5,2", "iPad mini 4" },
        { "iPad5,3", "iPad Air 2" },
        { "iPad5,4", "iPad Air 2" },
        { "iPad6,3", "iPad Pro (9.7-inch)" },
        { "iPad6,4", "iPad Pro (9.7-inch)" },
        { "iPad6,7", "iPad Pro (12.9-inch)" },
        { "iPad6,8", "iPad Pro (12.9-inch)" },
        { "iPad6,11", "iPad (5th generation)" },
        { "iPad6,12", "iPad (5th generation)" },
        { "iPad7,1", "iPad Pro (12.9-inch) (2nd generation)" },
        { "iPad7,2", "iPad Pro (12.9-inch) (2nd generation)" },
        { "iPad7,3", "iPad Pro (10.5-inch)" },
        { "iPad7,4", "iPad Pro (10.5-inch)" },
        { "iPad7,5", "iPad (6th generation)" },
        { "iPad7,6", "iPad (6th generation)" },
        { "iPad7,11", "iPad (7th generation)" },
        { "iPad7,12", "iPad (7th generation)" },
        { "iPad8,1", "iPad Pro (11-inch)" },
        { "iPad8,2", "iPad Pro (11-inch)" },
        { "iPad8,3", "iPad Pro (11-inch)" },
        { "iPad8,4", "iPad Pro (11-inch)" },
        { "iPad8,5", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,6", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,7", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,8", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,9", "iPad Pro (11-inch) (2nd generation)" },
        { "iPad8,10", "iPad Pro (11-inch) (2nd generation)" },
        { "iPad8,11", "iPad Pro (12.9-inch) (4th generation)" },
        { "iPad8,12", "iPad Pro (12.9-inch) (4th generation)" },
        { "iPad11,1", "iPad mini (5th generation)" },
        { "iPad11,2", "iPad mini (5th generation)" },
        { "iPad11,3", "iPad Air (3rd generation)" },
        { "iPad11,4", "iPad Air (3rd generation)" },
        { "iPad11,6", "iPad (8th generation)" },
        { "iPad11,7", "iPad (8th generation)" },
        { "iPad13,1", "iPad Air (4th generation)" },
        { "iPad13,2", "iPad Air (4th generation)" },
        { "iPad13,4", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,5", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,6", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,7", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,8", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,9", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,10", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,11", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPod1,1", "iPod touch" },
        { "iPod2,1", "iPod touch (2nd generation)" },
        { "iPod3,1", "iPod touch (3rd generation)" },
        { "iPod4,1", "iPod touch (4th generation)" },
        { "iPod5,1", "iPod touch (5th generation)" },
        { "iPod7,1", "iPod touch (6th generation)" },
        { "iPod9,1", "iPod touch (7th generation)" }
    };

    for (size_t i = 0; i < sizeof(models) / sizeof(models[0]); i++) {
        if (strcmp(info.machine, models[i].identifier) == 0) {
            return [NSString stringWithUTF8String:models[i].name];
        }
    }
    return [NSString stringWithUTF8String:info.machine];
}

static NSString *AppBuildVersion(void) {
    NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    if (![build isKindOfClass:[NSString class]] || [build length] == 0) {
        build = @"0";
    }
    return build;
}

static NSString *AppVersionSummary(void) {
    return [NSString stringWithFormat:@"Version %@ (%@)", AppShortVersion(), AppBuildVersion()];
}

static NSString *AppInfoString(NSString *key, NSString *fallback) {
    NSString *value = [[[NSBundle mainBundle] infoDictionary] objectForKey:key];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return fallback;
    }
    return value;
}

static NSString *AppDebBuildDate(void) {
    return AppInfoString(@"VCBuildDate", @"unknown");
}

static NSString *AppGitShortCommit(void) {
    return AppInfoString(@"VCGitCommit", @"unknown");
}

static NSString *AppBuildMetadataSummary(void) {
    return [NSString stringWithFormat:@"Built at: %@\nGitSHA: %@", AppDebBuildDate(), AppGitShortCommit()];
}

static NSString *SubscriptionHWID(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *hwid = [ud objectForKey:kDefaultsSubHWIDKey];
    if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
        return hwid;
    }

    NSString *generated = nil;
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    if (uuid) {
        CFStringRef cf = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        if (cf) {
            generated = [NSString stringWithString:(NSString *)cf];
            CFRelease(cf);
        }
        CFRelease(uuid);
    }

    if (![generated isKindOfClass:[NSString class]] || [generated length] == 0) {
        generated = [NSString stringWithFormat:@"%u-%u-%u",
                     (unsigned)arc4random(),
                     (unsigned)arc4random(),
                     (unsigned)getpid()];
    }

    [ud setObject:generated forKey:kDefaultsSubHWIDKey];
    [ud synchronize];
    return generated;
}

static void CleanupSubscriptionFetchTempFiles(const char *out_path, const char *err_path, const char *hdr_path) {
    if (out_path && *out_path) unlink(out_path);
    if (err_path && *err_path) unlink(err_path);
    if (hdr_path && *hdr_path) unlink(hdr_path);
}

static BOOL SubscriptionDictionaryAllowsInsecureFetch(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    id value = [sub objectForKey:kSubscriptionAllowInsecureFetchKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue] ? YES : NO;
    }
    return NO;
}

static BOOL URLStringUsesPlainHTTP(NSString *urlString) {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"];
}

static BOOL SubscriptionDictionaryAllowsPlainHTTP(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;
    id value = [sub objectForKey:kSubscriptionAllowPlainHTTPKey];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static BOOL HappURLStringIsEncrypted(NSString *urlString) {
    NSString *lower = [urlString isKindOfClass:[NSString class]] ? [urlString lowercaseString] : nil;
    return [lower hasPrefix:@"happ://crypt4/"] || [lower hasPrefix:@"happ://crypt5/"];
}

static BOOL SubscriptionDictionaryUsesHappHeaders(NSDictionary *sub) {
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

static BOOL SubscriptionDictionaryIsHappEncrypted(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    return HappURLStringIsEncrypted([sub objectForKey:@"url"]);
}

static BOOL CurlExitCodeCanRetryInsecurely(int exitCode) {
    return exitCode == 60; /* CURLE_PEER_FAILED_VERIFICATION */
}

static BOOL NSURLErrorCanRetryInsecurely(NSError *err) {
    if (![err isKindOfClass:[NSError class]]) return NO;
    if (![[err domain] isEqualToString:NSURLErrorDomain]) return NO;

    NSInteger code = [err code];
    return code == NSURLErrorSecureConnectionFailed ||
           code == NSURLErrorServerCertificateHasBadDate ||
           code == NSURLErrorServerCertificateUntrusted ||
           code == NSURLErrorServerCertificateHasUnknownRoot ||
           code == NSURLErrorServerCertificateNotYetValid;
}

static BOOL SubscriptionDataLooksLikeHTML(NSData *data) {
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

static int CreateCurlURLConfigFD(const char *url) {
    if (!url || !*url) return -1;
    size_t urlLength = strlen(url);
    if (urlLength > kVCMaximumSubscriptionURLBytes || urlLength > (SIZE_MAX - 16) / 2) return -1;

    size_t capacity = urlLength * 2 + 16;
    char *config = (char *)malloc(capacity);
    if (!config) return -1;

    size_t used = 0;
    memcpy(config + used, "url = \"", 7);
    used += 7;
    for (size_t i = 0; i < urlLength; i++) {
        unsigned char value = (unsigned char)url[i];
        if (value < 0x20 || value == 0x7f) {
            memset(config, 0, capacity);
            free(config);
            return -1;
        }
        if (value == '\\' || value == '"') config[used++] = '\\';
        config[used++] = (char)value;
    }
    config[used++] = '"';
    config[used++] = '\n';

    char path[] = "/tmp/vlesscore-curl-url-XXXXXX";
    int fd = mkstemp(path);
    if (fd >= 0) unlink(path);
    BOOL ok = fd >= 0 && fchmod(fd, 0600) == 0 &&
              VCWriteAllToFileDescriptor(fd, config, used) && lseek(fd, 0, SEEK_SET) == 0;
    memset(config, 0, capacity);
    free(config);
    if (!ok) {
        if (fd >= 0) close(fd);
        return -1;
    }
    return fd;
}

static NSData *FetchURLViaVlessCoreCurl(NSString *urlString,
                                       BOOL allowInsecureFetch,
                                       BOOL allowPlainHTTP,
                                       BOOL useHappHeaders,
                                       BOOL sendSubscriptionHWID,
                                       NSString *userAgent,
                                       NSString **errOut,
                                       NSString **headersOut,
                                       int *exitCodeOut) {
    const char *curl_path = "/usr/bin/vless-core-curl";
    const char *ca_bundle_path = "/usr/share/vless-core/cacert.pem";

    if (errOut) *errOut = nil;
    if (headersOut) *headersOut = nil;
    if (exitCodeOut) *exitCodeOut = -1;

    if (!urlString || [urlString length] == 0) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }

    if (access(curl_path, X_OK) != 0) {
        if (errOut) *errOut = @"vless-core-curl not found";
        return nil;
    }

    NSURL *parsedURL = [NSURL URLWithString:urlString];
    NSString *scheme = [[[parsedURL scheme] lowercaseString] copy];
    BOOL usesHTTPS = [scheme isEqualToString:@"https"];
    BOOL usesHTTP = [scheme isEqualToString:@"http"];
    BOOL allowsHTTPTransport = usesHTTP || useHappHeaders;
    if ((!usesHTTPS && !usesHTTP) || ![[parsedURL host] length]) {
        [scheme release];
        if (errOut) *errOut = @"Subscription URL must use HTTP or HTTPS";
        return nil;
    }
    if (usesHTTP && !allowPlainHTTP && !useHappHeaders) {
        [scheme release];
        if (errOut) *errOut = @"Plain HTTP subscription requires confirmation";
        return nil;
    }
    [scheme release];

    const char *url_c = [urlString UTF8String];
    if (!url_c || !*url_c) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }
    const char *user_agent_c = ([userAgent length] > 0) ? [userAgent UTF8String] : NULL;

    NSString *hwid = sendSubscriptionHWID ? TrimSimpleString(SubscriptionHWID()) : nil;
    char hwid_header[256];
    memset(hwid_header, 0, sizeof(hwid_header));
    const char *hwid_c = [hwid UTF8String];
    if (hwid_c && *hwid_c) {
        snprintf(hwid_header, sizeof(hwid_header), "X-HWID: %s", hwid_c);
    }

    char happ_locale_header[256];
    char device_os_header[64];
    char device_os_version_header[128];
    char device_model_header[256];
    memset(happ_locale_header, 0, sizeof(happ_locale_header));
    memset(device_os_header, 0, sizeof(device_os_header));
    memset(device_os_version_header, 0, sizeof(device_os_version_header));
    memset(device_model_header, 0, sizeof(device_model_header));
    if (sendSubscriptionHWID || useHappHeaders) {
        UIDevice *device = [UIDevice currentDevice];
        NSString *systemVersion = TrimSimpleString([device systemVersion]);
        NSString *model = DeviceModelName();
        const char *system_version_c = [systemVersion UTF8String];
        const char *model_c = [model UTF8String];
        snprintf(device_os_header, sizeof(device_os_header), "%s", "X-Device-OS: iOS");
        if (system_version_c && *system_version_c) {
            snprintf(device_os_version_header, sizeof(device_os_version_header), "X-Ver-OS: %s", system_version_c);
        }
        if (model_c && *model_c) {
            snprintf(device_model_header, sizeof(device_model_header), "X-Device-Model: %s", model_c);
        }
        if (useHappHeaders) {
            NSString *locale = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
            const char *locale_c = [locale UTF8String];
            if (locale_c && *locale_c) {
                snprintf(happ_locale_header, sizeof(happ_locale_header), "X-Device-Locale: %s", locale_c);
            }
        }
    }

    char out_tmpl[] = "/tmp/vlesscore-sub-out-XXXXXX";
    int out_fd = mkstemp(out_tmpl);
    if (out_fd < 0) {
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(out) failed: %s", strerror(errno)];
        return nil;
    }

    char err_tmpl[] = "/tmp/vlesscore-sub-err-XXXXXX";
    int err_fd = mkstemp(err_tmpl);
    if (err_fd < 0) {
        close(out_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, NULL, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(err) failed: %s", strerror(errno)];
        return nil;
    }

    char hdr_tmpl[] = "/tmp/vlesscore-sub-hdr-XXXXXX";
    int hdr_fd = mkstemp(hdr_tmpl);
    if (hdr_fd < 0) {
        close(out_fd);
        close(err_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(hdr) failed: %s", strerror(errno)];
        return nil;
    }
    close(hdr_fd);

    int curl_config_fd = -1;
    if (!useHappHeaders) {
        curl_config_fd = CreateCurlURLConfigFD(url_c);
        if (curl_config_fd < 0) {
            close(out_fd);
            close(err_fd);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = @"Invalid or excessively long subscription URL";
            return nil;
        }
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(out_fd);
        close(err_fd);
        if (curl_config_fd >= 0) close(curl_config_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = [NSString stringWithFormat:@"fork failed: %s", strerror(errno)];
        return nil;
    }

    if (pid == 0) {
        if (curl_config_fd >= 0) {
            if (curl_config_fd != STDIN_FILENO) {
                if (dup2(curl_config_fd, STDIN_FILENO) < 0) _exit(126);
                close(curl_config_fd);
            }
        } else {
            int dn = open("/dev/null", O_RDONLY);
            if (dn >= 0) {
                (void)dup2(dn, STDIN_FILENO);
                if (dn > STDERR_FILENO) close(dn);
            }
        }

        (void)dup2(out_fd, STDOUT_FILENO);
        (void)dup2(err_fd, STDERR_FILENO);
        close(out_fd);
        close(err_fd);

        char *argv[48];
        int argc = 0;
        argv[argc++] = (char *)"vless-core-curl";
        argv[argc++] = (char *)"--fail";
        argv[argc++] = (char *)"--location";
        argv[argc++] = (char *)"--compressed";
        argv[argc++] = (char *)"--silent";
        argv[argc++] = (char *)"--show-error";
        if (!useHappHeaders) {
            argv[argc++] = (char *)"--config";
            argv[argc++] = (char *)"-";
        }
        argv[argc++] = (char *)"--connect-timeout";
        argv[argc++] = (char *)"10";
        argv[argc++] = (char *)"--max-time";
        argv[argc++] = (char *)"25";
        argv[argc++] = (char *)"--max-filesize";
        argv[argc++] = (char *)"33554432";
        argv[argc++] = (char *)"--max-redirs";
        argv[argc++] = (char *)"10";
        argv[argc++] = (char *)"--proto";
        argv[argc++] = (char *)(allowsHTTPTransport ? "=https,http" : "=https");
        argv[argc++] = (char *)"--proto-redir";
        argv[argc++] = (char *)(allowsHTTPTransport ? "=https,http" : "=https");
        argv[argc++] = (char *)"--curves";
        argv[argc++] = (char *)"X25519:P-256:P-384";
        argv[argc++] = (char *)"-D";
        argv[argc++] = hdr_tmpl;

        if (useHappHeaders) {
            argv[argc++] = (char *)"--user-agent";
            argv[argc++] = (char *)[kHappSubscriptionUserAgent UTF8String];
            if (happ_locale_header[0] != '\0') {
                argv[argc++] = (char *)"-H";
                argv[argc++] = happ_locale_header;
            }
        } else if (user_agent_c && *user_agent_c) {
            argv[argc++] = (char *)"--user-agent";
            argv[argc++] = (char *)user_agent_c;
        }

        if (device_os_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_os_header;
        }
        if (device_os_version_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_os_version_header;
        }
        if (device_model_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_model_header;
        }

        if (allowInsecureFetch) {
            argv[argc++] = (char *)"--insecure";
        }

        if (sendSubscriptionHWID && hwid_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = hwid_header;
        }

        if (!allowInsecureFetch && access(ca_bundle_path, R_OK) == 0) {
            argv[argc++] = (char *)"--cacert";
            argv[argc++] = (char *)ca_bundle_path;
        }

        if (useHappHeaders) {
            argv[argc++] = (char *)url_c;
        }
        argv[argc] = NULL;

        execv(curl_path, argv);
        _exit(127);
    }

    close(out_fd);
    close(err_fd);
    if (curl_config_fd >= 0) close(curl_config_fd);

    int status = 0;
    int waited_ms = 0;
    const int timeout_ms = 30000;
    while (1) {
        pid_t wr = waitpid(pid, &status, WNOHANG);
        if (wr == pid) break;
        if (wr < 0) {
            if (errno == EINTR) continue;
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = [NSString stringWithFormat:@"waitpid failed: %s", strerror(errno)];
            return nil;
        }

        if (waited_ms >= timeout_ms) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = @"vless-core-curl timed out";
            return nil;
        }

        struct stat partialBodyStat;
        if (lstat(out_tmpl, &partialBodyStat) == 0 &&
            S_ISREG(partialBodyStat.st_mode) &&
            (uint64_t)partialBodyStat.st_size > kVCMaximumSubscriptionBytes) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = @"Subscription response exceeds 32 MiB";
            return nil;
        }

        usleep(100 * 1000);
        waited_ms += 100;
    }

    NSString *out_path = [NSString stringWithUTF8String:out_tmpl];
    NSString *err_path = [NSString stringWithUTF8String:err_tmpl];
    NSString *hdr_path = [NSString stringWithUTF8String:hdr_tmpl];
    NSString *curl_err = TrimSimpleString(ReadTextFileBestEffort(err_path));
    NSString *curl_hdr = ReadTextFileBestEffort(hdr_path);
    if ([curl_err length] > 220) {
        curl_err = [curl_err substringToIndex:220];
    }

    if (headersOut) {
        *headersOut = curl_hdr;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (exitCodeOut && WIFEXITED(status)) {
            *exitCodeOut = WEXITSTATUS(status);
        }
        if (errOut) {
            if ([curl_err length] > 0) {
                *errOut = curl_err;
            } else if (WIFEXITED(status)) {
                *errOut = [NSString stringWithFormat:@"vless-core-curl exited with code %d", WEXITSTATUS(status)];
            } else {
                *errOut = @"vless-core-curl terminated unexpectedly";
            }
        }
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        return nil;
    }

    struct stat bodyStat;
    if (lstat(out_tmpl, &bodyStat) != 0 || !S_ISREG(bodyStat.st_mode) || bodyStat.st_nlink != 1) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Invalid subscription response file";
        return nil;
    }
    if (bodyStat.st_size <= 0) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Empty subscription response";
        return nil;
    }
    if ((uint64_t)bodyStat.st_size > kVCMaximumSubscriptionBytes) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Subscription response exceeds 32 MiB";
        return nil;
    }

    NSData *body = [NSData dataWithContentsOfFile:out_path];
    CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);

    if (!body || [body length] == 0) {
        if (errOut) *errOut = @"Empty subscription response";
        return nil;
    }

    return body;
}

static NSArray *VCNumericVersionComponents(NSString *version) {
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

static NSString *VCNormalizedReleaseVersion(NSString *version) {
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

static NSComparisonResult VCCompareVersions(NSString *left, NSString *right) {
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

static NSDictionary *VCPerformUpdateCheck(void) {
    NSString *userAgent = AppUserAgent();
    NSString *fetchError = nil;
    NSData *data = FetchURLViaVlessCoreCurl(kUpdateAPIURL,
                                            NO,
                                            NO,
                                            NO,
                                            NO,
                                            userAgent,
                                            &fetchError,
                                            NULL,
                                            NULL);
    if (!data) {
        NSString *message = ([fetchError length] > 0) ? fetchError : @"Unable to reach GitHub";
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                message, @"error",
                nil];
    }

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSString *message = jsonError ? [jsonError localizedDescription] : @"Invalid update response";
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                message, @"error",
                nil];
    }

    NSString *tag = [(NSDictionary *)json objectForKey:@"tag_name"];
    NSString *releaseURL = [(NSDictionary *)json objectForKey:@"html_url"];
    if (![tag isKindOfClass:[NSString class]] || [VCNumericVersionComponents(tag) count] == 0) {
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                @"The latest release has no valid version", @"error",
                nil];
    }
    if (![releaseURL isKindOfClass:[NSString class]] || [releaseURL length] == 0) {
        releaseURL = kUpdateReleasesURL;
    }
    tag = VCNormalizedReleaseVersion(tag);

    NSString *currentVersion = AppShortVersion();
    BOOL updateAvailable = (VCCompareVersions(currentVersion, tag) == NSOrderedAscending);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            (updateAvailable ? @"update" : @"current"), @"status",
            currentVersion, @"current_version",
            tag, @"latest_version",
            releaseURL, @"release_url",
            nil];
}

static BOOL VCUpdateResultIsSuccessful(NSDictionary *result) {
    NSString *status = [result objectForKey:@"status"];
    return [status isEqualToString:@"update"] || [status isEqualToString:@"current"];
}

static void VCCacheSuccessfulUpdateResult(NSDictionary *result) {
    if (!VCUpdateResultIsSuccessful(result)) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kDefaultsLastUpdateCheckKey];

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

static BOOL VCAutomaticUpdateCheckIsFresh(void) {
    NSTimeInterval lastCheck = [[NSUserDefaults standardUserDefaults] doubleForKey:kDefaultsLastUpdateCheckKey];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return lastCheck > 0.0 && now >= lastCheck &&
           (now - lastCheck) < kAutomaticUpdateCheckInterval;
}

@class VCUpdateChecker;
@protocol VCUpdateCheckerDelegate <NSObject>
- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result;
@end

@interface VCUpdateChecker : NSObject {
    id<VCUpdateCheckerDelegate> _delegate;
    BOOL _started;
}
@property (nonatomic, assign) id<VCUpdateCheckerDelegate> delegate;
- (id)initWithDelegate:(id<VCUpdateCheckerDelegate>)delegate;
- (void)start;
@end

@implementation VCUpdateChecker
@synthesize delegate = _delegate;

- (id)initWithDelegate:(id<VCUpdateCheckerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)start {
    if (_started) return;
    _started = YES;
    [NSThread detachNewThreadSelector:@selector(checkWorker) toTarget:self withObject:nil];
}

- (void)checkWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *result = [VCPerformUpdateCheck() retain];
    [self retain];
    [self performSelectorOnMainThread:@selector(deliverResult:) withObject:result waitUntilDone:YES];
    [result release];
    [pool drain];
}

- (void)deliverResult:(NSDictionary *)result {
    id<VCUpdateCheckerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(updateChecker:didFinishWithResult:)]) {
        [delegate updateChecker:self didFinishWithResult:result];
    }
    [self release];
}

@end

static void VCShowUpdateAvailableAlert(NSDictionary *result,
                                       id<UIAlertViewDelegate> delegate,
                                       NSInteger tag) {
    NSString *message = [NSString stringWithFormat:@"Version %@ is available.\n Currently installed: %@.",
                         [result objectForKey:@"latest_version"],
                         [result objectForKey:@"current_version"]];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Update Available"
                                                     message:message
                                                    delegate:delegate
                                           cancelButtonTitle:@"Later"
                                           otherButtonTitles:@"View Release", nil] autorelease];
    alert.tag = tag;
    [alert show];
}

static NSString *ClearLogsViaDaemon(void) {
    return SendCommand(@"CLEAR_LOGS\n");
}

static NSString *ReadDaemonLog(NSInteger index, NSUInteger maxBytes) {
    NSString *name = index == 1 ? @"core" : @"daemon";
    NSString *response = SendCommand([NSString stringWithFormat:@"LOG\t%@\n", name]);
    if (![response hasPrefix:@"OK\n"]) {
        return [NSString stringWithFormat:@"(cannot read %@ log: %@)\n", name, response ? response : @"no response"];
    }

    NSData *data = [[response substringFromIndex:3] dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || [data length] == 0) {
        return @"(empty)\n";
    }
    if (maxBytes > 0 && [data length] > maxBytes) {
        data = [data subdataWithRange:NSMakeRange([data length] - maxBytes, maxBytes)];
    }

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) {
        txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
    if (!txt) {
        return @"(unreadable)\n";
    }
    return txt;
}

static NSString *ReadLogAtIndex(NSInteger index) {
    return ReadDaemonLog(index, 8192);
}

static int Base64Value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return (int)(c - 'A');
    if (c >= 'a' && c <= 'z') return (int)(c - 'a') + 26;
    if (c >= '0' && c <= '9') return (int)(c - '0') + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

static NSData *DecodeBase64String(NSString *input) {
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

static UIImage *LoadBundledIconScaled(NSString *baseName, CGFloat size) {
    NSString *path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (!path) return nil;

    UIImage *raw = [UIImage imageWithContentsOfFile:path];
    if (!raw) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
    [raw drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

static UIImage *SolidImageWithColor(UIColor *color) {
    CGRect rect = CGRectMake(0, 0, 4, 4);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillRect(ctx, rect);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIImage *TintImageWithColor(UIImage *image, UIColor *color) {
    if (!image || !color) return image;

    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    CGRect rect = CGRectMake(0.0f, 0.0f, size.width, size.height);
    [color setFill];
    UIRectFill(rect);
    [image drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1.0f];
    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return tinted;
}

static UIImage *LoadBundledIconTinted(NSString *baseName, CGFloat size, UIColor *color) {
    UIImage *image = LoadBundledIconScaled(baseName, size);
    return image ? TintImageWithColor(image, color) : nil;
}

static void VCAppearanceApplyHeaderView(UIView *view);

static void VCAppearanceApplyTable(UITableView *tableView) {
    if (!tableView) return;

    tableView.backgroundColor = VCBackgroundColor();
    tableView.separatorColor = VCSeparatorColor();
    tableView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                     : UIScrollViewIndicatorStyleDefault;
    UIView *background = [[[UIView alloc] initWithFrame:tableView.bounds] autorelease];
    background.backgroundColor = VCBackgroundColor();
    tableView.backgroundView = background;
}

static void VCAppearanceApplyCell(UITableViewCell *cell) {
    if (!cell) return;

    cell.backgroundColor = VCCellBackgroundColor();
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.textLabel.highlightedTextColor = VCPrimaryTextColor();
    cell.detailTextLabel.highlightedTextColor = VCSecondaryTextColor();

    UIView *selected = [[[UIView alloc] initWithFrame:cell.bounds] autorelease];
    selected.backgroundColor = VCSelectedCellColor();
    cell.selectedBackgroundView = selected;
}

static void VCAppearanceApplyHeaderView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        label.textColor = VCSecondaryTextColor();
        if (VCAppearanceIsDark()) {
            label.shadowColor = [UIColor clearColor];
            label.shadowOffset = CGSizeZero;
        } else {
            label.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
            label.shadowOffset = CGSizeMake(0.0f, 1.0f);
        }
    }
    for (UIView *subview in view.subviews) {
        VCAppearanceApplyHeaderView(subview);
    }
}

static void VCAppearanceRefreshVisibleTableHeaders(UITableView *tableView) {
    if (!tableView) return;

    [tableView setNeedsLayout];
    [tableView layoutIfNeeded];
    NSInteger sections = [tableView numberOfSections];
    for (NSInteger section = 0; section < sections; section++) {
        UIView *header = [tableView headerViewForSection:section];
        if (header) {
            VCAppearanceApplyHeaderView(header);
            [header setNeedsDisplay];
        }
        UIView *footer = [tableView footerViewForSection:section];
        if (footer) {
            VCAppearanceApplyHeaderView(footer);
            [footer setNeedsDisplay];
        }
    }
}

static void VCAppearanceScheduleVisibleTableHeadersRefresh(UITableView *tableView) {
    if (!tableView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        VCAppearanceRefreshVisibleTableHeaders(tableView);
    });
}

static void VCAppearanceApplyNavigationBar(UINavigationBar *navigationBar) {
    if (!navigationBar) return;

    BOOL dark = VCAppearanceIsDark();
    BOOL modernTintBehavior = ([[[UIDevice currentDevice] systemVersion] integerValue] >= 7);
    navigationBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
    navigationBar.tintColor = dark
        ? (modernTintBehavior ? VCAccentColor() : [UIColor colorWithWhite:0.18f alpha:1.0f])
        : nil;
    if (dark) {
        NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
            VCPrimaryTextColor(), UITextAttributeTextColor,
            [UIColor clearColor], UITextAttributeTextShadowColor,
            [NSValue valueWithUIOffset:UIOffsetZero], UITextAttributeTextShadowOffset,
            nil];
        [navigationBar setTitleTextAttributes:titleAttributes];
    } else {
        [navigationBar setTitleTextAttributes:nil];
    }

    UINavigationItem *topItem = navigationBar.topItem;
    NSString *title = [topItem.title copy];
    if (title) {
        topItem.title = nil;
        topItem.title = title;
        [title release];
    }
    [navigationBar setNeedsLayout];
    [navigationBar layoutIfNeeded];
}

static UIStatusBarStyle VCAppearancePreferredStatusBarStyle(void) {
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 13) {
        return [[UIApplication sharedApplication] statusBarStyle];
    }
    return VCAppearanceIsDark() ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

static void VCAppearanceApplyStatusBar(void) {
    NSInteger systemMajor = [[[UIDevice currentDevice] systemVersion] integerValue];
    if (systemMajor >= 13) {
        UIWindow *window = [[UIApplication sharedApplication] keyWindow];
        UIViewController *controller = window.rootViewController;
        while (controller.presentedViewController) {
            controller = controller.presentedViewController;
        }
        if ([controller respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
            [controller setNeedsStatusBarAppearanceUpdate];
        }
        return;
    }

    BOOL modernStatusBar = (systemMajor >= 7);
    UIStatusBarStyle style = UIStatusBarStyleDefault;
    if (VCAppearanceIsDark()) {
        style = modernStatusBar ? UIStatusBarStyleBlackTranslucent : UIStatusBarStyleBlackOpaque;
    }
    [[UIApplication sharedApplication] setStatusBarStyle:style animated:YES];
}

static UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active) {
    CGSize iconSize = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(iconSize, NO, 0.0f);

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *clr = active ? VCAccentColor() : VCPrimaryTextColor();
    CGContextSetStrokeColorWithColor(ctx, clr.CGColor);
    CGContextSetFillColorWithColor(ctx, clr.CGColor);
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    CGFloat c = size * 0.5f;
    CGFloat r = size * 0.34f;

    if (type == VCIconTypeAdd) {
        CGContextMoveToPoint(ctx, c, c - r);
        CGContextAddLineToPoint(ctx, c, c + r);
        CGContextMoveToPoint(ctx, c - r, c);
        CGContextAddLineToPoint(ctx, c + r, c);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeTerminal) {
        CGRect box = CGRectMake(size * 0.14f, size * 0.18f, size * 0.72f, size * 0.64f);
        UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:size * 0.10f];
        bp.lineWidth = 2.0f;
        [bp stroke];

        CGContextMoveToPoint(ctx, size * 0.30f, c);
        CGContextAddLineToPoint(ctx, size * 0.42f, c + size * 0.10f);
        CGContextMoveToPoint(ctx, size * 0.30f, c);
        CGContextAddLineToPoint(ctx, size * 0.42f, c - size * 0.10f);
        CGContextMoveToPoint(ctx, size * 0.48f, c + size * 0.12f);
        CGContextAddLineToPoint(ctx, size * 0.68f, c + size * 0.12f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeRefresh) {
        CGRect arcRect = CGRectMake(c - r, c - r, r * 2.0f, r * 2.0f);
        UIBezierPath *ap = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                           radius:r
                                                       startAngle:(CGFloat)(M_PI * 0.22f)
                                                         endAngle:(CGFloat)(M_PI * 1.85f)
                                                        clockwise:YES];
        ap.lineWidth = 2.0f;
        [ap stroke];

        CGPoint tip = CGPointMake(CGRectGetMaxX(arcRect) - size * 0.02f, c - size * 0.08f);
        CGContextMoveToPoint(ctx, tip.x, tip.y);
        CGContextAddLineToPoint(ctx, tip.x - size * 0.12f, tip.y + size * 0.01f);
        CGContextAddLineToPoint(ctx, tip.x - size * 0.02f, tip.y + size * 0.10f);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
    } else if (type == VCIconTypeSettings) {
        for (int i = 0; i < 8; i++) {
            CGFloat a = (CGFloat)i * (CGFloat)(M_PI / 4.0);
            CGFloat r1 = size * 0.22f;
            CGFloat r2 = size * 0.37f;
            CGFloat x1 = c + cosf(a) * r1;
            CGFloat y1 = c + sinf(a) * r1;
            CGFloat x2 = c + cosf(a) * r2;
            CGFloat y2 = c + sinf(a) * r2;
            CGContextMoveToPoint(ctx, x1, y1);
            CGContextAddLineToPoint(ctx, x2, y2);
        }
        CGContextStrokePath(ctx);

        UIBezierPath *outer = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                              radius:size * 0.21f
                                                          startAngle:0
                                                            endAngle:(CGFloat)(M_PI * 2.0f)
                                                           clockwise:YES];
        outer.lineWidth = 2.0f;
        [outer stroke];

        UIBezierPath *inner = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                              radius:size * 0.08f
                                                          startAngle:0
                                                            endAngle:(CGFloat)(M_PI * 2.0f)
                                                           clockwise:YES];
        inner.lineWidth = 2.0f;
        [inner stroke];
    } else if (type == VCIconTypeChevronRight) {
        CGContextMoveToPoint(ctx, size * 0.38f, size * 0.24f);
        CGContextAddLineToPoint(ctx, size * 0.62f, size * 0.50f);
        CGContextAddLineToPoint(ctx, size * 0.38f, size * 0.76f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeChevronDown) {
        CGContextMoveToPoint(ctx, size * 0.24f, size * 0.38f);
        CGContextAddLineToPoint(ctx, size * 0.50f, size * 0.62f);
        CGContextAddLineToPoint(ctx, size * 0.76f, size * 0.38f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeWifi) {
        UIBezierPath *a1 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.10f)
                                                          radius:size * 0.30f
                                                      startAngle:(CGFloat)(M_PI * 1.20f)
                                                        endAngle:(CGFloat)(M_PI * 1.80f)
                                                       clockwise:YES];
        a1.lineWidth = 2.0f;
        [a1 stroke];

        UIBezierPath *a2 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.10f)
                                                          radius:size * 0.20f
                                                      startAngle:(CGFloat)(M_PI * 1.20f)
                                                        endAngle:(CGFloat)(M_PI * 1.80f)
                                                       clockwise:YES];
        a2.lineWidth = 2.0f;
        [a2 stroke];

        UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.22f)
                                                           radius:size * 0.05f
                                                       startAngle:0
                                                         endAngle:(CGFloat)(M_PI * 2.0f)
                                                        clockwise:YES];
        [dot fill];
    } else if (type == VCIconTypeCheck) {
        UIColor *ok = VCSuccessColor();
        CGContextSetStrokeColorWithColor(ctx, ok.CGColor);
        CGContextMoveToPoint(ctx, size * 0.20f, size * 0.54f);
        CGContextAddLineToPoint(ctx, size * 0.42f, size * 0.74f);
        CGContextAddLineToPoint(ctx, size * 0.80f, size * 0.30f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeList) {
        CGFloat ys[3] = { size * 0.30f, size * 0.50f, size * 0.70f };
        for (int i = 0; i < 3; i++) {
            CGFloat y = ys[i];
            UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size * 0.22f, y)
                                                               radius:size * 0.05f
                                                           startAngle:0
                                                             endAngle:(CGFloat)(M_PI * 2.0f)
                                                            clockwise:YES];
            [dot fill];
            CGContextMoveToPoint(ctx, size * 0.34f, y);
            CGContextAddLineToPoint(ctx, size * 0.80f, y);
        }
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeReorder) {
        CGFloat ys[3] = { size * 0.28f, size * 0.50f, size * 0.72f };
        for (int i = 0; i < 3; i++) {
            CGContextMoveToPoint(ctx, size * 0.18f, ys[i]);
            CGContextAddLineToPoint(ctx, size * 0.82f, ys[i]);
        }
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeStop) {
        CGContextSetFillColorWithColor(ctx, VCPrimaryTextColor().CGColor);
        CGContextFillRect(ctx, CGRectMake(size * 0.28f,
                                          size * 0.28f,
                                          size * 0.44f,
                                          size * 0.44f));
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIView *VCCreateDisclosureAccessoryView(void) {
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 20.0f, 20.0f)] autorelease];
    UIImageView *imageView = [[[UIImageView alloc] initWithFrame:CGRectMake(2.0f, 2.0f, 16.0f, 16.0f)] autorelease];
    imageView.image = TintImageWithColor(MakeIconImage(VCIconTypeChevronRight, 16.0f, NO),
                                         VCSecondaryTextColor());
    [view addSubview:imageView];
    return view;
}

@interface VCMarqueeLabel : UIView {
    UILabel *_label;
    NSString *_text;
    NSTimer *_startTimer;
    NSTimer *_endPauseTimer;
    CGFloat _overflowWidth;
    CGSize _lastBoundsSize;
    BOOL _needsRefresh;
}
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic, retain) UIColor *textColor;
- (void)stopMarquee;
- (void)restartMarquee;
@end

@implementation VCMarqueeLabel
@synthesize text = _text;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor clearColor];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor grayColor];
    _label.font = [UIFont systemFontOfSize:11.0f];
    _label.numberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByClipping;
    [self addSubview:_label];

    _overflowWidth = 0.0f;
    _lastBoundsSize = CGSizeZero;
    _needsRefresh = YES;
    return self;
}

- (void)dealloc {
    [self stopMarquee];
    [_text release];
    [_label release];
    [super dealloc];
}

- (void)invalidateTimer:(NSTimer **)timerPtr {
    if (!timerPtr) return;
    NSTimer *timer = *timerPtr;
    if (timer) {
        [timer invalidate];
        [timer release];
        *timerPtr = nil;
    }
}

- (void)scheduleTimer:(NSTimer **)timerPtr selector:(SEL)selector after:(NSTimeInterval)seconds {
    [self invalidateTimer:timerPtr];
    NSTimer *timer = [NSTimer timerWithTimeInterval:seconds
                                             target:self
                                           selector:selector
                                           userInfo:nil
                                            repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    *timerPtr = [timer retain];
}

- (CGFloat)textWidthForCurrentText {
    if (![_text isKindOfClass:[NSString class]] || [_text length] == 0) return 0.0f;
    UIFont *font = (_label.font ? _label.font : [UIFont systemFontOfSize:11.0f]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize sz = [_text sizeWithFont:font];
#pragma clang diagnostic pop
    return ceilf(sz.width);
}

- (void)resetToStartAndPause {
    [self invalidateTimer:&_endPauseTimer];
    if (_overflowWidth <= 0.5f || !self.window) return;
    CGRect f = _label.frame;
    f.origin.x = 0.0f;
    _label.frame = f;
    [self scheduleTimer:&_startTimer selector:@selector(startScrollStep) after:kVCMarqueePauseSeconds];
}

- (void)startScrollStep {
    [self invalidateTimer:&_startTimer];
    if (_overflowWidth <= 0.5f || !self.window) return;

    CGFloat duration = _overflowWidth / kVCMarqueePixelsPerSecond;
    if (duration < 0.35f) duration = 0.35f;

    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         CGRect f = _label.frame;
                         f.origin.x = -_overflowWidth;
                         _label.frame = f;
                     }
                     completion:^(BOOL finished) {
                         if (!finished) return;
                         [self scheduleTimer:&_endPauseTimer
                                     selector:@selector(resetToStartAndPause)
                                        after:kVCMarqueePauseSeconds];
                     }];
}

- (void)refreshMarqueeIfNeeded:(BOOL)force {
    CGSize b = self.bounds.size;
    if (!force && !_needsRefresh && fabsf((float)(b.width - _lastBoundsSize.width)) < 0.5f &&
        fabsf((float)(b.height - _lastBoundsSize.height)) < 0.5f) {
        return;
    }

    _lastBoundsSize = b;
    _needsRefresh = NO;
    [self stopMarquee];
    _label.text = (_text ? _text : @"");

    CGFloat viewW = b.width;
    CGFloat viewH = b.height;
    if (viewW < 1.0f || viewH < 1.0f) {
        _label.frame = CGRectMake(0, 0, 0, 0);
        return;
    }

    CGFloat textW = [self textWidthForCurrentText];
    if (textW < 1.0f) textW = viewW;

    _overflowWidth = textW - viewW;
    if (_overflowWidth <= 0.5f) {
        _overflowWidth = 0.0f;
        _label.frame = CGRectMake(0, 0, viewW, viewH);
        return;
    }

    _label.frame = CGRectMake(0, 0, textW, viewH);
    [self scheduleTimer:&_startTimer selector:@selector(startScrollStep) after:kVCMarqueePauseSeconds];
}

- (void)setText:(NSString *)text {
    if (_text == text || [_text isEqualToString:text]) {
        _needsRefresh = YES;
        [self refreshMarqueeIfNeeded:YES];
        return;
    }
    [_text release];
    _text = [text copy];
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

- (UIFont *)font {
    return _label.font;
}

- (void)setFont:(UIFont *)font {
    if ((_label.font == font) || [_label.font isEqual:font]) return;
    _label.font = font;
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

- (UIColor *)textColor {
    return _label.textColor;
}

- (void)setTextColor:(UIColor *)textColor {
    if ((_label.textColor == textColor) || [_label.textColor isEqual:textColor]) return;
    _label.textColor = textColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refreshMarqueeIfNeeded:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        _needsRefresh = YES;
        [self refreshMarqueeIfNeeded:YES];
    } else {
        [self stopMarquee];
    }
}

- (void)stopMarquee {
    [self invalidateTimer:&_startTimer];
    [self invalidateTimer:&_endPauseTimer];
    [_label.layer removeAllAnimations];
}

- (void)restartMarquee {
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

@end

typedef NS_ENUM(NSInteger, VCMainListCellKind) {
    VCMainListCellKindSubscriptionHeader = 0,
    VCMainListCellKindSubscriptionItem = 1,
    VCMainListCellKindConfigurationItem = 2,
};

@interface VCMainListCellBackgroundView : UIView {
    VCMainListCellKind _kind;
    BOOL _expanded;
    BOOL _firstItem;
    BOOL _lastItem;
    BOOL _active;
    BOOL _selectedStyle;
}
- (void)configureKind:(VCMainListCellKind)kind
             expanded:(BOOL)expanded
            firstItem:(BOOL)firstItem
             lastItem:(BOOL)lastItem
                active:(BOOL)active
        selectedStyle:(BOOL)selectedStyle;
@end

@implementation VCMainListCellBackgroundView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)configureKind:(VCMainListCellKind)kind
             expanded:(BOOL)expanded
            firstItem:(BOOL)firstItem
             lastItem:(BOOL)lastItem
                active:(BOOL)active
        selectedStyle:(BOOL)selectedStyle {
    _kind = kind;
    _expanded = expanded;
    _firstItem = firstItem;
    _lastItem = lastItem;
    _active = active;
    _selectedStyle = selectedStyle;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGRect bounds = self.bounds;
    [VCBackgroundColor() setFill];
    UIRectFill(bounds);

    if (_kind == VCMainListCellKindSubscriptionHeader) {
        CGRect card = CGRectInset(bounds, 6.0f, 4.0f);
        if (CGRectGetWidth(card) < 1.0f || CGRectGetHeight(card) < 1.0f) return;

        UIBezierPath *cardPath = [UIBezierPath bezierPathWithRoundedRect:card cornerRadius:9.0f];
        UIColor *fill = (_selectedStyle || _active)
            ? VCSelectedCellColor()
            : VCCellBackgroundColor();
        [fill setFill];
        [cardPath fill];

        UIColor *border = _active
            ? [VCAccentColor() colorWithAlphaComponent:0.82f]
            : (_expanded ? [VCAccentColor() colorWithAlphaComponent:0.38f]
                         : [VCSeparatorColor() colorWithAlphaComponent:0.82f]);
        [border setStroke];
        cardPath.lineWidth = _active ? 1.25f : 0.75f;
        [cardPath stroke];

        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context);
        [cardPath addClip];
        [VCAccentColor() setFill];
        UIRectFill(CGRectMake(CGRectGetMinX(card), CGRectGetMinY(card), 4.0f, CGRectGetHeight(card)));
        CGContextRestoreGState(context);
        return;
    }

    BOOL nestedItem = (_kind == VCMainListCellKindSubscriptionItem);
    CGFloat panelLeft = nestedItem ? 22.0f : 6.0f;
    CGFloat topInset = _firstItem ? 4.0f : 0.0f;
    CGFloat bottomInset = _lastItem ? 8.0f : 0.0f;
    CGRect panel = CGRectMake(panelLeft,
                              topInset,
                              MAX(0.0f, CGRectGetWidth(bounds) - panelLeft - 6.0f),
                              MAX(0.0f, CGRectGetHeight(bounds) - topInset - bottomInset));
    if (CGRectGetWidth(panel) < 1.0f || CGRectGetHeight(panel) < 1.0f) return;

    UIRectCorner corners = 0;
    if (_firstItem) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (_lastItem) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    UIBezierPath *panelPath = corners
        ? [UIBezierPath bezierPathWithRoundedRect:panel
                                byRoundingCorners:corners
                                      cornerRadii:CGSizeMake(7.0f, 7.0f)]
        : [UIBezierPath bezierPathWithRect:panel];
    [((_selectedStyle || _active) ? VCSelectedCellColor() : VCCellBackgroundColor()) setFill];
    [panelPath fill];

    UIColor *panelBorder = _active
        ? [VCAccentColor() colorWithAlphaComponent:0.82f]
        : [VCSeparatorColor() colorWithAlphaComponent:0.72f];
    [panelBorder setStroke];
    panelPath.lineWidth = 0.75f;
    [panelPath stroke];

    if (!_lastItem) {
        if (_active) {
            [panelBorder setFill];
            UIRectFill(CGRectMake(CGRectGetMinX(panel),
                                  MAX(CGRectGetMinY(panel), CGRectGetMaxY(panel) - 0.75f),
                                  CGRectGetWidth(panel),
                                  0.75f));
        } else {
            [[VCSeparatorColor() colorWithAlphaComponent:0.52f] setFill];
            UIRectFill(CGRectMake(CGRectGetMinX(panel) + 14.0f,
                                  MAX(CGRectGetMinY(panel), CGRectGetMaxY(panel) - 0.5f),
                                  MAX(0.0f, CGRectGetWidth(panel) - 14.0f),
                                  0.5f));
        }
    }

    if (nestedItem) {
        CGFloat nodeX = 12.0f;
        CGFloat nodeY = CGRectGetMidY(panel);
        CGFloat lineTop = _firstItem ? CGRectGetMinY(panel) : 0.0f;
        CGFloat lineBottom = _lastItem ? nodeY : CGRectGetHeight(bounds);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetStrokeColorWithColor(context, [VCAccentColor() colorWithAlphaComponent:0.52f].CGColor);
        CGContextSetLineWidth(context, 1.5f);
        CGContextMoveToPoint(context, nodeX, lineTop);
        CGContextAddLineToPoint(context, nodeX, lineBottom);
        CGContextStrokePath(context);

        UIBezierPath *node = [UIBezierPath bezierPathWithArcCenter:CGPointMake(nodeX, nodeY)
                                                            radius:3.5f
                                                        startAngle:0.0f
                                                          endAngle:(CGFloat)(M_PI * 2.0f)
                                                         clockwise:YES];
        [VCBackgroundColor() setFill];
        [node fill];
        [VCAccentColor() setStroke];
        node.lineWidth = 1.5f;
        [node stroke];
    }
}

@end

@interface VCMainListCell : UITableViewCell {
    VCMainListCellKind _visualKind;
    BOOL _visualExpanded;
    BOOL _visualFirstItem;
    BOOL _visualLastItem;
    BOOL _visualActive;
    VCMainListCellBackgroundView *_normalVisualBackground;
    VCMainListCellBackgroundView *_selectedVisualBackground;
}
- (void)configureVisualKind:(VCMainListCellKind)kind
                   expanded:(BOOL)expanded
                  firstItem:(BOOL)firstItem
                   lastItem:(BOOL)lastItem
                      active:(BOOL)active;
- (void)refreshVisualAppearance;
- (BOOL)usesConfigurationItemLayout;
@end

static UIView *VCMainListCellReorderControlInView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass([subview class]) hasSuffix:@"ReorderControl"]) {
            return subview;
        }

        UIView *control = VCMainListCellReorderControlInView(subview);
        if (control) return control;
    }
    return nil;
}

@implementation VCMainListCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    _normalVisualBackground = [[VCMainListCellBackgroundView alloc] initWithFrame:self.bounds];
    _selectedVisualBackground = [[VCMainListCellBackgroundView alloc] initWithFrame:self.bounds];
    self.backgroundView = _normalVisualBackground;
    self.selectedBackgroundView = _selectedVisualBackground;

    return self;
}

- (void)dealloc {
    [_normalVisualBackground release];
    [_selectedVisualBackground release];
    [super dealloc];
}

- (void)configureVisualKind:(VCMainListCellKind)kind
                   expanded:(BOOL)expanded
                  firstItem:(BOOL)firstItem
                   lastItem:(BOOL)lastItem
                      active:(BOOL)active {
    _visualKind = kind;
    _visualExpanded = expanded;
    _visualFirstItem = firstItem;
    _visualLastItem = lastItem;
    _visualActive = active;
    [self refreshVisualAppearance];
    [self setNeedsLayout];
}

- (void)refreshVisualAppearance {
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.backgroundView = _normalVisualBackground;
    self.selectedBackgroundView = _selectedVisualBackground;

    [_normalVisualBackground configureKind:_visualKind
                                  expanded:_visualExpanded
                                 firstItem:_visualFirstItem
                                  lastItem:_visualLastItem
                                     active:_visualActive
                             selectedStyle:NO];
    [_selectedVisualBackground configureKind:_visualKind
                                    expanded:_visualExpanded
                                   firstItem:_visualFirstItem
                                    lastItem:_visualLastItem
                                       active:_visualActive
                               selectedStyle:YES];

    self.textLabel.textColor = VCPrimaryTextColor();
    self.textLabel.highlightedTextColor = VCPrimaryTextColor();
    self.detailTextLabel.textColor = VCSecondaryTextColor();
    self.detailTextLabel.highlightedTextColor = VCSecondaryTextColor();

    if (_visualKind == VCMainListCellKindSubscriptionHeader) {
        self.textLabel.font = [UIFont boldSystemFontOfSize:15.5f];
    } else {
        self.textLabel.font = [UIFont boldSystemFontOfSize:18.0f];
    }
}

- (BOOL)usesConfigurationItemLayout {
    return _visualKind == VCMainListCellKindSubscriptionItem ||
           _visualKind == VCMainListCellKindConfigurationItem;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsReorderControl) {
        UIView *reorderControl = VCMainListCellReorderControlInView(self);
        if (reorderControl && reorderControl.superview) {
            CGRect cellBounds = [self convertRect:self.bounds toView:reorderControl.superview];
            CGRect reorderFrame = reorderControl.frame;
            reorderFrame.origin.x = CGRectGetMaxX(cellBounds) - CGRectGetWidth(reorderFrame);
            reorderFrame.origin.y = floorf(CGRectGetMidY(cellBounds) -
                                            CGRectGetHeight(reorderFrame) * 0.5f);
            reorderControl.frame = reorderFrame;
        }
    }

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (self.accessoryView && !self.accessoryView.hidden) {
        CGRect accessoryFrame = self.accessoryView.frame;
        accessoryFrame.origin.x = floorf(CGRectGetWidth(self.bounds) -
                                         CGRectGetWidth(accessoryFrame) - 14.0f);
        accessoryFrame.origin.y = floorf((CGRectGetHeight(self.bounds) -
                                          CGRectGetHeight(accessoryFrame)) * 0.5f);
        self.accessoryView.frame = accessoryFrame;
    }

    if (_visualKind == VCMainListCellKindSubscriptionHeader) {
        CGFloat left = 14.0f;
        CGFloat rightPadding = 8.0f;
        self.textLabel.frame = CGRectMake(left, 9.0f, MAX(0.0f, width - left - rightPadding), 21.0f);
        self.detailTextLabel.frame = CGRectMake(left, 32.0f, MAX(0.0f, width - left - rightPadding), 15.0f);
    } else if ([self usesConfigurationItemLayout]) {
        CGFloat left = (_visualKind == VCMainListCellKindSubscriptionItem) ? 22.0f : 7.0f;
        CGFloat rightPadding = 8.0f;
        CGFloat topInset = _visualFirstItem ? 4.0f : 0.0f;
        self.textLabel.frame = CGRectMake(left, topInset + 4.0f,
                                          MAX(0.0f, width - left - rightPadding), 22.0f);
        self.detailTextLabel.frame = CGRectMake(left, topInset + 26.0f,
                                                MAX(0.0f, width - left - rightPadding), 14.0f);

        if (self.accessoryView && !self.accessoryView.hidden) {
            CGFloat height = CGRectGetHeight(self.bounds);
            CGFloat bottomInset = _visualLastItem ? 8.0f : 0.0f;
            CGFloat panelMidY = topInset + (height - topInset - bottomInset) * 0.5f;
            CGRect accessoryFrame = self.accessoryView.frame;
            accessoryFrame.origin.y = floorf(panelMidY - CGRectGetHeight(accessoryFrame) * 0.5f);
            self.accessoryView.frame = accessoryFrame;
        }
    }

    _normalVisualBackground.frame = self.bounds;
    _selectedVisualBackground.frame = self.bounds;
}

@end

@class SettingsVC;
@protocol SettingsVCDelegate <NSObject>
- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled;
@end

@interface SettingsVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate, VCUpdateCheckerDelegate> {
    UITableView *_tableView;
    UISwitch *_autoUpdateSwitch;
    UISwitch *_preserveCustomNamesSwitch;
    UISwitch *_stealthSwitch;
    UISwitch *_automaticUpdateChecksSwitch;
    UISwitch *_preferGitHubLegacySwitch;
    VCUpdateChecker *_updateChecker;
    NSString *_availableReleaseURL;
    BOOL _autoUpdate;
    BOOL _preserveCustomNames;
    BOOL _stealthMode;
    BOOL _darkTheme;
    BOOL _automaticUpdateChecks;
    CGFloat _footerWidth;
    id<SettingsVCDelegate> _delegate;
}
@property (nonatomic, assign) BOOL autoUpdate;
@property (nonatomic, assign) BOOL preserveCustomNames;
@property (nonatomic, assign) BOOL stealthMode;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, assign) BOOL automaticUpdateChecks;
@property (nonatomic, assign) id<SettingsVCDelegate> delegate;
@end

@interface XrayVersionSpoofVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    UITableView *_tableView;
    UISwitch *_enabledSwitch;
    UITextField *_versionField;
}
@end

@interface VCAppEventRecorder : NSObject {
    NSMutableArray *_events;
    NSMutableArray *_pendingEvents;
    dispatch_queue_t _writeQueue;
    BOOL _flushScheduled;
}
+ (VCAppEventRecorder *)sharedRecorder;
- (void)recordCategory:(NSString *)category action:(NSString *)action detail:(NSString *)detail;
- (NSArray *)eventsSnapshot;
- (void)flushNow;
- (void)clearEvents;
- (void)setAppActivityEnabled:(BOOL)enabled;
@end

@interface DiagnosticEventsVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    NSArray *_events;
}
- (id)initWithEvents:(NSArray *)events;
@end

typedef NS_ENUM(NSInteger, VCDebugSection) {
    VCDebugSectionLiveState = 0,
    VCDebugSectionConnectionQuality,
    VCDebugSectionActivityLogging,
    VCDebugSectionRecentActivity,
    VCDebugSectionDiagnostics,
    VCDebugSectionCount,
};

@interface DebugVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentInteractionControllerDelegate> {
    UITableView *_tableView;
    NSDictionary *_daemonState;
    NSArray *_daemonEvents;
    NSArray *_appEvents;
    NSMutableArray *_localEvents;
    NSArray *_displayEvents;
    NSDictionary *_qualityState;
    NSString *_lastNetwork;
    NSTimer *_refreshTimer;
    UIDocumentInteractionController *_documentController;
    UISwitch *_appActivitySwitch;
    BOOL _refreshing;
    BOOL _checking;
    BOOL _reporting;
    NSUInteger _qualityGeneration;
}
@end

@interface SettingsNavController : UINavigationController
@end

@interface RoutingVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    UISwitch *_enabledSwitch;
    UISwitch *_bypassLANSwitch;
    NSMutableArray *_rules;
    NSString *_pendingAction;
    NSString *_pendingType;
}
@end

@interface FAQVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
}
@end

@implementation FAQVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)question:(NSString *)question answer:(NSString *)answer {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            question ? question : @"", @"question",
            answer ? answer : @"", @"answer",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title questions:(NSArray *)questions {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            questions ? questions : [NSArray array], @"questions",
            nil];
}

- (void)buildSections {
    NSArray *gettingStarted = [NSArray arrayWithObjects:
        [self question:@"How do I import?"
                 answer:@"Tap + and choose Import from Clipboard, Import from File, Scan QR Code, or Manual Input. You can import vless:// and socks5:// configurations, HTTP/HTTPS subscription URLs, happ:// links, and Karing backup ZIP files or LAN Send QR codes."],
        [self question:@"How do I delete or reorder items?"
                 answer:@"Swipe a standalone configuration or subscription from right to left to delete it. To change the order, tap the list button beside Configurations or Subscriptions, drag the rows, then tap the checkmark to finish."],
        [self question:@"Do I need to respring after installation?"
                 answer:@"No. With the current package, wait for uicache to finish and for the installer to show “Installation done! You can now exit the installer.” A respring is only a fallback if the icon is still missing after installation has fully completed."],
        nil];

    NSArray *subscriptions = [NSArray arrayWithObjects:
        [self question:@"Where are the subscription details?"
                 answer:@"Tap the info button beside a subscription. The details page shows its source, provider description, configuration count, traffic, and expiry when the provider supplies that data. You can also update or delete that subscription there."],
        [self question:@"Why wasn't my subscription added?"
                 answer:@"The URL must return at least one parseable VLESS or SOCKS5 entry. Import can fail when the provider is unavailable, returns an empty or HTML response, has a certificate problem, or uses an unsupported format. The import alert shows a more specific reason when one is available."],
        [self question:@"What does auto-update do?"
                 answer:@"When enabled, subscriptions refresh once after a fresh app launch. It does not interrupt an active VPN connection. Use the refresh button to update all subscriptions manually, or open a subscription's details and choose Update Now to refresh only that one."],
        nil];

    NSArray *connections = [NSArray arrayWithObjects:
        [self question:@"Why can't I connect?"
                 answer:@"Make sure a configuration is selected, then check the message shown after pressing Connect. If the protocol text is red, the link contains an unsupported option. Otherwise, verify the server parameters, confirm that the server is online, and check both logs for the exact failure."],
        [self question:@"What can the app connect to?"
                 answer:@"Supported configurations:\n"
                         @"• VLESS TCP with no security, TLS, or Reality; with TLS/Reality, flow may be omitted or set to xtls-rprx-vision\n"
                         @"• VLESS XHTTP with no security, TLS, or Reality; modes auto, packet-up, stream-one, and stream-up\n"
                         @"• VLESS gRPC with no security, TLS, or Reality; single-stream and multi modes\n"
                         @"• VLESS WebSocket with TLS or no security\n"
                         @"• SOCKS5\n"
                         @"Supported fingerprints are chrome, firefox, edge, random, randomized, and qq."],
        [self question:@"Why is the protocol text red?"
                 answer:@"Red text means the transport, security type, mode, flow, or fingerprint is not supported. The app keeps the entry visible so you can identify it, but blocks the connection to avoid a broken tunnel. Press Connect to see the unsupported option."],
        [self question:@"How does routing work?"
                 answer:@"Open Settings → Routing. Enable it, choose the default Proxy, Direct, or Block action, then add ordered domain, IP/CIDR, or port rules. The first matching rule wins after the optional local-network bypass. Reconnect the VPN after changing the policy; existing connections are left untouched."],
        [self question:@"Does closing the app stop the VPN?"
                 answer:@"No. The connection belongs to the vpnctld background daemon and remains active after the app is closed. Reopen the app to manage it, or press Disconnect to stop it. After a full app relaunch, the on-screen timer may restart at 00:00:00 even though the tunnel stayed connected."],
        nil];

    NSArray *troubleshooting = [NSArray arrayWithObjects:
        [self question:@"Where can I find the logs?"
                 answer:@"Tap the terminal button on the main screen. The vpnctld log covers daemon and device-routing work; the vless-core log covers the selected proxy transport and server connection. The logs update live, and the trash button clears them. Logs are unavailable for encrypted HAPP subscriptions."],
        [self question:@"What does Stealth mode hide?"
                 answer:@"Stealth mode masks configuration and subscription links in the interface. It does not change the connection or redact technical logs. Configurations and subscriptions are encrypted in the protected local store regardless of Stealth mode. Encrypted HAPP subscriptions are protected separately and never expose their links or connection logs."],
        nil];

    NSArray *compatibility = [NSArray arrayWithObject:
        [self question:@"Which devices are supported?"
                 answer:@"A jailbreak is required. The package requires iOS 6 - iOS 10 and contains ARMv7 binaries. It supports compatible 32-bit devices as well as 64-bit devices (ARM64) running iOS 10 or earlier through 32-bit compatibility. It is tested on iOS 6.1.3 and iOS 10.3.3; other device and iOS combinations are not guaranteed."]];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
        [self sectionWithTitle:@"Getting started" questions:gettingStarted],
        [self sectionWithTitle:@"Subscriptions" questions:subscriptions],
        [self sectionWithTitle:@"Connections" questions:connections],
        [self sectionWithTitle:@"Privacy and troubleshooting" questions:troubleshooting],
        [self sectionWithTitle:@"Compatibility" questions:compatibility],
        nil];
    [_sections release];
    _sections = newSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FAQ";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
}

- (NSDictionary *)questionAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *section = [_sections objectAtIndex:indexPath.section];
    return [[section objectForKey:@"questions"] objectAtIndex:indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return [[[_sections objectAtIndex:section] objectForKey:@"questions"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self questionAtIndexPath:indexPath];
    NSString *answer = [item objectForKey:@"answer"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize answerSize = [answer sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 2000.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 31.0f + answerSize.height + 17.0f;
    return (height < 64.0f) ? 64.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kFAQCellId = @"FAQCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *item = [self questionAtIndexPath:indexPath];
    cell.textLabel.text = [item objectForKey:@"question"];
    cell.detailTextLabel.text = [item objectForKey:@"answer"];
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@interface AboutVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
    CGFloat _headerWidth;
}
@end

@implementation AboutVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSString *coreVersion = DetectCoreBinaryVersion();
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();
    NSString *redsocksVersion = DetectRedsocksVersion();

    NSArray *components = [NSArray arrayWithObjects:
                           [self rowWithTitle:@"vless-core-cli" detail:coreVersion],
                           [self rowWithTitle:@"vless-core-curl"
                                       detail:[NSString stringWithFormat:@"curl %@, OpenSSL %@ (%@), zlib %@",
                                               [deps objectForKey:@"curl"],
                                               [deps objectForKey:@"openssl"],
                                               opensslPatchStatus,
                                               [deps objectForKey:@"zlib"]]],
                           [self rowWithTitle:@"redsocks-vless-core" detail:redsocksVersion],
                           nil];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"Bundled components" rows:components],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (UIView *)tableHeaderForWidth:(CGFloat)width {
    CGFloat headerHeight = 212.0f;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImage *icon = LoadBundledIconScaled(@"Icon", 82.0f);
    UIImageView *iconView = [[[UIImageView alloc] initWithImage:icon] autorelease];
    iconView.frame = CGRectMake((width - 82.0f) / 2.0f, 22.0f, 82.0f, 82.0f);
    iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    iconView.layer.cornerRadius = 14.0f;
    iconView.layer.masksToBounds = YES;
    [header addSubview:iconView];

    UILabel *nameLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 112.0f, width - 32.0f, 28.0f)] autorelease];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    nameLabel.backgroundColor = [UIColor clearColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.textColor = VCPrimaryTextColor();
    nameLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    nameLabel.text = AppDisplayName();
    [header addSubview:nameLabel];

    UILabel *versionLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 140.0f, width - 32.0f, 22.0f)] autorelease];
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    versionLabel.backgroundColor = [UIColor clearColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.textColor = VCSecondaryTextColor();
    versionLabel.font = [UIFont systemFontOfSize:14.0f];
    versionLabel.text = AppVersionSummary();
    [header addSubview:versionLabel];

    UILabel *buildLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 162.0f, width - 32.0f, 44.0f)] autorelease];
    buildLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    buildLabel.backgroundColor = [UIColor clearColor];
    buildLabel.textAlignment = NSTextAlignmentCenter;
    buildLabel.textColor = VCSecondaryTextColor();
    buildLabel.font = [UIFont systemFontOfSize:14.0f];
    buildLabel.numberOfLines = 2;
    buildLabel.text = AppBuildMetadataSummary();
    [header addSubview:buildLabel];

    return header;
}

- (UIView *)tableFooterForWidth:(CGFloat)width {
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 48.0f)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 8.0f, width - 32.0f, 24.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = VCSecondaryTextColor();
    label.font = [UIFont boldSystemFontOfSize:14.0f];
    label.text = @"made by notfence";
    [footer addSubview:label];

    return footer;
}

- (void)updateTableHeaderAndFooterForWidth:(CGFloat)width {
    if (width <= 0.0f) {
        return;
    }

    _headerWidth = width;
    _tableView.tableHeaderView = [self tableHeaderForWidth:width];
    _tableView.tableFooterView = [self tableFooterForWidth:width];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
    [self updateTableHeaderAndFooterForWidth:_tableView.bounds.size.width];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = _tableView.bounds.size.width;
    if (fabs(_headerWidth - width) > 0.5f) {
        [self updateTableHeaderAndFooterForWidth:width];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kAboutCellId = @"AboutCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@interface LicenseDocumentVC : UIViewController {
    UITextView *_textView;
    NSString *_documentText;
    NSString *_resourceName;
    NSString *_marker;
    BOOL _didScrollToMarker;
}
- (id)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName marker:(NSString *)marker;
@end

@implementation LicenseDocumentVC

- (id)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName marker:(NSString *)marker {
    self = [super init];
    if (self) {
        self.title = title;
        _resourceName = [resourceName copy];
        _marker = [marker copy];
    }
    return self;
}

- (void)dealloc {
    [_textView release];
    [_documentText release];
    [_resourceName release];
    [_marker release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VCBackgroundColor();

    NSString *path = [[NSBundle mainBundle] pathForResource:_resourceName ofType:nil];
    NSString *text = path
        ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]
        : nil;
    if (![text length]) {
        text = @"License information is unavailable.";
    }
    _documentText = [text copy];

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.backgroundColor = VCBackgroundColor();
    _textView.textColor = VCPrimaryTextColor();
    _textView.font = [UIFont systemFontOfSize:13.0f];
    _textView.editable = NO;
    _textView.text = _documentText;
    [self.view addSubview:_textView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_didScrollToMarker || ![_marker length]) {
        return;
    }

    NSRange range = [_documentText rangeOfString:_marker options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound) {
        [_textView scrollRangeToVisible:range];
        _textView.selectedRange = NSMakeRange(range.location, 0);
    }
    _didScrollToMarker = YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@interface CreditsVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
}
@end

@implementation CreditsVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)licensedRowWithTitle:(NSString *)title detail:(NSString *)detail marker:(NSString *)marker {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            @"THIRD_PARTY_LICENSES.txt", @"licenseResource",
            marker ? marker : @"", @"licenseMarker",
            nil];
}

- (NSDictionary *)projectLicenseRow {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"vless-core-app", @"title",
            @"vless-core-app Source License 1.0. Click to read the license.", @"detail",
            @"LICENSE", @"licenseResource",
            @"", @"licenseMarker",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();

    NSArray *libraries = [NSArray arrayWithObjects:
                          [self licensedRowWithTitle:@"curl"
                                              detail:[NSString stringWithFormat:@"HTTP client library, version %@. License: curl license.", [deps objectForKey:@"curl"]]
                                              marker:@"curl 8.21.0"],
                          [self licensedRowWithTitle:@"OpenSSL"
                                              detail:[NSString stringWithFormat:@"TLS library, version %@, %@. License: Apache 2.0.", [deps objectForKey:@"openssl"], opensslPatchStatus]
                                              marker:@"OpenSSL 3.5.7"],
                          [self licensedRowWithTitle:@"zlib"
                                              detail:[NSString stringWithFormat:@"Compression library, version %@. License: zlib license.", [deps objectForKey:@"zlib"]]
                                              marker:@"zlib 1.3.1"],
                          [self licensedRowWithTitle:@"libevent"
                                              detail:@"Event loop library used by redsocks. License: BSD-style licenses."
                                              marker:@"libevent 2.1.12-stable"],
                          [self licensedRowWithTitle:@"ZBar"
                                              detail:@"QR code recognition library, version 0.23.93. License: LGPL 2.1 or later."
                                              marker:@"ZBar 0.23.93"],
                          [self licensedRowWithTitle:@"CA certificates"
                                              detail:@"Mozilla CA bundle packaged as cacert.pem. License: MPL 2.0."
                                              marker:@"Mozilla CA certificate bundle"],
                          [self licensedRowWithTitle:@"redsocks"
                                              detail:@"SOCKS5 redirector used for full-device routing. License: Apache 2.0."
                                              marker:@"redsocks"],
                          nil];

    NSArray *thanks = [NSArray arrayWithObject:
                       [self rowWithTitle:@"Special thanks to:" detail:@"@kirillshpitalev for testing and debugging\n"
                                                                       @"@rafal_official for testing and debugging\n"
                                                                       @"@polin0m for testing and debugging\n"
                                                                       @"@cmp_73 for testing and debugging"]];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"License" rows:[NSArray arrayWithObject:[self projectLicenseRow]]],
                            [self sectionWithTitle:@"Third-party software" rows:libraries],
                            [self sectionWithTitle:@"Special thanks" rows:thanks],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Credits";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCreditsCellId = @"CreditsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    BOOL hasLicense = [[row objectForKey:@"licenseResource"] length] > 0;
    cell.selectionStyle = hasLicense ? UITableViewCellSelectionStyleBlue
                                     : UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = hasLicense ? VCCreateDisclosureAccessoryView() : nil;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *resourceName = [row objectForKey:@"licenseResource"];
    NSString *marker = [row objectForKey:@"licenseMarker"];
    if ([resourceName length]) {
        LicenseDocumentVC *license = [[[LicenseDocumentVC alloc]
            initWithTitle:[row objectForKey:@"title"] resourceName:resourceName marker:marker] autorelease];
        [self.navigationController pushViewController:license animated:YES];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

static NSInteger const kRoutingAddActionSheetTag = 6101;
static NSInteger const kRoutingAddTypeSheetTag = 6102;
static NSInteger const kRoutingValueAlertTag = 6103;
static NSInteger const kRoutingRuleActionSheetTagBase = 6200;

@implementation RoutingVC

- (NSString *)defaultAction {
    NSString *value = [[[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsRoutingDefaultKey] lowercaseString];
    if (![value isEqualToString:@"proxy"] &&
        ![value isEqualToString:@"direct"] &&
        ![value isEqualToString:@"block"]) {
        return @"proxy";
    }
    return value;
}

- (BOOL)bypassLAN {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud objectForKey:kDefaultsRoutingBypassLANKey] == nil
        ? YES
        : [ud boolForKey:kDefaultsRoutingBypassLANKey];
}

- (void)saveRules {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:_rules forKey:kDefaultsRoutingRulesKey];
    [ud synchronize];
    VCRecordAppEvent(@"settings", @"Routing rules saved",
                     [NSString stringWithFormat:@"rules=%lu", (unsigned long)[_rules count]]);
}

- (void)enabledChanged:(UISwitch *)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender isOn] forKey:kDefaultsRoutingEnabledKey];
    [ud synchronize];
    [_tableView reloadData];
    VCRecordAppEvent(@"settings", @"Routing changed", [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (void)bypassLANChanged:(UISwitch *)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender isOn] forKey:kDefaultsRoutingBypassLANKey];
    [ud synchronize];
    VCRecordAppEvent(@"settings", @"LAN bypass changed", [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (void)setDefaultAction:(NSString *)action {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:action forKey:kDefaultsRoutingDefaultKey];
    [ud synchronize];
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
              withRowAnimation:UITableViewRowAnimationNone];
    VCRecordAppEvent(@"settings", @"Routing default action changed",
                     [NSString stringWithFormat:@"action=%@", action]);
}

- (NSString *)displayNameForAction:(NSString *)action {
    if ([action isEqualToString:@"direct"]) return @"Direct";
    if ([action isEqualToString:@"block"]) return @"Block";
    return @"Proxy";
}

- (NSString *)displayNameForType:(NSString *)type {
    if ([type isEqualToString:@"domain"]) return @"Domain";
    if ([type isEqualToString:@"suffix"]) return @"Domain suffix";
    if ([type isEqualToString:@"cidr"]) return @"IP / CIDR";
    return @"Port";
}

- (UIColor *)colorForAction:(NSString *)action {
    if ([action isEqualToString:@"direct"]) return VCSuccessColor();
    if ([action isEqualToString:@"block"]) return VCErrorColor();
    return VCAccentColor();
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Routing";
    self.view.backgroundColor = VCBackgroundColor();

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsRoutingRulesKey];
    _rules = saved ? [[NSMutableArray alloc] initWithArray:saved copyItems:YES]
                   : [[NSMutableArray alloc] init];

    _enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_enabledSwitch setOn:[[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsRoutingEnabledKey] animated:NO];
    [_enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    _bypassLANSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_bypassLANSwitch setOn:[self bypassLAN] animated:NO];
    [_bypassLANSwitch addTarget:self action:@selector(bypassLANChanged:) forControlEvents:UIControlEventValueChanged];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _enabledSwitch.onTintColor = VCAccentColor();
    _bypassLANSwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [_tableView setEditing:editing animated:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0 || section == 2) return 1;
    if (section == 1) return 3;
    return (NSInteger)[_rules count] + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Routing";
    if (section == 1) return @"Default action";
    if (section == 2) return @"Local network";
    return @"Rules — first match wins";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return @"When disabled, all supported traffic uses the selected proxy.";
    }
    if (section == 2) {
        return @"Keeps private, link-local and carrier-grade NAT addresses outside the proxy.";
    }
    if (section == 3) {
        return @"Reconnect the VPN to apply routing changes.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text) return 0.01f;

    CGFloat width = MAX(1.0f, tableView.bounds.size.width - 36.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14.0f]
                   constrainedToSize:CGSizeMake(width, 1000.0f)
                       lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height) + 14.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text) return nil;

    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    UIView *footer = [[[UIView alloc] initWithFrame:
                       CGRectMake(0.0f, 0.0f, tableView.bounds.size.width, height)] autorelease];
    footer.backgroundColor = [UIColor clearColor];

    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(18.0f, 4.0f, tableView.bounds.size.width - 36.0f, height - 8.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:14.0f];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textColor = VCSecondaryTextColor();
    label.text = text;
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"RoutingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID] autorelease];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.detailTextLabel.text = nil;
    VCAppearanceApplyCell(cell);

    if (indexPath.section == 0) {
        cell.textLabel.text = @"Enable routing";
        cell.detailTextLabel.text = @"Apply ordered Proxy, Direct and Block rules";
        cell.accessoryView = _enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        NSString *action = [actions objectAtIndex:indexPath.row];
        cell.textLabel.text = [self displayNameForAction:action];
        cell.detailTextLabel.text = indexPath.row == 0
            ? @"Use the selected configuration"
            : (indexPath.row == 1 ? @"Connect without the proxy" : @"Reject the connection");
        cell.textLabel.textColor = [self colorForAction:action];
        cell.accessoryType = [[self defaultAction] isEqualToString:action]
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Bypass local networks";
        cell.detailTextLabel.text = @"LAN, link-local and CGNAT";
        cell.accessoryView = _bypassLANSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row < (NSInteger)[_rules count]) {
        NSDictionary *rule = [_rules objectAtIndex:indexPath.row];
        NSString *action = [rule objectForKey:@"action"];
        NSString *type = [rule objectForKey:@"type"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@",
                               [self displayNameForAction:action],
                               [rule objectForKey:@"value"]];
        cell.detailTextLabel.text = [self displayNameForType:type];
        cell.textLabel.textColor = [self colorForAction:action];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
    } else {
        cell.textLabel.text = @"Add Rule";
        cell.detailTextLabel.text = @"Domain, IP/CIDR or port";
        cell.textLabel.textColor = VCAccentColor();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    cell.backgroundColor = VCCellBackgroundColor();
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 3 && indexPath.row < (NSInteger)[_rules count];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 3 && indexPath.row < (NSInteger)[_rules count];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    (void)tableView;
    (void)sourceIndexPath;
    if (proposedDestinationIndexPath.section != 3) {
        return [NSIndexPath indexPathForRow:0 inSection:3];
    }
    NSInteger last = (NSInteger)[_rules count] - 1;
    if (proposedDestinationIndexPath.row > last) {
        return [NSIndexPath indexPathForRow:last inSection:3];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView;
    NSDictionary *rule = [[_rules objectAtIndex:sourceIndexPath.row] retain];
    [_rules removeObjectAtIndex:sourceIndexPath.row];
    [_rules insertObject:rule atIndex:destinationIndexPath.row];
    [rule release];
    [self saveRules];
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete ||
        indexPath.section != 3 ||
        indexPath.row >= (NSInteger)[_rules count]) return;
    [_rules removeObjectAtIndex:indexPath.row];
    [self saveRules];
    [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)showRuleTypeSheet {
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Match"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"Exact Domain", @"Domain Suffix", @"IP or CIDR", @"Port or Range", nil] autorelease];
    sheet.tag = kRoutingAddTypeSheetTag;
    [sheet showInView:self.view];
}

- (void)showRuleValuePrompt {
    NSString *title = [self displayNameForType:_pendingType];
    NSString *message = nil;
    if ([_pendingType isEqualToString:@"domain"]) message = @"Example: api.example.com";
    else if ([_pendingType isEqualToString:@"suffix"]) message = @"Example: example.com";
    else if ([_pendingType isEqualToString:@"cidr"]) message = @"Example: 203.0.113.0/24";
    else message = @"Example: 80 or 8000-8999";

    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:title
                                                     message:message
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Add", nil] autorelease];
    alert.tag = kRoutingValueAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [[alert textFieldAtIndex:0] setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [[alert textFieldAtIndex:0] setAutocorrectionType:UITextAutocorrectionTypeNo];
    [alert show];
}

- (NSString *)normalizedRuleValue:(NSString *)input type:(NSString *)type {
    NSString *value = [[[input stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString] copy];
    if ([value length] == 0 || [value length] > 128 ||
        [value rangeOfCharacterFromSet:
         [NSCharacterSet characterSetWithCharactersInString:@";,\r\n\t "]].location != NSNotFound) {
        [value release];
        return nil;
    }

    BOOL valid = NO;
    if ([type isEqualToString:@"domain"] || [type isEqualToString:@"suffix"]) {
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
                                @"abcdefghijklmnopqrstuvwxyz0123456789-_."] invertedSet];
        valid = [value rangeOfCharacterFromSet:bad].location == NSNotFound &&
                ![value hasPrefix:@"."] && ![value hasSuffix:@"."] &&
                [value rangeOfString:@".."].location == NSNotFound;
    } else if ([type isEqualToString:@"cidr"]) {
        NSArray *parts = [value componentsSeparatedByString:@"/"];
        if ([parts count] == 1 || [parts count] == 2) {
            NSString *address = [parts objectAtIndex:0];
            unsigned char bytes[16];
            BOOL is4 = inet_pton(AF_INET, [address UTF8String], bytes) == 1;
            BOOL is6 = inet_pton(AF_INET6, [address UTF8String], bytes) == 1;
            valid = is4 || is6;
            if (valid && [parts count] == 2) {
                NSString *prefixText = [parts objectAtIndex:1];
                NSInteger prefix = [prefixText integerValue];
                valid = [prefixText length] > 0 &&
                        prefix >= 0 && prefix <= (is4 ? 32 : 128) &&
                        [[NSString stringWithFormat:@"%ld", (long)prefix] isEqualToString:prefixText];
            }
        }
    } else if ([type isEqualToString:@"port"]) {
        NSArray *parts = [value componentsSeparatedByString:@"-"];
        if ([parts count] == 1 || [parts count] == 2) {
            NSString *firstText = [parts objectAtIndex:0];
            NSString *lastText = [parts count] == 2 ? [parts objectAtIndex:1] : firstText;
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([firstText length] > 0 && [lastText length] > 0 &&
                [firstText rangeOfCharacterFromSet:nonDigits].location == NSNotFound &&
                [lastText rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                NSInteger first = [firstText integerValue];
                NSInteger last = [lastText integerValue];
                valid = first > 0 && first <= 65535 &&
                        last >= first && last <= 65535;
            }
        }
    }

    if (!valid) {
        [value release];
        return nil;
    }
    return [value autorelease];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        [self setDefaultAction:[actions objectAtIndex:indexPath.row]];
        return;
    }
    if (indexPath.section != 3) return;

    if (indexPath.row == (NSInteger)[_rules count]) {
        if ([_rules count] >= 24) {
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Rule Limit"
                                                             message:@"A maximum of 24 routing rules is supported."
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil] autorelease];
            [alert show];
            return;
        }
        UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Action"
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Proxy", @"Direct", @"Block", nil] autorelease];
        sheet.tag = kRoutingAddActionSheetTag;
        [sheet showInView:self.view];
        return;
    }

    NSDictionary *rule = [_rules objectAtIndex:indexPath.row];
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:
                             [NSString stringWithFormat:@"%@ · %@",
                              [self displayNameForType:[rule objectForKey:@"type"]],
                              [rule objectForKey:@"value"]]
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:@"Delete"
                                                otherButtonTitles:@"Use Proxy", @"Use Direct", @"Use Block", nil] autorelease];
    sheet.tag = kRoutingRuleActionSheetTagBase + indexPath.row;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (actionSheet.tag == kRoutingAddActionSheetTag) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)[actions count]) return;
        [_pendingAction release];
        _pendingAction = [[actions objectAtIndex:buttonIndex] copy];
        [self showRuleTypeSheet];
        return;
    }
    if (actionSheet.tag == kRoutingAddTypeSheetTag) {
        NSArray *types = [NSArray arrayWithObjects:@"domain", @"suffix", @"cidr", @"port", nil];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)[types count]) return;
        [_pendingType release];
        _pendingType = [[types objectAtIndex:buttonIndex] copy];
        [self showRuleValuePrompt];
        return;
    }
    if (actionSheet.tag >= kRoutingRuleActionSheetTagBase) {
        NSInteger index = actionSheet.tag - kRoutingRuleActionSheetTagBase;
        if (index < 0 || index >= (NSInteger)[_rules count]) return;
        if (buttonIndex == actionSheet.destructiveButtonIndex) {
            [_rules removeObjectAtIndex:index];
        } else {
            NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
            NSInteger actionIndex = buttonIndex - 1;
            if (actionIndex < 0 || actionIndex >= (NSInteger)[actions count]) return;
            NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:
                                             [_rules objectAtIndex:index]];
            [updated setObject:[actions objectAtIndex:actionIndex] forKey:@"action"];
            [_rules replaceObjectAtIndex:index withObject:updated];
        }
        [self saveRules];
        [_tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != kRoutingValueAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    NSString *value = [self normalizedRuleValue:[[alertView textFieldAtIndex:0] text]
                                           type:_pendingType];
    if (!value) {
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid Rule"
                                                         message:@"Check the value and try again."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [error show];
        return;
    }
    NSDictionary *rule = [NSDictionary dictionaryWithObjectsAndKeys:
                          (_pendingAction ? _pendingAction : @"proxy"), @"action",
                          (_pendingType ? _pendingType : @"domain"), @"type",
                          value, @"value",
                          nil];
    [_rules addObject:rule];
    [self saveRules];
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
              withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    [_tableView release];
    [_enabledSwitch release];
    [_bypassLANSwitch release];
    [_rules release];
    [_pendingAction release];
    [_pendingType release];
    [super dealloc];
}

@end

@implementation XrayVersionSpoofVC

- (void)dealloc {
    [_tableView release];
    [_enabledSwitch release];
    [_versionField release];
    [super dealloc];
}

- (BOOL)saveVersion {
    NSString *value = [_versionField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!VCXrayVersionIsValid(value)) {
        _versionField.text = VCSelectedXrayVersion();
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid version"
                                                        message:@"Use x.y.z; each number must be from 0 to 255."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil] autorelease];
        [error show];
        return NO;
    }

    _versionField.text = value;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:value forKey:kDefaultsXrayVersionKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"Xray spoof version saved", nil);
    return YES;
}

- (void)enabledSwitchChanged:(UISwitch *)sender {
    if ([sender isOn] && ![self saveVersion]) {
        [sender setOn:NO animated:YES];
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:[sender isOn] forKey:kDefaultsXrayVersionSpoofEnabledKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"Xray version spoof changed",
                     [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    (void)textField;
    [self saveVersion];
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _enabledSwitch.onTintColor = VCAccentColor();
    _versionField.textColor = VCPrimaryTextColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Xray version spoof";

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    _enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_enabledSwitch setOn:VCXrayVersionSpoofEnabled() animated:NO];
    [_enabledSwitch addTarget:self
                       action:@selector(enabledSwitchChanged:)
             forControlEvents:UIControlEventValueChanged];

    CGFloat fieldWidth = IsPadDevice() ? 220.0f : 150.0f;
    _versionField = [[UITextField alloc] initWithFrame:CGRectMake(0.0f, 0.0f, fieldWidth, 30.0f)];
    _versionField.borderStyle = UITextBorderStyleNone;
    _versionField.backgroundColor = [UIColor clearColor];
    _versionField.textAlignment = NSTextAlignmentRight;
    _versionField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _versionField.text = VCSelectedXrayVersion();
    _versionField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    _versionField.returnKeyType = UIReturnKeyDone;
    _versionField.autocorrectionType = UITextAutocorrectionTypeNo;
    _versionField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _versionField.clearButtonMode = UITextFieldViewModeNever;
    _versionField.delegate = self;

    [self applyTheme];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return @"Xray version";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [NSString stringWithFormat:
            @"When disabled, vless-core-cli reports Xray version %@. Changes apply on the next connection.",
            kDefaultXrayVersion];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat width = MAX(1.0f, tableView.bounds.size.width - 36.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14.0f]
                   constrainedToSize:CGSizeMake(width, 1000.0f)
                       lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height) + 14.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    UIView *footer = [[[UIView alloc] initWithFrame:
                       CGRectMake(0.0f, 0.0f, tableView.bounds.size.width, height)] autorelease];
    footer.backgroundColor = [UIColor clearColor];

    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(18.0f, 4.0f, tableView.bounds.size.width - 36.0f, height - 8.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:14.0f];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.text = text;
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"XrayVersionSpoofCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:cellIdentifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = (indexPath.row == 0) ? @"Enabled" : @"Version";
    cell.accessoryView = (indexPath.row == 0) ? (UIView *)_enabledSwitch : (UIView *)_versionField;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

@end

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

static NSString *VCSanitizeDiagnosticText(NSString *value, NSUInteger maximumLength) {
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

static NSString *VCDiagnosticErrorCategory(NSString *errorText) {
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

static NSInteger VCDiagnosticIntegerAfterMarker(NSString *text,
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

static NSString *VCDiagnosticErrorSummary(NSString *errorText) {
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

static void VCIncrementDiagnosticCategory(NSMutableDictionary *counts, NSString *errorText) {
    if (![counts isKindOfClass:[NSMutableDictionary class]]) return;
    NSString *category = VCDiagnosticErrorCategory(errorText);
    NSUInteger count = [[counts objectForKey:category] unsignedIntegerValue];
    [counts setObject:[NSNumber numberWithUnsignedInteger:count + 1] forKey:category];
}

static NSString *VCDiagnosticCategoryCountsText(NSDictionary *counts) {
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

static NSDictionary *VCMakeAppDiagnosticEvent(long long timestamp,
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

static BOOL VCAppActivityLoggingEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsDiagnosticAppActivityKey];
}

static BOOL VCIsOptionalAppDiagnosticEvent(NSString *category, NSString *action) {
    if ([category isEqualToString:@"connection"] ||
        [category isEqualToString:@"diagnostics"] ||
        [category isEqualToString:@"ping"]) return NO;
    if ([category isEqualToString:@"subscription"] &&
        [action rangeOfString:@"update" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return YES;
}

static BOOL VCOpenDiagnosticEventDatabase(sqlite3 **databaseOut) {
    if (!databaseOut || !VCEnsureSecureStoreDirectory()) return NO;
    *databaseOut = NULL;
    struct stat existing;
    const char *path = [kDiagnosticEventDatabasePath fileSystemRepresentation];
    if (lstat(path, &existing) == 0 &&
        (!S_ISREG(existing.st_mode) || S_ISLNK(existing.st_mode) ||
         existing.st_uid != geteuid() || existing.st_nlink != 1)) return NO;
    int rc = sqlite3_open_v2([kDiagnosticEventDatabasePath fileSystemRepresentation],
                             databaseOut,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                             NULL);
    if (rc != SQLITE_OK || !*databaseOut) {
        if (*databaseOut) sqlite3_close(*databaseOut);
        *databaseOut = NULL;
        return NO;
    }
    sqlite3_busy_timeout(*databaseOut, 1000);
    const char *setup =
        "PRAGMA journal_mode=DELETE;"
        "PRAGMA synchronous=NORMAL;"
        "PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS events ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "timestamp INTEGER NOT NULL,"
        "category TEXT NOT NULL,"
        "action TEXT NOT NULL,"
        "detail TEXT"
        ");";
    if (sqlite3_exec(*databaseOut, setup, NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_close(*databaseOut);
        *databaseOut = NULL;
        return NO;
    }
    (void)chmod([kDiagnosticEventDatabasePath fileSystemRepresentation], 0600);
    return YES;
}

static NSArray *VCLoadDiagnosticEventDatabase(void) {
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabase(&database)) return [NSArray array];
    const char *query =
        "SELECT timestamp, category, action, detail FROM ("
        "SELECT id, timestamp, category, action, detail "
        "FROM events ORDER BY id DESC LIMIT 250"
        ") ORDER BY id ASC;";
    sqlite3_stmt *statement = NULL;
    NSMutableArray *events = [NSMutableArray array];
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const unsigned char *categoryBytes = sqlite3_column_text(statement, 1);
            const unsigned char *actionBytes = sqlite3_column_text(statement, 2);
            const unsigned char *detailBytes = sqlite3_column_text(statement, 3);
            NSString *category = categoryBytes ? [NSString stringWithUTF8String:(const char *)categoryBytes] : nil;
            NSString *action = actionBytes ? [NSString stringWithUTF8String:(const char *)actionBytes] : nil;
            NSString *detail = detailBytes ? [NSString stringWithUTF8String:(const char *)detailBytes] : nil;
            NSDictionary *event = VCMakeAppDiagnosticEvent(sqlite3_column_int64(statement, 0),
                                                           category,
                                                           action,
                                                           detail);
            if (event) [events addObject:event];
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
    return events;
}

static BOOL VCInsertDiagnosticEventBatch(NSArray *events) {
    if (![events isKindOfClass:[NSArray class]] || [events count] == 0) return YES;
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabase(&database)) return NO;
    BOOL ok = sqlite3_exec(database, "BEGIN IMMEDIATE;", NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_stmt *statement = NULL;
    const char *insert = "INSERT INTO events(timestamp, category, action, detail) VALUES(?, ?, ?, ?);";
    if (ok) ok = sqlite3_prepare_v2(database, insert, -1, &statement, NULL) == SQLITE_OK;
    for (NSDictionary *candidate in events) {
        if (!ok) break;
        NSDictionary *event = VCMakeAppDiagnosticEvent(
            [[candidate objectForKey:@"timestamp"] longLongValue],
            [candidate objectForKey:@"category"],
            [candidate objectForKey:@"action"],
            [candidate objectForKey:@"detail"]);
        if (!event) continue;
        NSString *detail = [event objectForKey:@"detail"];
        sqlite3_bind_int64(statement, 1, [[event objectForKey:@"timestamp"] longLongValue]);
        sqlite3_bind_text(statement, 2, [[event objectForKey:@"category"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, [[event objectForKey:@"action"] UTF8String], -1, SQLITE_TRANSIENT);
        if ([detail length] > 0) sqlite3_bind_text(statement, 4, [detail UTF8String], -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(statement, 4);
        ok = sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
    }
    if (statement) sqlite3_finalize(statement);
    if (ok) {
        ok = sqlite3_exec(database,
                          "DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 250);",
                          NULL, NULL, NULL) == SQLITE_OK;
    }
    if (ok) ok = sqlite3_exec(database, "COMMIT;", NULL, NULL, NULL) == SQLITE_OK;
    else sqlite3_exec(database, "ROLLBACK;", NULL, NULL, NULL);
    sqlite3_close(database);
    return ok;
}

static void VCClearDiagnosticEventDatabase(void) {
    sqlite3 *database = NULL;
    if (VCOpenDiagnosticEventDatabase(&database)) {
        sqlite3_exec(database, "DELETE FROM events;", NULL, NULL, NULL);
        sqlite3_exec(database, "DELETE FROM sqlite_sequence WHERE name='events';", NULL, NULL, NULL);
        sqlite3_exec(database, "VACUUM;", NULL, NULL, NULL);
        sqlite3_close(database);
    }
}

static void VCPurgeOptionalDiagnosticEvents(void) {
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabase(&database)) return;
    sqlite3_exec(database,
                 "DELETE FROM events "
                 "WHERE category NOT IN ('connection','diagnostics','ping') "
                 "AND NOT (category='subscription' AND action LIKE '%update%');",
                 NULL, NULL, NULL);
    sqlite3_close(database);
}

@implementation VCAppEventRecorder

+ (VCAppEventRecorder *)sharedRecorder {
    static VCAppEventRecorder *recorder = nil;
    @synchronized(self) {
        if (!recorder) recorder = [[VCAppEventRecorder alloc] init];
    }
    return recorder;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _events = [[NSMutableArray alloc] init];
    _pendingEvents = [[NSMutableArray alloc] init];
    _writeQueue = dispatch_queue_create("com.vlesscore.diagnostics.write", DISPATCH_QUEUE_SERIAL);
    BOOL appActivityEnabled = VCAppActivityLoggingEnabled();
    NSArray *stored = VCLoadDiagnosticEventDatabase();
    for (NSDictionary *event in stored) {
        if (appActivityEnabled ||
            !VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                            [event objectForKey:@"action"])) {
            [_events addObject:event];
        }
    }
    if (!appActivityEnabled && _writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCPurgeOptionalDiagnosticEvents();
            [pool drain];
        });
    }
    return self;
}

- (void)scheduleFlushOnMainThread {
    @synchronized(self) {
        if (!_flushScheduled) return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    [self performSelector:@selector(flushPendingEvents) withObject:nil afterDelay:2.0];
}

- (void)recordCategory:(NSString *)category action:(NSString *)action detail:(NSString *)detail {
    if (!VCAppActivityLoggingEnabled() && VCIsOptionalAppDiagnosticEvent(category, action)) return;
    NSTimeInterval seconds = [[NSDate date] timeIntervalSince1970];
    NSDictionary *event = VCMakeAppDiagnosticEvent((long long)(seconds * 1000.0),
                                                   category,
                                                   action,
                                                   detail);
    if (!event) return;
    @synchronized(self) {
        [_events addObject:event];
        [_pendingEvents addObject:event];
        if ([_events count] > kVCDiagnosticEventCapacity) {
            [_events removeObjectsInRange:
             NSMakeRange(0, [_events count] - kVCDiagnosticEventCapacity)];
        }
        if ([_pendingEvents count] > kVCDiagnosticEventCapacity) {
            [_pendingEvents removeObjectsInRange:
             NSMakeRange(0, [_pendingEvents count] - kVCDiagnosticEventCapacity)];
        }
        _flushScheduled = YES;
    }
    [self performSelectorOnMainThread:@selector(scheduleFlushOnMainThread)
                           withObject:nil
                        waitUntilDone:NO];
}

- (NSArray *)eventsSnapshot {
    @synchronized(self) {
        return [[_events copy] autorelease];
    }
}

- (void)flushPendingEvents {
    NSArray *pending = nil;
    @synchronized(self) {
        if (!_flushScheduled) return;
        _flushScheduled = NO;
        if ([_pendingEvents count] == 0) return;
        pending = [_pendingEvents copy];
        [_pendingEvents removeAllObjects];
    }
    if (_writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCInsertDiagnosticEventBatch(pending);
            [pending release];
            [pool drain];
        });
    } else {
        [pending release];
    }
}

- (void)flushNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    NSArray *pending = nil;
    @synchronized(self) {
        _flushScheduled = NO;
        if ([_pendingEvents count] > 0) {
            pending = [_pendingEvents copy];
            [_pendingEvents removeAllObjects];
        }
    }
    if (_writeQueue && pending) {
        dispatch_sync(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCInsertDiagnosticEventBatch(pending);
            [pool drain];
        });
    }
    [pending release];
}

- (void)clearEvents {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    @synchronized(self) {
        _flushScheduled = NO;
        [_events removeAllObjects];
        [_pendingEvents removeAllObjects];
    }
    if (_writeQueue) {
        dispatch_sync(_writeQueue, ^{
            VCClearDiagnosticEventDatabase();
        });
    } else {
        VCClearDiagnosticEventDatabase();
    }
}

- (void)setAppActivityEnabled:(BOOL)enabled {
    if (enabled) return;
    @synchronized(self) {
        for (NSInteger index = (NSInteger)[_events count] - 1; index >= 0; index--) {
            NSDictionary *event = [_events objectAtIndex:index];
            if (VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                               [event objectForKey:@"action"])) {
                [_events removeObjectAtIndex:index];
            }
        }
        for (NSInteger index = (NSInteger)[_pendingEvents count] - 1; index >= 0; index--) {
            NSDictionary *event = [_pendingEvents objectAtIndex:index];
            if (VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                               [event objectForKey:@"action"])) {
                [_pendingEvents removeObjectAtIndex:index];
            }
        }
    }
    if (_writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCPurgeOptionalDiagnosticEvents();
            [pool drain];
        });
    }
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
#if !OS_OBJECT_USE_OBJC
    if (_writeQueue) dispatch_release(_writeQueue);
#endif
    [_pendingEvents release];
    [_events release];
    [super dealloc];
}

@end

static void VCRecordAppEvent(NSString *category, NSString *action, NSString *detail) {
    [[VCAppEventRecorder sharedRecorder] recordCategory:category action:action detail:detail];
}

static NSString *VCEventTimeText(NSDictionary *event) {
    long long milliseconds = [[event objectForKey:@"timestamp"] longLongValue];
    time_t seconds = (time_t)(milliseconds / 1000LL);
    struct tm local;
    memset(&local, 0, sizeof(local));
    if (!localtime_r(&seconds, &local)) return @"--:--:--";
    return [NSString stringWithFormat:@"%02d:%02d:%02d",
            local.tm_hour, local.tm_min, local.tm_sec];
}

static NSString *VCEventMessage(NSDictionary *event) {
    NSString *message = [event objectForKey:@"message"];
    if ([message isKindOfClass:[NSString class]] && [message length] > 0) {
        return VCSanitizeDiagnosticText(message, 192);
    }
    return VCSanitizeDiagnosticText([event objectForKey:@"action"], 96);
}

static NSString *VCEventMetadata(NSDictionary *event) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:VCEventTimeText(event)];
    NSString *source = [event objectForKey:@"source"];
    NSString *category = [event objectForKey:@"category"];
    if ([source isEqualToString:@"daemon"]) {
        [parts addObject:@"daemon"];
    } else if ([category length] > 0) {
        [parts addObject:category];
    } else if ([source length] > 0) {
        [parts addObject:source];
    }
    NSString *detail = VCSanitizeDiagnosticText([event objectForKey:@"detail"], 192);
    if ([detail length] > 0) [parts addObject:detail];
    return [parts componentsJoinedByString:@" · "];
}

static NSArray *VCCombinedDiagnosticEvents(NSArray *daemonEvents,
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

@implementation DiagnosticEventsVC

- (id)initWithEvents:(NSArray *)events {
    self = [super init];
    if (self) _events = [events copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"All Events";
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
                                                initWithTitle:@"Clear"
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(clearPressed)] autorelease];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    UIBarButtonItem *clearButton = self.navigationItem.rightBarButtonItem;
    clearButton.tintColor = VCErrorColor();
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 7) {
        clearButton.style = UIBarButtonItemStyleDone;
    } else {
        [clearButton setTitleTextAttributes:
            [NSDictionary dictionaryWithObject:VCErrorColor()
                                        forKey:NSForegroundColorAttributeName]
                                  forState:UIControlStateNormal];
    }
    clearButton.enabled = [_events count] > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return MAX((NSInteger)1, (NSInteger)[_events count]);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [NSString stringWithFormat:@"Activity (%u)", (unsigned)[_events count]];
}

- (void)clearPressed {
    if ([_events count] == 0) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Clear Activity?"
                                                     message:@"Are you sure you want to delete all recorded diagnostic activity?"
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Clear", nil] autorelease];
    [alert show];
#pragma clang diagnostic pop
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
#pragma clang diagnostic pop
    [[VCAppEventRecorder sharedRecorder] clearEvents];
    (void)SendCommand(@"CLEAR_EVENTS\n");
    [_events release];
    _events = [[NSArray alloc] init];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [_tableView reloadData];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kVCDiagnosticEventsClearedNotification
                      object:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DiagnosticEventListCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if ([_events count] == 0) {
        cell.textLabel.text = @"No events recorded";
        cell.detailTextLabel.text = @"Actions will appear here as they happen";
    } else {
        NSDictionary *event = [_events objectAtIndex:[_events count] - 1 - indexPath.row];
        cell.textLabel.text = VCEventMessage(event);
        cell.detailTextLabel.text = VCEventMetadata(event);
    }
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 62.0f;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate { return IsPadDevice(); }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    [_tableView release];
    [_events release];
    [super dealloc];
}

@end

static NSDictionary *VCParseDaemonDiagnostics(NSString *response) {
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

static NSArray *VCParseDaemonEvents(NSString *response) {
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

static NSString *VCMachineIdentifier(void) {
    struct utsname info;
    if (uname(&info) != 0 || info.machine[0] == '\0') return @"unknown";
    return [NSString stringWithUTF8String:info.machine];
}

static NSString *VCActiveNetworkDescription(void) {
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;

    SCNetworkReachabilityRef reachability =
        SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault,
                                                (const struct sockaddr *)&address);
    if (!reachability) return @"Unknown";

    SCNetworkReachabilityFlags flags = 0;
    BOOL valid = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!valid) return @"Unknown";

    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    if (!reachable || needsConnection) return @"No active route";
#if TARGET_OS_IPHONE
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        return @"pdp_ip (Cellular)";
    }
#endif
    return @"en0 (Wi-Fi)";
}

static NSString *VCNormalizedIPAddress(NSString *value) {
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

static NSString *VCExternalIPThroughSOCKS(uint16_t socksPort) {
    int fd = connect_loopback_port(socksPort, 8000);
    if (fd < 0) return nil;
    if (socks5_connect_domain(fd, "api.ipify.org", 80) != 0) {
        close(fd);
        return nil;
    }

    static const char request[] =
        "GET / HTTP/1.0\r\n"
        "Host: api.ipify.org\r\n"
        "User-Agent: vless-core-app-diagnostics\r\n"
        "Connection: close\r\n\r\n";
    if (write_all(fd, request, sizeof(request) - 1) != 0) {
        close(fd);
        return nil;
    }

    char response[8192];
    size_t used = 0;
    while (used + 1 < sizeof(response)) {
        ssize_t count = read(fd, response + used, sizeof(response) - used - 1);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        used += (size_t)count;
    }
    close(fd);
    response[used] = '\0';
    if (used < 12 || strncmp(response, "HTTP/", 5) != 0) return nil;

    char *status = strchr(response, ' ');
    if (!status || atoi(status + 1) < 200 || atoi(status + 1) >= 300) return nil;
    char *body = strstr(response, "\r\n\r\n");
    if (!body) return nil;
    body += 4;
    NSString *bodyText = [[[NSString alloc] initWithBytes:body
                                                   length:used - (size_t)(body - response)
                                                 encoding:NSUTF8StringEncoding] autorelease];
    return VCNormalizedIPAddress(bodyText);
}

static NSString *VCExternalIPThroughSystemHTTP(void) {
    BOOL usesATS = [[[UIDevice currentDevice] systemVersion] integerValue] >= 9;
    NSURL *url = [NSURL URLWithString:(usesATS
                                      ? @"https://api.ipify.org/"
                                      : @"http://api.ipify.org/")];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:10.0];
    [request setValue:@"vless-core-app-diagnostics" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSURLResponse *response = nil;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&error];
#pragma clang diagnostic pop
    if (!data || error) return nil;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status < 200 || status >= 300) return nil;
    }
    NSString *body = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return VCNormalizedIPAddress(body);
}

static BOOL VCSystemHTTPProbe(void) {
    BOOL usesATS = [[[UIDevice currentDevice] systemVersion] integerValue] >= 9;
    NSURL *url = [NSURL URLWithString:(usesATS
                                      ? @"https://www.gstatic.com/generate_204"
                                      : @"http://www.gstatic.com/generate_204")];
    if (!url) return NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:8.0];
    [request setValue:@"vless-core-app-diagnostics" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSURLResponse *response = nil;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    (void)[NSURLConnection sendSynchronousRequest:request
                                returningResponse:&response
                                            error:&error];
#pragma clang diagnostic pop
    if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) return NO;
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    return status >= 200 && status < 400;
}

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    int finished;
    int result;
    int waiter_timed_out;
} VCDNSCheckContext;

static void *VCDNSCheckWorker(void *opaque) {
    VCDNSCheckContext *context = (VCDNSCheckContext *)opaque;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *result = NULL;
    int rc = getaddrinfo("api.ipify.org", "80", &hints, &result);
    if (result) freeaddrinfo(result);

    pthread_mutex_lock(&context->mutex);
    context->result = rc == 0;
    context->finished = 1;
    int timedOut = context->waiter_timed_out;
    if (!timedOut) pthread_cond_signal(&context->condition);
    pthread_mutex_unlock(&context->mutex);

    if (timedOut) {
        pthread_cond_destroy(&context->condition);
        pthread_mutex_destroy(&context->mutex);
        free(context);
    }
    return NULL;
}

static BOOL VCDNSCheck(void) {
    VCDNSCheckContext *context = calloc(1, sizeof(*context));
    if (!context) return NO;
    if (pthread_mutex_init(&context->mutex, NULL) != 0) {
        free(context);
        return NO;
    }
    if (pthread_cond_init(&context->condition, NULL) != 0) {
        pthread_mutex_destroy(&context->mutex);
        free(context);
        return NO;
    }

    pthread_t thread;
    if (pthread_create(&thread, NULL, VCDNSCheckWorker, context) != 0) {
        pthread_cond_destroy(&context->condition);
        pthread_mutex_destroy(&context->mutex);
        free(context);
        return NO;
    }

    struct timeval now;
    gettimeofday(&now, NULL);
    struct timespec deadline;
    deadline.tv_sec = now.tv_sec + 8;
    deadline.tv_nsec = (long)now.tv_usec * 1000L;

    pthread_mutex_lock(&context->mutex);
    int waitRC = 0;
    while (!context->finished && waitRC == 0) {
        waitRC = pthread_cond_timedwait(&context->condition, &context->mutex, &deadline);
    }
    if (!context->finished) {
        context->waiter_timed_out = 1;
        pthread_mutex_unlock(&context->mutex);
        (void)pthread_detach(thread);
        return NO;
    }
    BOOL success = context->result != 0;
    pthread_mutex_unlock(&context->mutex);
    (void)pthread_join(thread, NULL);
    pthread_cond_destroy(&context->condition);
    pthread_mutex_destroy(&context->mutex);
    free(context);
    return success;
}

static NSDictionary *VCRunConnectionQualityChecks(NSDictionary *daemonState) {
    NSMutableDictionary *quality = [NSMutableDictionary dictionary];
    BOOL connected = [[daemonState objectForKey:@"connected"] boolValue];
    NSInteger socksPort = [[daemonState objectForKey:@"socks_port"] integerValue];
    if (!connected || socksPort <= 0 || socksPort > 65535) {
        [quality setObject:@"VPN disconnected" forKey:@"server"];
        [quality setObject:@"Not running" forKey:@"core"];
        [quality setObject:@"Not checked" forKey:@"dns"];
        [quality setObject:@"Not checked" forKey:@"http"];
        [quality setObject:@"Not checked" forKey:@"webkit"];
        [quality setObject:@"Not checked" forKey:@"leak"];
        [quality setObject:@"VPN disconnected" forKey:@"internet"];
        return quality;
    }

    BOOL helperRunning = [[daemonState objectForKey:@"core"] isEqualToString:@"running"];
    BOOL listenerReady = ConnectLatencyMs("127.0.0.1", (uint16_t)socksPort, 1500,
                                         NULL) == 0;
    [quality setObject:(helperRunning && listenerReady ? @"Running and listening" : @"Unavailable")
                 forKey:@"core"];

    BOOL dnsWorks = VCDNSCheck();
    [quality setObject:(dnsWorks ? @"Resolved successfully" : @"Resolution failed")
                 forKey:@"dns"];

    int proxyLatency = 0;
    BOOL proxyHTTP = helperRunning && listenerReady &&
        ProxyGetConnectOnceMs((uint16_t)socksPort, 8000, &proxyLatency) == 0;
    NSString *proxyIP = proxyHTTP ? VCExternalIPThroughSOCKS((uint16_t)socksPort) : nil;
    [quality setObject:(proxyHTTP ? @"Reachable through tunnel" : @"Tunnel request failed")
                 forKey:@"server"];
    [quality setObject:(proxyHTTP
                        ? [NSString stringWithFormat:@"Passed (%d ms)", proxyLatency]
                        : @"Failed")
                 forKey:@"http"];

    BOOL systemWorks = VCSystemHTTPProbe();
    NSString *systemIP = systemWorks ? VCExternalIPThroughSystemHTTP() : nil;
    BOOL exitsMatch = proxyIP && systemIP && [proxyIP isEqualToString:systemIP];
    if (exitsMatch) {
        [quality setObject:@"Routed through VPN" forKey:@"webkit"];
        [quality setObject:@"Not detected" forKey:@"leak"];
    } else if (proxyIP && systemIP) {
        [quality setObject:@"Different network exit" forKey:@"webkit"];
        [quality setObject:@"Detected" forKey:@"leak"];
    } else {
        [quality setObject:(systemWorks ? @"HTTP works; exit not verified" : @"Request failed")
                     forKey:@"webkit"];
        [quality setObject:@"Not checked" forKey:@"leak"];
    }

    if (dnsWorks && proxyHTTP && systemWorks && exitsMatch) {
        [quality setObject:@"Working through VPN" forKey:@"internet"];
    } else if (dnsWorks && proxyHTTP && systemWorks && proxyIP && systemIP) {
        [quality setObject:@"Working with a traffic leak" forKey:@"internet"];
    } else if (dnsWorks && proxyHTTP && systemWorks) {
        [quality setObject:@"Working; exit not verified" forKey:@"internet"];
    } else if (proxyHTTP || systemWorks) {
        [quality setObject:@"Partially working" forKey:@"internet"];
    } else {
        [quality setObject:@"Unavailable" forKey:@"internet"];
    }
    return quality;
}

static NSString *VCDiagnosticValue(NSDictionary *dictionary,
                                   NSString *key,
                                   NSString *fallback) {
    NSString *value = [dictionary objectForKey:key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : fallback;
}

@implementation DebugVC

- (void)stopRefreshTimer {
    [_refreshTimer invalidate];
    [_refreshTimer release];
    _refreshTimer = nil;
}

- (void)startRefreshTimer {
    if (_refreshTimer) return;
    [self refreshDiagnostics];
    _refreshTimer = [[NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(refreshDiagnostics)
                                                    userInfo:nil
                                                     repeats:YES] retain];
}

- (void)applicationEnteredBackground:(NSNotification *)notification {
    (void)notification;
    [self stopRefreshTimer];
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    if (self.view.window) [self startRefreshTimer];
}

- (NSArray *)combinedEvents {
    if (_displayEvents) return _displayEvents;
    _displayEvents = [VCCombinedDiagnosticEvents(_daemonEvents, _appEvents, _localEvents) copy];
    return _displayEvents;
}

- (void)diagnosticEventsCleared:(NSNotification *)notification {
    (void)notification;
    [_daemonEvents release];
    _daemonEvents = [[NSArray alloc] init];
    [_appEvents release];
    _appEvents = [[NSArray alloc] init];
    [_localEvents removeAllObjects];
    [_displayEvents release];
    _displayEvents = nil;
    [_tableView reloadData];
}

- (void)addLocalEvent:(NSString *)message {
    if (![message isKindOfClass:[NSString class]] || [message length] == 0) return;
    NSDictionary *last = [_localEvents lastObject];
    if ([[last objectForKey:@"message"] isEqualToString:message]) return;
    NSTimeInterval seconds = [[NSDate date] timeIntervalSince1970];
    [_localEvents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithLongLong:(long long)(seconds * 1000.0)], @"timestamp",
                             @"debug", @"source",
                             message, @"message",
                             nil]];
    if ([_localEvents count] > 32) [_localEvents removeObjectAtIndex:0];
    [_displayEvents release];
    _displayEvents = nil;
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _appActivitySwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Debug";
    _localEvents = [[NSMutableArray alloc] init];
    VCRecordAppEvent(@"ui", @"Debug screen opened", nil);
    _appEvents = [[[VCAppEventRecorder sharedRecorder] eventsSnapshot] copy];
    _appActivitySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_appActivitySwitch setOn:VCAppActivityLoggingEnabled() animated:NO];
    [_appActivitySwitch addTarget:self
                           action:@selector(appActivitySwitchChanged:)
                 forControlEvents:UIControlEventValueChanged];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationEnteredBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(diagnosticEventsCleared:)
                                                 name:kVCDiagnosticEventsClearedNotification
                                               object:nil];
    [self applyTheme];
}

- (void)appActivitySwitchChanged:(UISwitch *)sender {
    BOOL enabled = [sender isOn];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDefaultsDiagnosticAppActivityKey];
    [defaults synchronize];
    [[VCAppEventRecorder sharedRecorder] setAppActivityEnabled:enabled];
    VCRecordAppEvent(@"diagnostics", @"App activity logging changed",
                     enabled ? @"enabled=1" : @"enabled=0");
    [_appEvents release];
    _appEvents = [[[VCAppEventRecorder sharedRecorder] eventsSnapshot] copy];
    [_displayEvents release];
    _displayEvents = nil;
    [_tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startRefreshTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRefreshTimer];
}

- (void)refreshDiagnostics {
    if (_refreshing) return;
    _refreshing = YES;
    [NSThread detachNewThreadSelector:@selector(diagnosticsWorker) toTarget:self withObject:nil];
}

- (void)diagnosticsWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = VCParseDaemonDiagnostics(SendCommand(@"DIAGNOSTICS\n"));
    NSArray *events = VCParseDaemonEvents(SendCommand(@"EVENTS\n"));
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             state, @"state",
                             events, @"events",
                             nil];
    [self performSelectorOnMainThread:@selector(diagnosticsFinished:)
                           withObject:payload
                        waitUntilDone:NO];
    [pool drain];
}

- (void)diagnosticsFinished:(NSDictionary *)payload {
    _refreshing = NO;
    NSDictionary *newState = [payload objectForKey:@"state"];
    NSArray *newEvents = [payload objectForKey:@"events"];
    NSArray *newAppEvents = [[VCAppEventRecorder sharedRecorder] eventsSnapshot];
    BOOL hadDaemonState = _daemonState != nil;
    BOOL stateChanged = ![_daemonState isEqual:newState];
    BOOL eventsChanged = ![_daemonEvents isEqual:newEvents];
    BOOL appEventsChanged = ![_appEvents isEqual:newAppEvents];
    [_daemonState release];
    _daemonState = [newState copy];
    [_daemonEvents release];
    _daemonEvents = [newEvents copy];
    [_appEvents release];
    _appEvents = [newAppEvents copy];
    if (eventsChanged || appEventsChanged) {
        [_displayEvents release];
        _displayEvents = nil;
    }

    NSString *network = VCActiveNetworkDescription();
    BOOL networkChanged = !_lastNetwork || ![_lastNetwork isEqualToString:network];
    BOOL hadNetworkState = _lastNetwork != nil;
    if (networkChanged) {
        BOOL changedNetwork = _lastNetwork != nil;
        if (_lastNetwork && ![_lastNetwork isEqualToString:@"No active route"] &&
            ![_lastNetwork isEqualToString:@"Unknown"]) {
            NSString *oldName = [_lastNetwork rangeOfString:@"Cellular"].location != NSNotFound
                ? @"Cellular network"
                : @"Wi-Fi";
            [self addLocalEvent:[NSString stringWithFormat:@"%@ disconnected", oldName]];
        }
        if (![network isEqualToString:@"No active route"] && ![network isEqualToString:@"Unknown"]) {
            [self addLocalEvent:[NSString stringWithFormat:@"%@ active", network]];
        } else if ([network isEqualToString:@"No active route"]) {
            [self addLocalEvent:@"No active network route"];
        }
        [_lastNetwork release];
        _lastNetwork = [network copy];
        if (changedNetwork && [[_daemonState objectForKey:@"connected"] boolValue]) {
            if ([[_daemonState objectForKey:@"pf_routing"] isEqualToString:@"active"]) {
                [self addLocalEvent:@"PF routing verified after network change"];
            }
            if ([[_daemonState objectForKey:@"pac"] isEqualToString:@"active"]) {
                [self addLocalEvent:@"PAC verified after network change"];
            }
        }
    }

    if ((hadDaemonState && stateChanged) || (hadNetworkState && networkChanged)) {
        _qualityGeneration++;
        [_qualityState release];
        _qualityState = nil;
    }

    if (stateChanged || eventsChanged || appEventsChanged || networkChanged) [_tableView reloadData];
    if (!_qualityState && !_checking && [[_daemonState objectForKey:@"connected"] boolValue]) {
        [self runQualityCheck];
    }
}

- (void)runQualityCheck {
    if (_checking || _reporting) return;
    if (!_daemonState || [_daemonState objectForKey:@"error"] ||
        ![[_daemonState objectForKey:@"connected"] boolValue]) {
        BOOL loading = _daemonState == nil;
        BOOL unavailable = [_daemonState objectForKey:@"error"] != nil;
        VCRecordAppEvent(@"diagnostics", @"Connection check blocked",
                         loading ? @"reason=status_loading" :
                         (unavailable ? @"reason=daemon_unavailable" : @"reason=vpn_disconnected"));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc]
                               initWithTitle:(loading ? @"Please Wait" :
                                              (unavailable ? @"Status Unavailable" : @"VPN Is Disconnected"))
                               message:(loading
                                        ? @"Connection status is still loading. Try again in a moment."
                                        : (unavailable
                                           ? @"The VPN daemon status could not be read."
                                           : @"Connect to a configuration before running the connection check."))
                               delegate:nil
                               cancelButtonTitle:@"OK"
                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
        return;
    }
    VCRecordAppEvent(@"diagnostics", @"Connection check started", nil);
    _checking = YES;
    [_tableView reloadData];
    NSDictionary *input = [NSDictionary dictionaryWithObjectsAndKeys:
                           (_daemonState ? _daemonState : [NSDictionary dictionary]), @"state",
                           [NSNumber numberWithUnsignedInteger:_qualityGeneration], @"generation",
                           nil];
    [NSThread detachNewThreadSelector:@selector(qualityWorker:) toTarget:self withObject:input];
}

- (void)qualityWorker:(NSDictionary *)input {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = [input objectForKey:@"state"];
    NSDictionary *quality = VCRunConnectionQualityChecks(state);
    NSDictionary *output = [NSDictionary dictionaryWithObjectsAndKeys:
                            quality, @"quality",
                            [input objectForKey:@"generation"], @"generation",
                            nil];
    [self performSelectorOnMainThread:@selector(qualityFinished:)
                           withObject:output
                        waitUntilDone:NO];
    [pool drain];
}

- (void)qualityFinished:(NSDictionary *)output {
    _checking = NO;
    if ([[output objectForKey:@"generation"] unsignedIntegerValue] != _qualityGeneration) {
        if ([[_daemonState objectForKey:@"connected"] boolValue]) {
            [self runQualityCheck];
        } else {
            [_tableView reloadData];
        }
        return;
    }
    NSDictionary *quality = [output objectForKey:@"quality"];
    [_qualityState release];
    _qualityState = [quality copy];
    NSString *leak = [_qualityState objectForKey:@"leak"];
    if ([leak isEqualToString:@"Detected"]) {
        [self addLocalEvent:@"Traffic leak detected: system and tunnel exits differ"];
    } else if ([leak isEqualToString:@"Not detected"]) {
        [self addLocalEvent:@"External IP confirmed through VPN"];
    } else if ([[[_qualityState objectForKey:@"internet"] lowercaseString] hasPrefix:@"working"]) {
        [self addLocalEvent:@"Connection works; external IP comparison unavailable"];
    } else {
        [self addLocalEvent:@"Connection quality check could not be completed"];
    }
    VCRecordAppEvent(@"diagnostics", @"Connection check finished",
                     [NSString stringWithFormat:@"core=%@ dns=%@ proxy=%@ webkit=%@ leak=%@ internet=%@",
                      VCDiagnosticValue(_qualityState, @"core", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"dns", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"http", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"webkit", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"leak", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"internet", @"unknown")]);
    [_tableView reloadData];
}

- (NSString *)buildReportWithState:(NSDictionary *)state
                            quality:(NSDictionary *)quality
                             events:(NSArray *)events {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss ZZZZ";
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"vless-core diagnostic report\n"];
    [report appendFormat:@"Generated: %@\n\n", [formatter stringFromDate:[NSDate date]]];
    [report appendString:@"Privacy: configuration URIs, subscription URLs, server addresses, external IP addresses, UUIDs, credentials and keys are omitted.\n\n"];
    [report appendString:@"Application\n-----------\n"];
    [report appendFormat:@"Version: %@ (%@)\n", AppShortVersion(), AppBuildVersion()];
    [report appendFormat:@"Device: %@ (%@)\n", DeviceModelName(), VCMachineIdentifier()];
    [report appendFormat:@"iOS: %@\n", [[UIDevice currentDevice] systemVersion]];
#if defined(__LP64__)
    [report appendString:@"Application architecture: arm64\n"];
#else
    [report appendString:@"Application architecture: armv7\n"];
#endif
    [report appendFormat:@"App activity logging: %@\n",
     VCAppActivityLoggingEnabled() ? @"enabled" : @"disabled"];
    [report appendFormat:@"Daemon architecture: %@\n", VCDiagnosticValue(state, @"architecture", @"unknown")];
    [report appendFormat:@"Active network: %@\n\n", VCActiveNetworkDescription()];

    [report appendString:@"Routing and helpers\n-------------------\n"];
    [report appendFormat:@"Connection: %@\n", [[state objectForKey:@"connected"] boolValue] ? @"connected" : @"disconnected"];
    [report appendFormat:@"Mode: %@\n", VCDiagnosticValue(state, @"mode", @"unknown")];
    [report appendFormat:@"PF engine: %@\n", VCDiagnosticValue(state, @"pf", @"unknown")];
    [report appendFormat:@"PF routing: %@\n", VCDiagnosticValue(state, @"pf_routing", @"unknown")];
    [report appendFormat:@"PAC: %@\n", VCDiagnosticValue(state, @"pac", @"unknown")];
    [report appendFormat:@"Core helper: %@\n", VCDiagnosticValue(state, @"core", @"unknown")];
    [report appendFormat:@"Traffic redirector: %@\n", VCDiagnosticValue(state, @"redsocks", @"unknown")];
    [report appendFormat:@"DNS helper: %@\n\n", VCDiagnosticValue(state, @"dns", @"unknown")];

    [report appendString:@"Connection quality\n------------------\n"];
    NSArray *qualityRows = [NSArray arrayWithObjects:
                            [NSArray arrayWithObjects:@"Server path", @"server", nil],
                            [NSArray arrayWithObjects:@"Core", @"core", nil],
                            [NSArray arrayWithObjects:@"DNS", @"dns", nil],
                            [NSArray arrayWithObjects:@"HTTP through proxy", @"http", nil],
                            [NSArray arrayWithObjects:@"Safari/WebKit path", @"webkit", nil],
                            [NSArray arrayWithObjects:@"Traffic leak", @"leak", nil],
                            [NSArray arrayWithObjects:@"Internet", @"internet", nil],
                            nil];
    for (NSArray *row in qualityRows) {
        [report appendFormat:@"%@: %@\n",
         [row objectAtIndex:0],
         VCDiagnosticValue(quality, [row objectAtIndex:1], @"not checked")];
    }

    [report appendString:@"\nPrivacy-safe activity history\n-----------------------------\n"];
    if ([events count] == 0) {
        [report appendString:@"No events recorded.\n"];
    } else {
        for (NSDictionary *event in events) {
            [report appendFormat:@"%@ — %@\n",
             VCEventMetadata(event),
             VCEventMessage(event)];
        }
    }
    return report;
}

- (void)createReport {
    if (_reporting || _checking) return;
    VCRecordAppEvent(@"diagnostics", @"Diagnostic report requested", nil);
    _reporting = YES;
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:VCDebugSectionDiagnostics]
              withRowAnimation:UITableViewRowAnimationNone];
    [NSThread detachNewThreadSelector:@selector(reportWorker) toTarget:self withObject:nil];
}

- (void)reportWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = VCParseDaemonDiagnostics(SendCommand(@"DIAGNOSTICS\n"));
    NSArray *events = VCParseDaemonEvents(SendCommand(@"EVENTS\n"));
    NSDictionary *quality = VCRunConnectionQualityChecks(state);
    NSArray *appEvents = [[VCAppEventRecorder sharedRecorder] eventsSnapshot];
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             state, @"state",
                             events, @"events",
                             quality, @"quality",
                             appEvents, @"app_events",
                             nil];
    [self performSelectorOnMainThread:@selector(reportFinished:)
                           withObject:payload
                        waitUntilDone:NO];
    [pool drain];
}

- (void)reportFinished:(NSDictionary *)payload {
    _reporting = NO;
    NSDictionary *reportState = [payload objectForKey:@"state"];
    NSDictionary *reportQuality = [payload objectForKey:@"quality"];
    NSArray *events = VCCombinedDiagnosticEvents([payload objectForKey:@"events"],
                                                  [payload objectForKey:@"app_events"],
                                                  _localEvents);
    NSString *report = [self buildReportWithState:reportState
                                          quality:reportQuality
                                           events:events];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      @"vless-core-diagnostics.txt"];
    NSError *error = nil;
    BOOL written = [report writeToFile:path
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:&error];
    if (!written) {
        VCRecordAppEvent(@"diagnostics", @"Diagnostic report failed", @"stage=file_write");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Report Failed"
                                                         message:(error ? [error localizedDescription] : @"Unable to write the report.")
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
        [_tableView reloadData];
        return;
    }
    (void)chmod([path fileSystemRepresentation], 0600);
    VCRecordAppEvent(@"diagnostics", @"Diagnostic report created",
                     [NSString stringWithFormat:@"events=%lu bytes=%lu",
                      (unsigned long)[events count],
                      (unsigned long)[report lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]);

    [_documentController release];
    _documentController = [[UIDocumentInteractionController interactionControllerWithURL:
                            [NSURL fileURLWithPath:path]] retain];
    _documentController.delegate = self;
    _documentController.name = @"vless-core diagnostics";
    CGRect anchor = CGRectMake(CGRectGetMidX(self.view.bounds),
                               CGRectGetMidY(self.view.bounds),
                               1.0f,
                               1.0f);
    if (![_documentController presentOptionsMenuFromRect:anchor
                                                  inView:self.view
                                                animated:YES]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Report Ready"
                                                         message:path
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
    }
    [_tableView reloadData];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    (void)controller;
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return VCDebugSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionLiveState) return 6;
    if (section == VCDebugSectionConnectionQuality) return 7;
    if (section == VCDebugSectionActivityLogging) return 1;
    if (section == VCDebugSectionRecentActivity) {
        NSInteger count = (NSInteger)[[self combinedEvents] count];
        return count == 0 ? 1 : MIN((NSInteger)5, count) + 1;
    }
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionLiveState) return @"Live state";
    if (section == VCDebugSectionConnectionQuality) return @"Connection quality";
    if (section == VCDebugSectionActivityLogging) return @"Activity logging";
    if (section == VCDebugSectionRecentActivity) return @"Recent activity";
    return @"Diagnostics";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionActivityLogging) {
        return @"Off by default. Connection, network diagnostics, ping and subscription update events are always recorded.";
    }
    if (section == VCDebugSectionRecentActivity) {
        return @"Up to 250 recent events are kept only on this device. URLs, IP addresses, UUIDs, names and secrets are omitted. Nothing is sent automatically.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionActivityLogging) return 64.0f;
    if (section == VCDebugSectionRecentActivity) return 82.0f;
    return 18.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != VCDebugSectionActivityLogging &&
        section != VCDebugSectionRecentActivity) return nil;
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    UIView *footer = [[[UIView alloc] initWithFrame:
                       CGRectMake(0.0f, 0.0f, tableView.bounds.size.width, height)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(18.0f, 3.0f, tableView.bounds.size.width - 36.0f, height - 6.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:13.0f];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.text = [self tableView:tableView titleForFooterInSection:section];
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (NSString *)qualityValueForRow:(NSInteger)row {
    if (_checking) return @"Checking...";
    NSArray *keys = [NSArray arrayWithObjects:@"server", @"core", @"dns", @"http", @"webkit", @"leak", @"internet", nil];
    return VCDiagnosticValue(_qualityState, [keys objectAtIndex:row], @"Not checked");
}

- (UIColor *)colorForStatus:(NSString *)status {
    NSString *lower = [status lowercaseString];
    if ([lower rangeOfString:@"leak"].location != NSNotFound &&
        [lower rangeOfString:@"not detected"].location == NSNotFound) {
        return VCErrorColor();
    }
    if ([lower hasPrefix:@"not detected"] ||
        [lower hasPrefix:@"active"] ||
        [lower hasPrefix:@"enabled"] ||
        [lower hasPrefix:@"connected"] ||
        [lower hasPrefix:@"running"] ||
        [lower hasPrefix:@"reachable"] ||
        [lower hasPrefix:@"resolved"] ||
        [lower hasPrefix:@"passed"] ||
        [lower hasPrefix:@"routed"] ||
        [lower hasPrefix:@"working"]) {
        return VCSuccessColor();
    }
    if ([lower hasPrefix:@"error"] ||
        [lower hasPrefix:@"missing"] ||
        [lower hasPrefix:@"unavailable"] ||
        [lower hasPrefix:@"failed"] ||
        [lower hasPrefix:@"tunnel request failed"] ||
        [lower hasPrefix:@"resolution failed"] ||
        [lower hasPrefix:@"different"] ||
        [lower isEqualToString:@"detected"]) {
        return VCErrorColor();
    }
    return VCSecondaryTextColor();
}

- (UITableViewCell *)statusCellInTable:(UITableView *)tableView
                                 title:(NSString *)title
                                detail:(NSString *)detail {
    static NSString *identifier = @"DebugStatusCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = [self colorForStatus:detail];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == VCDebugSectionLiveState) {
        NSString *title = nil;
        NSString *detail = nil;
        NSString *error = [_daemonState objectForKey:@"error"];
        if (indexPath.row == 0) {
            title = @"Daemon control";
            detail = !_daemonState ? @"Loading..." : (error ? error : @"Online");
        } else if (indexPath.row == 1) {
            title = @"VPN connection";
            detail = error ? @"Unavailable" : ([[_daemonState objectForKey:@"connected"] boolValue] ? @"Connected" : @"Disconnected");
        } else if (indexPath.row == 2) {
            title = @"Active network";
            detail = _lastNetwork ? _lastNetwork : VCActiveNetworkDescription();
        } else if (indexPath.row == 3) {
            title = @"PF routing";
            detail = error ? @"Unavailable" : [NSString stringWithFormat:@"%@ (engine: %@)",
                                                VCDiagnosticValue(_daemonState, @"pf_routing", @"unknown"),
                                                VCDiagnosticValue(_daemonState, @"pf", @"unknown")];
        } else if (indexPath.row == 4) {
            title = @"PAC for Safari/WebKit";
            NSString *pac = VCDiagnosticValue(_daemonState, @"pac", @"unknown");
            detail = error ? @"Unavailable" : ([pac isEqualToString:@"not_required"] ? @"Not required on armv7" : [pac capitalizedString]);
        } else {
            title = @"Helper processes";
            if (error) {
                detail = @"Unavailable";
            } else {
                NSString *core = VCDiagnosticValue(_daemonState, @"core", @"unknown");
                NSString *redirector = VCDiagnosticValue(_daemonState, @"redsocks", @"unknown");
                NSString *dns = VCDiagnosticValue(_daemonState, @"dns", @"unknown");
                detail = [core isEqualToString:@"running"] &&
                         [redirector isEqualToString:@"running"] &&
                         [dns isEqualToString:@"running"]
                    ? @"All running"
                    : [NSString stringWithFormat:@"core %@ · redirector %@ · DNS %@",
                       core, redirector, dns];
            }
        }
        return [self statusCellInTable:tableView title:title detail:detail];
    }

    if (indexPath.section == VCDebugSectionConnectionQuality) {
        NSArray *titles = [NSArray arrayWithObjects:
                           @"Server path", @"Core listener", @"DNS", @"HTTP through proxy",
                           @"Safari/WebKit path", @"Traffic leak", @"Internet", nil];
        return [self statusCellInTable:tableView
                                 title:[titles objectAtIndex:indexPath.row]
                                detail:[self qualityValueForRow:indexPath.row]];
    }

    if (indexPath.section == VCDebugSectionActivityLogging) {
        static NSString *identifier = @"DebugAppActivityCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:identifier] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = _appActivitySwitch;
        cell.textLabel.text = @"Record app activity";
        cell.detailTextLabel.text = @"UI, imports, settings and storage";
        VCAppearanceApplyCell(cell);
        cell.textLabel.textColor = VCPrimaryTextColor();
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSArray *events = [self combinedEvents];
        NSInteger recentCount = MIN((NSInteger)5, (NSInteger)[events count]);
        BOOL viewAllRow = [events count] > 0 && indexPath.row == recentCount;
        static NSString *identifier = @"DebugEventCell";
        static NSString *viewAllIdentifier = @"DebugViewAllEventsCell";
        NSString *reuseIdentifier = viewAllRow ? viewAllIdentifier : identifier;
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:reuseIdentifier] autorelease];
        }
        if (viewAllRow) {
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"View all events";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%u recorded", (unsigned)[events count]];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = VCCreateDisclosureAccessoryView();
            cell.textLabel.numberOfLines = 1;
            cell.detailTextLabel.numberOfLines = 1;
        } else if ([events count] == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = nil;
            cell.textLabel.text = @"No events recorded";
            cell.detailTextLabel.text = @"Privacy-safe user and system actions will appear here";
            cell.textLabel.numberOfLines = 2;
            cell.detailTextLabel.numberOfLines = 2;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = nil;
            NSDictionary *event = [events objectAtIndex:[events count] - 1 - indexPath.row];
            cell.textLabel.text = VCEventMessage(event);
            cell.detailTextLabel.text = VCEventMetadata(event);
            cell.textLabel.numberOfLines = 2;
            cell.detailTextLabel.numberOfLines = 2;
        }
        VCAppearanceApplyCell(cell);
        cell.textLabel.textColor = VCPrimaryTextColor();
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    static NSString *identifier = @"DebugActionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    BOOL operationInProgress = _checking || _reporting;
    BOOL currentOperation = indexPath.row == 0 ? _checking : _reporting;
    cell.selectionStyle = operationInProgress
        ? UITableViewCellSelectionStyleNone
        : UITableViewCellSelectionStyleBlue;
    cell.textLabel.text = indexPath.row == 0 ? @"Run connection check" : @"Create diagnostic report";
    cell.detailTextLabel.text = indexPath.row == 0
        ? @"Test DNS, proxy HTTP and the Safari/WebKit path"
        : @"Export one privacy-safe text file";
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (currentOperation) {
        UIActivityIndicatorViewStyle style = VCAppearanceIsDark()
            ? UIActivityIndicatorViewStyleWhite
            : UIActivityIndicatorViewStyleGray;
        UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc]
                                             initWithActivityIndicatorStyle:style] autorelease];
        [spinner startAnimating];
        cell.accessoryView = spinner;
    } else if (operationInProgress) {
        cell.accessoryView = nil;
    } else {
        cell.accessoryView = VCCreateDisclosureAccessoryView();
    }
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSArray *events = [self combinedEvents];
        NSInteger recentCount = MIN((NSInteger)5, (NSInteger)[events count]);
        if ([events count] > 0 && indexPath.row == recentCount) {
            VCRecordAppEvent(@"ui", @"Full diagnostic event history opened", nil);
            DiagnosticEventsVC *controller = [[[DiagnosticEventsVC alloc] initWithEvents:events] autorelease];
            [self.navigationController pushViewController:controller animated:YES];
        }
        return;
    }
    if (indexPath.section != VCDebugSectionDiagnostics) return;
    if (indexPath.row == 0) [self runQualityCheck];
    else [self createReport];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSInteger eventCount = (NSInteger)[[self combinedEvents] count];
        NSInteger recentCount = MIN((NSInteger)5, eventCount);
        BOOL viewAllRow = eventCount > 0 && indexPath.row == recentCount;
        return viewAllRow ? 48.0f : 62.0f;
    }
    return 48.0f;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    if (indexPath.section == VCDebugSectionLiveState ||
        indexPath.section == VCDebugSectionConnectionQuality) {
        cell.detailTextLabel.textColor = [self colorForStatus:cell.detailTextLabel.text];
    } else {
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
    }
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopRefreshTimer];
    _documentController.delegate = nil;
    [_documentController release];
    [_appActivitySwitch release];
    [_tableView release];
    [_daemonState release];
    [_daemonEvents release];
    [_appEvents release];
    [_localEvents release];
    [_displayEvents release];
    [_qualityState release];
    [_lastNetwork release];
    [super dealloc];
}

@end

@implementation SettingsVC
@synthesize autoUpdate = _autoUpdate;
@synthesize preserveCustomNames = _preserveCustomNames;
@synthesize stealthMode = _stealthMode;
@synthesize darkTheme = _darkTheme;
@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize delegate = _delegate;

- (void)closePressed {
    VCRecordAppEvent(@"ui", @"Settings closed", nil);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)autoUpdateSwitchChanged:(UISwitch *)sw {
    _autoUpdate = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeAutoUpdate:)]) {
        [_delegate settingsVC:self didChangeAutoUpdate:_autoUpdate];
    }
}

- (void)preserveCustomNamesSwitchChanged:(UISwitch *)sw {
    _preserveCustomNames = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangePreserveCustomSubscriptionNames:)]) {
        [_delegate settingsVC:self didChangePreserveCustomSubscriptionNames:_preserveCustomNames];
    }
}

- (void)stealthSwitchChanged:(UISwitch *)sw {
    _stealthMode = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeStealthMode:)]) {
        [_delegate settingsVC:self didChangeStealthMode:_stealthMode];
    }
}

- (void)automaticUpdateChecksSwitchChanged:(UISwitch *)sw {
    _automaticUpdateChecks = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeAutomaticUpdateChecks:)]) {
        [_delegate settingsVC:self didChangeAutomaticUpdateChecks:_automaticUpdateChecks];
    }
}

- (void)preferGitHubLegacySwitchChanged:(UISwitch *)sw {
    BOOL enabled = [sw isOn];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDefaultsPreferGitHubLegacyKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"GitHub Legacy priority changed",
                     enabled ? @"enabled=1" : @"enabled=0");
}

- (NSString *)updateCheckDetailText {
    if (_updateChecker) return @"Checking GitHub Releases...";

    NSString *latest = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsLatestVersionKey];
    if ([latest isKindOfClass:[NSString class]] &&
        VCCompareVersions(AppShortVersion(), latest) == NSOrderedAscending) {
        return [NSString stringWithFormat:@"%@ is available", latest];
    }
    return [NSString stringWithFormat:@"Installed version %@", AppShortVersion()];
}

- (NSString *)displaySubscriptionHWID {
    NSString *hwid = SubscriptionHWID();
    NSRange separator = [hwid rangeOfString:@"-" options:NSBackwardsSearch];
    if (separator.location == NSNotFound) {
        return ([hwid length] > 12) ? [hwid substringFromIndex:([hwid length] - 12)] : hwid;
    }
    if (NSMaxRange(separator) >= [hwid length]) return hwid;
    return [hwid substringFromIndex:NSMaxRange(separator)];
}

- (void)copySubscriptionHWID {
    [[UIPasteboard generalPasteboard] setString:SubscriptionHWID()];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"HWID copied"
                                                     message:nil
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil] autorelease];
    [alert show];
}

- (UIView *)settingsFooterForWidth:(CGFloat)width {
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, width, 64.0f)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *hwidButton = [UIButton buttonWithType:UIButtonTypeCustom];
    hwidButton.frame = CGRectMake(16.0f, 6.0f, width - 32.0f, 48.0f);
    hwidButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hwidButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    hwidButton.titleLabel.numberOfLines = 2;
    hwidButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [hwidButton setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
    [hwidButton setTitle:[NSString stringWithFormat:@"HWID:\n%@", [self displaySubscriptionHWID]]
                 forState:UIControlStateNormal];
    hwidButton.accessibilityLabel = [NSString stringWithFormat:@"Subscription HWID: %@", SubscriptionHWID()];
    hwidButton.accessibilityHint = @"Copies the full HWID";
    [hwidButton addTarget:self action:@selector(copySubscriptionHWID) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:hwidButton];

    return footer;
}

- (void)updateSettingsFooterForWidth:(CGFloat)width {
    if (width <= 0.0f) return;
    _footerWidth = width;
    _tableView.tableFooterView = [self settingsFooterForWidth:width];
}

- (void)startManualUpdateCheck {
    if (_updateChecker) return;

    _updateChecker = [[VCUpdateChecker alloc] initWithDelegate:self];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:3];
    [_tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                      withRowAnimation:UITableViewRowAnimationNone];
    [_updateChecker start];
}

- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result {
    if (checker != _updateChecker) return;

    checker.delegate = nil;
    [_updateChecker release];
    _updateChecker = nil;

    NSString *status = [result objectForKey:@"status"];
    if (VCUpdateResultIsSuccessful(result)) {
        VCCacheSuccessfulUpdateResult(result);
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:3];
    [_tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                      withRowAnimation:UITableViewRowAnimationNone];

    if ([status isEqualToString:@"update"]) {
        [_availableReleaseURL release];
        _availableReleaseURL = [[result objectForKey:@"release_url"] copy];
        VCShowUpdateAvailableAlert(result, self, kVCSettingsUpdateAlertTag);
    } else if ([status isEqualToString:@"current"]) {
        NSString *message = [NSString stringWithFormat:@"Version %@ is the latest release.", AppShortVersion()];
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Up to Date"
                                                         message:message
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
    } else {
        NSString *error = [result objectForKey:@"error"];
        if (![error isKindOfClass:[NSString class]] || [error length] == 0) {
            error = @"Unable to check for updates.";
        }
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Update Check Failed"
                                                         message:error
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
    }
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _autoUpdateSwitch.onTintColor = VCAccentColor();
    _preserveCustomNamesSwitch.onTintColor = VCAccentColor();
    _stealthSwitch.onTintColor = VCAccentColor();
    _automaticUpdateChecksSwitch.onTintColor = VCAccentColor();
    _preferGitHubLegacySwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    [self updateSettingsFooterForWidth:_tableView.bounds.size.width];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VCBackgroundColor();
    self.title = @"Settings";

    UIBarButtonItem *close = [[[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                style:UIBarButtonItemStyleBordered
                                                               target:self
                                                               action:@selector(closePressed)] autorelease];
    self.navigationItem.leftBarButtonItem = close;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    _autoUpdateSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
    [_autoUpdateSwitch addTarget:self action:@selector(autoUpdateSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _preserveCustomNamesSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_preserveCustomNamesSwitch setOn:_preserveCustomNames animated:NO];
    [_preserveCustomNamesSwitch addTarget:self
                                   action:@selector(preserveCustomNamesSwitchChanged:)
                         forControlEvents:UIControlEventValueChanged];

    _stealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_stealthSwitch setOn:_stealthMode animated:NO];
    [_stealthSwitch addTarget:self action:@selector(stealthSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _automaticUpdateChecksSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_automaticUpdateChecksSwitch setOn:_automaticUpdateChecks animated:NO];
    [_automaticUpdateChecksSwitch addTarget:self
                                     action:@selector(automaticUpdateChecksSwitchChanged:)
                           forControlEvents:UIControlEventValueChanged];

    _preferGitHubLegacySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_preferGitHubLegacySwitch setOn:VCPreferGitHubLegacy() animated:NO];
    [_preferGitHubLegacySwitch addTarget:self
                                  action:@selector(preferGitHubLegacySwitchChanged:)
                        forControlEvents:UIControlEventValueChanged];

    [self applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = _tableView.bounds.size.width;
    if (fabs(_footerWidth - width) > 0.5f) {
        [self updateSettingsFooterForWidth:width];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_tableView reloadData];
    [_tableView layoutIfNeeded];

    for (NSIndexPath *indexPath in [_tableView indexPathsForVisibleRows]) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        [self applySettingsMarqueesToCell:cell
                                    title:[self settingsTitleTextForIndexPath:indexPath]
                                   detail:[self settingsDetailTextForIndexPath:indexPath]];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 7;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 3;
    if (section == 1) return 3;
    if (section == 2 || section == 3) return 2;
    if (section == 4 || section == 5) return 1;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Subscriptions";
    if (section == 1) return @"Network";
    if (section == 2) return @"Appearance";
    if (section == 3) return @"Updates";
    if (section == 4) return @"Debug";
    if (section == 5) return @"Advanced";
    return @"About";
}

- (VCMarqueeLabel *)settingsMarqueeForCell:(UITableViewCell *)cell
                                        tag:(NSInteger)tag
                              createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[cell.contentView viewWithTag:tag];
    if (!marquee && createIfNeeded) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = tag;
        marquee.userInteractionEnabled = NO;
        marquee.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:marquee];
    }
    return marquee;
}

- (void)applySettingsMarqueesToCell:(UITableViewCell *)cell
                               title:(NSString *)title
                              detail:(NSString *)detail {
    if (!cell) return;
    NSString *titleText = ([title isKindOfClass:[NSString class]] ? title : @"");
    NSString *detailText = ([detail isKindOfClass:[NSString class]] ? detail : @"");
    UIColor *titleColor = VCPrimaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();

    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = titleColor;
    cell.detailTextLabel.textColor = detailColor;
    cell.textLabel.text = titleText;
    cell.detailTextLabel.text = detailText;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    VCMarqueeLabel *titleMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsTitleMarqueeTag createIfNeeded:YES];
    if ([titleText length] > 0) {
        titleMarquee.hidden = NO;
        titleMarquee.frame = cell.textLabel.frame;
        titleMarquee.font = cell.textLabel.font;
        titleMarquee.textColor = titleColor;
        titleMarquee.text = titleText;
        cell.textLabel.textColor = [UIColor clearColor];
    } else {
        [titleMarquee stopMarquee];
        titleMarquee.text = @"";
        titleMarquee.hidden = YES;
    }

    VCMarqueeLabel *detailMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsDetailMarqueeTag createIfNeeded:YES];
    if ([detailText length] > 0) {
        detailMarquee.hidden = NO;
        detailMarquee.frame = cell.detailTextLabel.frame;
        detailMarquee.font = cell.detailTextLabel.font;
        detailMarquee.textColor = detailColor;
        detailMarquee.text = detailText;
        cell.detailTextLabel.textColor = [UIColor clearColor];
    } else {
        [detailMarquee stopMarquee];
        detailMarquee.text = @"";
        detailMarquee.hidden = YES;
    }
}

- (NSString *)settingsTitleTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Auto-update subscriptions";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Preserve custom names";
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        return @"Stealth mode";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Routing";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Ping type";
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return @"Xray version spoof";
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"Light";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Dark";
    }
    if (indexPath.section == 3 && indexPath.row == 0) {
        return @"Automatic checks";
    }
    if (indexPath.section == 3 && indexPath.row == 1) {
        return @"Check for Updates";
    }
    if (indexPath.section == 4 && indexPath.row == 0) {
        return @"Debug and diagnostics";
    }
    if (indexPath.section == 5 && indexPath.row == 0) {
        return @"Prefer GitHub Legacy";
    }
    if (indexPath.section == 6 && indexPath.row == 0) {
        return @"About vless-core";
    }
    if (indexPath.section == 6 && indexPath.row == 1) {
        return @"Credits";
    }
    if (indexPath.section == 6 && indexPath.row == 2) {
        return @"FAQ";
    }
    if (indexPath.section == 6 && indexPath.row == 3) {
        return @"Project on GitHub";
    }
    return @"";
}

- (NSString *)settingsDetailTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Refresh subscriptions on app open";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Keep renamed subscriptions after updates";
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        return @"Hide links in configs and subscriptions";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Proxy, Direct and Block rules";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return VCSelectedPingTypeText();
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return VCSelectedXrayVersionText();
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"Use the light color scheme";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Use the dark color scheme";
    }
    if (indexPath.section == 3 && indexPath.row == 0) {
        return @"Check for new releases once a day";
    }
    if (indexPath.section == 3 && indexPath.row == 1) {
        return [self updateCheckDetailText];
    }
    if (indexPath.section == 4 && indexPath.row == 0) {
        return @"Live state, connection tests, events and reports";
    }
    if (indexPath.section == 5 && indexPath.row == 0) {
        return @"Open GitHub links in the app before the browser";
    }
    if (indexPath.section == 6 && indexPath.row == 0) {
        return @"Version and core binary info";
    }
    if (indexPath.section == 6 && indexPath.row == 1) {
        return @"Dependencies, licenses and special thanks";
    }
    if (indexPath.section == 6 && indexPath.row == 2) {
        return @"Common questions and quick answers";
    }
    if (indexPath.section == 6 && indexPath.row == 3) {
        return @"github.com/notfence/vless-core-app";
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        static NSString *kSwitchCellId = @"SettingsSwitchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSwitchCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
        cell.accessoryView = _autoUpdateSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Auto-update subscriptions"
                                   detail:@"Refresh subscriptions on app open"];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 1) {
        static NSString *kPreserveCustomNamesCellId = @"SettingsPreserveCustomNamesCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPreserveCustomNamesCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kPreserveCustomNamesCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_preserveCustomNamesSwitch setOn:_preserveCustomNames animated:NO];
        cell.accessoryView = _preserveCustomNamesSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Preserve custom names"
                                   detail:@"Keep renamed subscriptions after updates"];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 2) {
        static NSString *kStealthCellId = @"SettingsStealthCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kStealthCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kStealthCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_stealthSwitch setOn:_stealthMode animated:NO];
        cell.accessoryView = _stealthSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Stealth mode"
                                   detail:@"Hide links in configs and subscriptions"];
        return cell;
    }

    if (indexPath.section == 1) {
        static NSString *kNetworkCellId = @"SettingsNetworkCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kNetworkCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kNetworkCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        NSString *title = @"Xray version spoof";
        NSString *detail = VCSelectedXrayVersionText();
        if (indexPath.row == 0) {
            title = @"Routing";
            detail = @"Proxy, Direct and Block rules";
        } else if (indexPath.row == 1) {
            title = @"Ping type";
            detail = VCSelectedPingTypeText();
        }
        [self applySettingsMarqueesToCell:cell
                                    title:title
                                   detail:detail];
        return cell;
    }

    if (indexPath.section == 2) {
        static NSString *kThemeCellId = @"SettingsThemeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kThemeCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kThemeCellId] autorelease];
        }
        BOOL darkRow = (indexPath.row == 1);
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryView = nil;
        cell.accessoryType = (_darkTheme == darkRow) ? UITableViewCellAccessoryCheckmark
                                                     : UITableViewCellAccessoryNone;
        [self applySettingsMarqueesToCell:cell
                                    title:(darkRow ? @"Dark" : @"Light")
                                   detail:(darkRow ? @"Use the dark color scheme" : @"Use the light color scheme")];
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 0) {
        static NSString *kAutomaticChecksCellId = @"SettingsAutomaticChecksCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAutomaticChecksCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kAutomaticChecksCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_automaticUpdateChecksSwitch setOn:_automaticUpdateChecks animated:NO];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = _automaticUpdateChecksSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Automatic checks"
                                   detail:@"Check for new releases once a day"];
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 1) {
        static NSString *kUpdateCellId = @"SettingsUpdateCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUpdateCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kUpdateCellId] autorelease];
        }
        cell.selectionStyle = _updateChecker ? UITableViewCellSelectionStyleNone
                                             : UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        if (_updateChecker) {
            UIActivityIndicatorViewStyle style = VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray;
            UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style] autorelease];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.accessoryView = VCCreateDisclosureAccessoryView();
        }
        [self applySettingsMarqueesToCell:cell
                                    title:@"Check for Updates"
                                   detail:[self updateCheckDetailText]];
        return cell;
    }

    if (indexPath.section == 4 && indexPath.row == 0) {
        static NSString *kDebugCellId = @"SettingsDebugCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDebugCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kDebugCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"Debug and diagnostics"
                                   detail:@"Live state, connection tests, events and reports"];
        return cell;
    }

    if (indexPath.section == 5 && indexPath.row == 0) {
        static NSString *kGitHubLegacyCellId = @"SettingsGitHubLegacyCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubLegacyCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kGitHubLegacyCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [_preferGitHubLegacySwitch setOn:VCPreferGitHubLegacy() animated:NO];
        cell.accessoryView = _preferGitHubLegacySwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Prefer GitHub Legacy"
                                   detail:@"Open GitHub links in the app before the browser"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 0) {
        static NSString *kAboutCellId = @"SettingsAboutCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"About vless-core"
                                   detail:@"Version and core binary info"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 1) {
        static NSString *kCreditsCellId = @"SettingsCreditsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"Credits"
                                   detail:@"Dependencies, licenses and special thanks"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 2) {
        static NSString *kFAQCellId = @"SettingsFAQCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"FAQ"
                                   detail:@"Common questions and quick answers"];
        return cell;
    }

    static NSString *kGitHubCellId = @"SettingsGitHubCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kGitHubCellId] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = VCCreateDisclosureAccessoryView();
    [self applySettingsMarqueesToCell:cell
                                title:@"Project on GitHub"
                               detail:@"github.com/notfence/vless-core-app"];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    [self applySettingsMarqueesToCell:cell
                                title:[self settingsTitleTextForIndexPath:indexPath]
                               detail:[self settingsDetailTextForIndexPath:indexPath]];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row == 0) {
        VCRecordAppEvent(@"ui", @"Routing settings opened", nil);
        RoutingVC *routing = [[[RoutingVC alloc] init] autorelease];
        [self.navigationController pushViewController:routing animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        VCRecordAppEvent(@"ui", @"Ping type menu opened", nil);
        UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Ping type"
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Proxy GET", @"TCP", @"ICMP", nil] autorelease];
        sheet.tag = kVCSettingsPingTypeActionSheetTag;
        [sheet showInView:self.view];
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        VCRecordAppEvent(@"ui", @"Xray version settings opened", nil);
        XrayVersionSpoofVC *spoof = [[[XrayVersionSpoofVC alloc] init] autorelease];
        [self.navigationController pushViewController:spoof animated:YES];
    } else if (indexPath.section == 2) {
        BOOL dark = (indexPath.row == 1);
        if (_darkTheme != dark) {
            _darkTheme = dark;
            VCAppearanceSetDark(dark);
            if ([_delegate respondsToSelector:@selector(settingsVC:didChangeDarkTheme:)]) {
                [_delegate settingsVC:self didChangeDarkTheme:dark];
            }
            [self applyTheme];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 1) {
            [self startManualUpdateCheck];
        }
    } else if (indexPath.section == 4) {
        VCRecordAppEvent(@"ui", @"Debug settings opened", nil);
        DebugVC *debug = [[[DebugVC alloc] init] autorelease];
        [self.navigationController pushViewController:debug animated:YES];
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) {
            AboutVC *about = [[[AboutVC alloc] init] autorelease];
            [self.navigationController pushViewController:about animated:YES];
        } else if (indexPath.row == 1) {
            CreditsVC *credits = [[[CreditsVC alloc] init] autorelease];
            [self.navigationController pushViewController:credits animated:YES];
        } else if (indexPath.row == 2) {
            FAQVC *faq = [[[FAQVC alloc] init] autorelease];
            [self.navigationController pushViewController:faq animated:YES];
        } else if (indexPath.row == 3) {
            VCOpenGitHubProject();
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != kVCSettingsPingTypeActionSheetTag ||
        buttonIndex < VCPingTypeProxyGET ||
        buttonIndex > VCPingTypeICMP ||
        buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }

    VCPingType pingType = (VCPingType)buttonIndex;
    VCRecordAppEvent(@"settings", @"Ping type changed",
                     [NSString stringWithFormat:@"type=%ld", (long)pingType]);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:pingType forKey:kDefaultsPingTypeKey];
    [defaults synchronize];
    [_tableView reloadRowsAtIndexPaths:
        [NSArray arrayWithObject:[NSIndexPath indexPathForRow:1 inSection:1]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != kVCSettingsUpdateAlertTag || buttonIndex == alertView.cancelButtonIndex) return;

    VCOpenGitHubLatestRelease(_availableReleaseURL);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    _updateChecker.delegate = nil;
    [_updateChecker release];
    [_availableReleaseURL release];
    [_tableView release];
    [_autoUpdateSwitch release];
    [_preserveCustomNamesSwitch release];
    [_stealthSwitch release];
    [_automaticUpdateChecksSwitch release];
    [_preferGitHubLegacySwitch release];
    [super dealloc];
}

@end

@implementation SettingsNavController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    VCAppearanceApplyNavigationBar(self.navigationBar);
}

- (BOOL)shouldAutorotate {
    return [[self topViewController] shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [[self topViewController] supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[self topViewController] preferredInterfaceOrientationForPresentation];
}

@end

@protocol QRScanVCDelegate <NSObject>
- (void)qrScanVCDidCancel:(UIViewController *)vc;
- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text;
@end

@interface QRScanVC : UIViewController <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate> {
    id<QRScanVCDelegate> _delegate;
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_camera;
    AVCaptureMetadataOutput *_metadataOutput;
    AVCaptureVideoDataOutput *_videoOutput;
    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _videoQueue;
    AVCaptureVideoPreviewLayer *_previewLayer;
    UILabel *_hintLabel;
    UIButton *_torchButton;
    UIButton *_cancelButton;
    UILabel *_cancelButtonLabel;
    UIView *_focusIndicator;
    UITapGestureRecognizer *_focusGesture;
    zbar_image_scanner_t *_qrScanner;
    NSString *_pendingScanResult;
    NSUInteger _zbarPassIndex;
    NSTimeInterval _scanEnabledAt;
    NSTimeInterval _nextZBarScanAt;
    BOOL _captureConfigurationStarted;
    BOOL _scannerVisible;
    BOOL _didFinish;
    BOOL _torchEnabled;
}
@property (nonatomic, assign) id<QRScanVCDelegate> delegate;
- (void)applyNativeQRMetadataType;
@end

@implementation QRScanVC

@synthesize delegate = _delegate;

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (void)setScannerHintText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) text = @"";
    _hintLabel.text = text;
}

- (void)updateTorchButtonAppearance {
    if (!_torchButton) return;

    _torchButton.selected = _torchEnabled;
    _torchButton.backgroundColor = _torchEnabled
        ? [UIColor colorWithWhite:0.0f alpha:0.68f]
        : [UIColor colorWithWhite:0.0f alpha:0.28f];
    _torchButton.accessibilityValue = _torchEnabled ? @"On" : @"Off";
}

- (void)setTorchEnabled:(BOOL)enabled {
    if (!_camera || ![_camera hasTorch] ||
        ![_camera isTorchModeSupported:(enabled ? AVCaptureTorchModeOn : AVCaptureTorchModeOff)]) {
        _torchEnabled = NO;
        [self updateTorchButtonAppearance];
        return;
    }

    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    @try {
        [_camera setTorchMode:(enabled ? AVCaptureTorchModeOn : AVCaptureTorchModeOff)];
        _torchEnabled = enabled;
    }
    @catch (NSException *exception) {
        (void)exception;
        _torchEnabled = NO;
    }
    [_camera unlockForConfiguration];
    [self updateTorchButtonAppearance];
}

- (void)torchPressed {
    [self setTorchEnabled:!_torchEnabled];
}

- (void)configureContinuousCameraFocus {
    if (!_camera) return;

    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    if ([_camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        [_camera setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    }
    if ([_camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [_camera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_camera unlockForConfiguration];
}

- (void)showFocusIndicatorAtPoint:(CGPoint)point {
    if (!_focusIndicator) return;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    _focusIndicator.center = point;
    _focusIndicator.alpha = 1.0f;
    _focusIndicator.transform = CGAffineTransformMakeScale(1.25f, 1.25f);
    [UIView animateWithDuration:0.18f animations:^{
        _focusIndicator.transform = CGAffineTransformIdentity;
    }];
    [self performSelector:@selector(hideFocusIndicator) withObject:nil afterDelay:0.8f];
}

- (void)hideFocusIndicator {
    [UIView animateWithDuration:0.2f animations:^{
        _focusIndicator.alpha = 0.0f;
    }];
}

- (void)focusTapped:(UITapGestureRecognizer *)gesture {
    if (!_camera || !_previewLayer || [gesture state] != UIGestureRecognizerStateEnded) return;

    CGPoint viewPoint = [gesture locationInView:self.view];
    if (CGRectContainsPoint(_hintLabel.frame, viewPoint) ||
        CGRectContainsPoint(_cancelButton.frame, viewPoint) ||
        (!_torchButton.hidden && CGRectContainsPoint(_torchButton.frame, viewPoint))) {
        return;
    }
    if (![_camera isFocusPointOfInterestSupported] ||
        ![_camera isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        return;
    }

    CGPoint devicePoint = [_previewLayer captureDevicePointOfInterestForPoint:viewPoint];
    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    [_camera setFocusPointOfInterest:devicePoint];
    [_camera setFocusMode:AVCaptureFocusModeAutoFocus];
    if ([_camera isExposurePointOfInterestSupported] &&
        [_camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [_camera setExposurePointOfInterest:devicePoint];
        [_camera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_camera unlockForConfiguration];

    [self showFocusIndicatorAtPoint:viewPoint];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [self performSelector:@selector(configureContinuousCameraFocus) withObject:nil afterDelay:1.2f];
}

- (AVCaptureVideoOrientation)captureVideoOrientationForCurrentInterfaceOrientation {
    UIInterfaceOrientation ui = CurrentInterfaceOrientation();
    switch (ui) {
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationPortrait:
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (void)updateCaptureConnectionOrientations {
    AVCaptureVideoOrientation v = [self captureVideoOrientationForCurrentInterfaceOrientation];

    AVCaptureConnection *previewConn = [_previewLayer connection];
    if (previewConn && [previewConn isVideoOrientationSupported]) {
        [previewConn setVideoOrientation:v];
    }

    AVCaptureConnection *metadataConn = [_metadataOutput connectionWithMediaType:AVMediaTypeVideo];
    if (metadataConn && [metadataConn isVideoOrientationSupported]) {
        [metadataConn setVideoOrientation:v];
    }

    AVCaptureConnection *videoConn = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConn && [videoConn isVideoOrientationSupported]) {
        [videoConn setVideoOrientation:v];
    }
}

- (void)setCaptureSessionRunning:(BOOL)running {
    if (!_captureSession || !_sessionQueue) return;

    AVCaptureSession *session = [_captureSession retain];
    QRScanVC *controller = (running && _metadataOutput) ? [self retain] : nil;
    dispatch_async(_sessionQueue, ^{
        if (running) {
            if (![session isRunning]) [session startRunning];
        } else {
            if ([session isRunning]) [session stopRunning];
        }
        if (controller) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller applyNativeQRMetadataType];
                [controller release];
            });
        }
        [session release];
    });
}

- (void)notifyDelegateOfScanResult {
    if (![_pendingScanResult isKindOfClass:[NSString class]] || [_pendingScanResult length] == 0) return;

    NSString *value = [[_pendingScanResult retain] autorelease];
    [_pendingScanResult release];
    _pendingScanResult = nil;
    if ([_delegate respondsToSelector:@selector(qrScanVC:didScanText:)]) {
        [_delegate qrScanVC:self didScanText:value];
    }
}

- (void)deliverScanResult:(NSString *)rawValue {
    if (_didFinish) return;
    NSString *value = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;

    _didFinish = YES;
    _pendingScanResult = [value copy];
    _cancelButton.enabled = NO;
    _torchButton.enabled = NO;
    [self setScannerHintText:@"Succeeded ✅"];
    _hintLabel.backgroundColor = [UIColor colorWithRed:0.08f green:0.55f blue:0.22f alpha:0.9f];
    _hintLabel.alpha = 0.0f;
    _hintLabel.transform = CGAffineTransformMakeScale(0.86f, 0.86f);
    [UIView animateWithDuration:0.16f animations:^{
        _hintLabel.alpha = 1.0f;
        _hintLabel.transform = CGAffineTransformIdentity;
    }];
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
    [self performSelector:@selector(notifyDelegateOfScanResult) withObject:nil afterDelay:0.45];
}

- (BOOL)tryDecodeFrameWithZBar:(CMSampleBufferRef)sampleBuffer decodedText:(NSString **)decodedText {
    if (!sampleBuffer || !decodedText) return NO;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return NO;

    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t width = 0;
    size_t height = 0;
    size_t bytesPerRow = 0;
    const uint8_t *source = NULL;
    BOOL isPlanar = CVPixelBufferIsPlanar(imageBuffer);

    if (isPlanar && CVPixelBufferGetPlaneCount(imageBuffer) > 0) {
        width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        source = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    } else {
        width = CVPixelBufferGetWidth(imageBuffer);
        height = CVPixelBufferGetHeight(imageBuffer);
        bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        source = (const uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    }

    if (!source || width < 40 || height < 40 ||
        width > UINT_MAX || height > UINT_MAX || height > (SIZE_MAX / width)) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    size_t imageLength = width * height;
    uint8_t *luma = (uint8_t *)malloc(imageLength);
    if (!luma) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    if (isPlanar) {
        for (size_t y = 0; y < height; y++) {
            memcpy(luma + (y * width), source + (y * bytesPerRow), width);
        }
    } else {
        OSType pixelType = CVPixelBufferGetPixelFormatType(imageBuffer);
        if (pixelType == kCVPixelFormatType_32BGRA || pixelType == kCVPixelFormatType_32ARGB) {
            for (size_t y = 0; y < height; y++) {
                const uint8_t *row = source + (y * bytesPerRow);
                uint8_t *dstRow = luma + (y * width);
                for (size_t x = 0; x < width; x++) {
                    const uint8_t *px = row + (x * 4);
                    unsigned int red = (pixelType == kCVPixelFormatType_32BGRA) ? px[2] : px[1];
                    unsigned int green = (pixelType == kCVPixelFormatType_32BGRA) ? px[1] : px[2];
                    unsigned int blue = (pixelType == kCVPixelFormatType_32BGRA) ? px[0] : px[3];
                    dstRow[x] = (uint8_t)((red * 77U + green * 150U + blue * 29U) >> 8);
                }
            }
        } else {
            for (size_t y = 0; y < height; y++) {
                memcpy(luma + (y * width), source + (y * bytesPerRow), width);
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    if (!_qrScanner) {
        _qrScanner = zbar_image_scanner_create();
        if (_qrScanner) {
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_ENABLE, 0);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_TEST_INVERTED, 0);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_X_DENSITY, 1);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_Y_DENSITY, 1);
        }
    }
    if (!_qrScanner) {
        free(luma);
        return NO;
    }

    size_t centerX0 = width / 4;
    size_t centerX1 = width - centerX0;
    size_t centerY0 = height / 4;
    size_t centerY1 = height - centerY0;
    uint64_t centerLuma = 0;
    size_t centerSamples = 0;
    for (size_t y = centerY0; y < centerY1; y += 8) {
        for (size_t x = centerX0; x < centerX1; x += 8) {
            centerLuma += luma[y * width + x];
            centerSamples++;
        }
    }

    NSUInteger pass = _zbarPassIndex++ & 3U;
    BOOL preferInverted = (centerSamples > 0 && centerLuma / centerSamples < 110U);
    BOOL inverted = ((pass & 1U) == 0U) ? preferInverted : !preferInverted;
    BOOL useUpscaledCenter = (pass >= 2U);
    uint8_t *pixels = luma;
    uint8_t *upscaled = NULL;
    size_t scanWidth = width;
    size_t scanHeight = height;
    size_t scanLength = imageLength;

    if (useUpscaledCenter) {
        size_t cropSide = MIN(width, height) / 2;
        scanWidth = cropSide * 2;
        scanHeight = scanWidth;
        if (cropSide < 80 || scanHeight > (SIZE_MAX / scanWidth)) {
            free(luma);
            return NO;
        }
        scanLength = scanWidth * scanHeight;
        upscaled = (uint8_t *)malloc(scanLength);
        if (!upscaled) {
            free(luma);
            return NO;
        }

        size_t cropX = (width - cropSide) / 2;
        size_t cropY = (height - cropSide) / 2;
        for (size_t y = 0; y < scanHeight; y++) {
            const uint8_t *sourceRow = luma + ((cropY + y / 2) * width) + cropX;
            uint8_t *targetRow = upscaled + y * scanWidth;
            for (size_t x = 0; x < scanWidth; x++) {
                uint8_t value = sourceRow[x / 2];
                targetRow[x] = inverted ? (uint8_t)(255U - value) : value;
            }
        }
        pixels = upscaled;
    } else if (inverted) {
        for (size_t i = 0; i < imageLength; i++) luma[i] = (uint8_t)(255U - luma[i]);
    }

    zbar_image_t *image = zbar_image_create();
    if (!image) {
        free(upscaled);
        free(luma);
        return NO;
    }
    zbar_image_set_format(image, zbar_fourcc('Y', '8', '0', '0'));
    zbar_image_set_size(image, (unsigned int)scanWidth, (unsigned int)scanHeight);
    zbar_image_set_data(image, pixels, scanLength, NULL);

    NSString *text = nil;
    if (zbar_scan_image(_qrScanner, image) > 0) {
        const zbar_symbol_t *symbol = zbar_image_first_symbol(image);
        for (; symbol; symbol = zbar_symbol_next(symbol)) {
            if (zbar_symbol_get_type(symbol) != ZBAR_QRCODE) continue;
            const char *payload = zbar_symbol_get_data(symbol);
            unsigned int payloadLength = zbar_symbol_get_data_length(symbol);
            if (!payload || payloadLength == 0) continue;

            text = [[[NSString alloc] initWithBytes:payload
                                             length:(NSUInteger)payloadLength
                                           encoding:NSUTF8StringEncoding] autorelease];
            if (!text) {
                text = [[[NSString alloc] initWithBytes:payload
                                                 length:(NSUInteger)payloadLength
                                               encoding:NSISOLatin1StringEncoding] autorelease];
            }
            if (text && [text length] > 0) break;
        }
    }

    zbar_image_set_data(image, NULL, 0, NULL);
    zbar_image_destroy(image);
    free(upscaled);
    free(luma);

    if (text && [text length] > 0) {
        *decodedText = text;
        return YES;
    }

    return NO;
}

- (NSString *)configureCaptureSession {
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!camera) return @"Camera is unavailable on this device";

    _camera = [camera retain];
    [self configureContinuousCameraFocus];

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (!input) return @"Failed to access camera";

    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    } else if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    } else if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    } else {
        [_captureSession release];
        _captureSession = nil;
        return @"Camera input is not supported";
    }

    if ([[UIDevice currentDevice].systemVersion integerValue] >= 11) {
        _metadataOutput = [[AVCaptureMetadataOutput alloc] init];
        if ([_captureSession canAddOutput:_metadataOutput]) {
            [_captureSession addOutput:_metadataOutput];
            [_metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        } else {
            [_metadataOutput release];
            _metadataOutput = nil;
            return @"Native QR recognition is unavailable";
        }
    } else {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
        NSDictionary *settings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [_videoOutput setVideoSettings:settings];
        _videoQueue = dispatch_queue_create("com.vlesscore.qrscan.video", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_videoQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
        if ([_captureSession canAddOutput:_videoOutput]) {
            [_captureSession addOutput:_videoOutput];
        } else {
            [_videoOutput release];
            _videoOutput = nil;
            return @"Legacy QR recognition is unavailable";
        }
    }
    return nil;
}

- (void)applyNativeQRMetadataType {
    if (!_metadataOutput || _didFinish || !_scannerVisible) return;

    NSArray *availableTypes = [_metadataOutput availableMetadataObjectTypes];
    if (![availableTypes containsObject:kVCQRMetadataType]) return;
    @try {
        [_metadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:kVCQRMetadataType]];
    }
    @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)finishCaptureSessionConfigurationWithError:(NSString *)errorText {
    if ([errorText length] > 0) {
        [self setScannerHintText:errorText];
        return;
    }
    if (!_captureSession || _didFinish || !_scannerVisible) return;

    if (!_previewLayer) {
        _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.view.layer insertSublayer:_previewLayer atIndex:0];
    }
    _previewLayer.frame = self.view.bounds;
    _torchButton.hidden = !(_camera && [_camera hasTorch] &&
                            [_camera isTorchModeSupported:AVCaptureTorchModeOn] &&
                            [_camera isTorchModeSupported:AVCaptureTorchModeOff]);
    [self updateCaptureConnectionOrientations];
    [self setCaptureSessionRunning:YES];
}

- (void)beginCaptureSessionConfiguration {
    if (_captureConfigurationStarted) return;
    _captureConfigurationStarted = YES;
    dispatch_async(_sessionQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = [[self configureCaptureSession] retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishCaptureSessionConfigurationWithError:errorText];
            [errorText release];
        });
        [pool drain];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.58f];
    _hintLabel.textColor = [UIColor whiteColor];
    _hintLabel.font = [UIFont boldSystemFontOfSize:16.0];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.numberOfLines = 1;
    _hintLabel.layer.cornerRadius = 8.0f;
    _hintLabel.layer.masksToBounds = YES;
    [self setScannerHintText:@"Scan a QR code"];
    [self.view addSubview:_hintLabel];

    _torchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_torchButton retain];
    _torchButton.hidden = YES;
    _torchButton.accessibilityLabel = @"Flashlight";
    _torchButton.adjustsImageWhenHighlighted = YES;
    UIImage *flashlightIcon = LoadBundledIconScaled(@"icon-flashlight", 32.0f);
    [_torchButton setImage:flashlightIcon forState:UIControlStateNormal];
    [_torchButton setImage:flashlightIcon forState:UIControlStateSelected];
    _torchButton.layer.cornerRadius = 22.0f;
    [_torchButton addTarget:self action:@selector(torchPressed) forControlEvents:UIControlEventTouchUpInside];
    [self updateTorchButtonAppearance];
    [self.view addSubview:_torchButton];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setTitle:@"" forState:UIControlStateNormal];
    _cancelButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _cancelButton.layer.cornerRadius = 8.0f;
    _cancelButton.layer.borderWidth = 1.0f;
    _cancelButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    _cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [_cancelButton addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    _cancelButtonLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _cancelButtonLabel.backgroundColor = [UIColor clearColor];
    _cancelButtonLabel.text = @"Cancel";
    _cancelButtonLabel.font = [UIFont boldSystemFontOfSize:17.0];
    _cancelButtonLabel.textAlignment = NSTextAlignmentCenter;
    _cancelButtonLabel.textColor = [UIColor whiteColor];
    _cancelButtonLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _cancelButtonLabel.shadowOffset = CGSizeMake(0.0f, -1.0f);
    _cancelButtonLabel.userInteractionEnabled = NO;
    [_cancelButton addSubview:_cancelButtonLabel];

    _focusIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 72.0f, 72.0f)];
    _focusIndicator.userInteractionEnabled = NO;
    _focusIndicator.backgroundColor = [UIColor clearColor];
    _focusIndicator.layer.cornerRadius = 8.0f;
    _focusIndicator.layer.borderWidth = 2.0f;
    _focusIndicator.layer.borderColor = [UIColor colorWithRed:1.0f green:0.82f blue:0.18f alpha:1.0f].CGColor;
    _focusIndicator.alpha = 0.0f;
    [self.view addSubview:_focusIndicator];

    _focusGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusTapped:)];
    _focusGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:_focusGesture];

    _sessionQueue = dispatch_queue_create("com.vlesscore.qrscan.session", DISPATCH_QUEUE_SERIAL);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    _previewLayer.frame = b;
    [self updateCaptureConnectionOrientations];

    CGFloat pad = 14.0f;
    CGFloat top = 28.0f;
    CGRect sb = [UIApplication sharedApplication].statusBarFrame;
    CGFloat statusInset = MIN(sb.size.width, sb.size.height);
    if (statusInset > 0.0f && statusInset < 64.0f) {
        top = statusInset + 8.0f;
    }
    CGFloat hintWidth = MIN(190.0f, b.size.width - (pad * 2.0f) - 56.0f);
    _hintLabel.frame = CGRectMake(floor((b.size.width - hintWidth) * 0.5f), top, hintWidth, 42.0f);
    _torchButton.frame = CGRectMake(b.size.width - pad - 44.0f, top, 44.0f, 44.0f);
    _cancelButton.frame = CGRectMake(pad, b.size.height - 62.0f - pad, b.size.width - (pad * 2.0f), 62.0f);
    _cancelButtonLabel.frame = _cancelButton.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _didFinish = NO;
    _zbarPassIndex = 0;
    _scanEnabledAt = HUGE_VAL;
    _nextZBarScanAt = HUGE_VAL;
    [_pendingScanResult release];
    _pendingScanResult = nil;
    _cancelButton.enabled = YES;
    _torchButton.enabled = YES;
    [self setScannerHintText:@"Scan a QR code"];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.58f];
    _hintLabel.alpha = 1.0f;
    _hintLabel.transform = CGAffineTransformIdentity;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _scannerVisible = YES;
    _scanEnabledAt = CACurrentMediaTime() + 1.0;
    _nextZBarScanAt = _scanEnabledAt;
    if (_captureSession) {
        [self finishCaptureSessionConfigurationWithError:nil];
    } else {
        [self beginCaptureSessionConfiguration];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _scannerVisible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyDelegateOfScanResult) object:nil];
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
}

- (void)cancelPressed {
    _didFinish = YES;
    [_pendingScanResult release];
    _pendingScanResult = nil;
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
    if ([_delegate respondsToSelector:@selector(qrScanVCDidCancel:)]) {
        [_delegate qrScanVCDidCancel:self];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    if (_didFinish || ![metadataObjects isKindOfClass:[NSArray class]]) return;

    for (id object in metadataObjects) {
        if (![object respondsToSelector:@selector(type)] ||
            ![object respondsToSelector:@selector(stringValue)]) {
            continue;
        }
        NSString *type = [object performSelector:@selector(type)];
        if (![type isEqualToString:kVCQRMetadataType]) continue;
        NSString *value = [object performSelector:@selector(stringValue)];
        if (![value isKindOfClass:[NSString class]] || [value length] == 0) continue;
        [self deliverScanResult:value];
        return;
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    NSTimeInterval now = CACurrentMediaTime();
    if (_didFinish || now < _scanEnabledAt || now < _nextZBarScanAt) return;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *decoded = nil;
    BOOL found = [self tryDecodeFrameWithZBar:sampleBuffer decodedText:&decoded];
    _nextZBarScanAt = CACurrentMediaTime() + 0.18;
    if (!found) {
        [pool drain];
        return;
    }
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        [pool drain];
        return;
    }

    NSString *captured = [decoded copy];
    [pool drain];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self deliverScanResult:captured];
        [captured release];
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
    if (_sessionQueue) {
        dispatch_release(_sessionQueue);
        _sessionQueue = NULL;
    }
    if (_videoQueue) {
        dispatch_release(_videoQueue);
        _videoQueue = NULL;
    }
    if (_qrScanner) {
        zbar_image_scanner_destroy(_qrScanner);
        _qrScanner = NULL;
    }
    [_captureSession release];
    [_camera release];
    [_metadataOutput release];
    [_videoOutput release];
    [_previewLayer release];
    [_hintLabel release];
    [_torchButton release];
    [_cancelButtonLabel release];
    [_focusIndicator release];
    [_focusGesture release];
    [_pendingScanResult release];
    [super dealloc];
}

@end

@class SubscriptionInfoVC;
@protocol SubscriptionInfoVCDelegate <NSObject>
- (void)subscriptionInfoVCRequestedRefresh:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
- (void)subscriptionInfoVCRequestedDelete:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
- (void)subscriptionInfoVC:(SubscriptionInfoVC *)vc requestedRenameTo:(NSString *)name atIndex:(NSInteger)index;
@end

@interface SubscriptionInfoVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    NSDictionary *_subscription;
    NSArray *_sections;
    NSInteger _subscriptionIndex;
    BOOL _stealthMode;
    BOOL _refreshing;
    id<SubscriptionInfoVCDelegate> _delegate;
}
- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode
                  delegate:(id<SubscriptionInfoVCDelegate>)delegate;
- (NSInteger)subscriptionIndex;
- (void)reloadWithSubscription:(NSDictionary *)subscription;
- (void)cancelRefresh;
- (void)finishRefreshWithSubscription:(NSDictionary *)subscription errorText:(NSString *)errorText;
@end

@implementation SubscriptionInfoVC

- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode
                  delegate:(id<SubscriptionInfoVCDelegate>)delegate {
    self = [super init];
    if (!self) return nil;

    _subscription = [subscription copy];
    _subscriptionIndex = index;
    _stealthMode = stealthMode;
    _delegate = delegate;
    return self;
}

- (void)dealloc {
    [_tableView release];
    [_subscription release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail action:(NSString *)action {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    [row setObject:(title ? title : @"") forKey:@"title"];
    if ([detail isKindOfClass:[NSString class]] && [detail length] > 0) {
        [row setObject:detail forKey:@"detail"];
    }
    if ([action isKindOfClass:[NSString class]] && [action length] > 0) {
        [row setObject:action forKey:@"action"];
    }
    return row;
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            (title ? title : @""), @"title",
            (rows ? rows : [NSArray array]), @"rows",
            nil];
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
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

- (NSString *)formattedTimestamp:(unsigned long long)timestamp includeTime:(BOOL)includeTime {
    if (timestamp == 0) return nil;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestamp];
    if (!date) return nil;

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setDateFormat:(includeTime ? @"dd.MM.yyyy HH:mm" : @"dd.MM.yyyy")];
    return [formatter stringFromDate:date];
}

- (void)buildSections {
    NSMutableArray *newSections = [NSMutableArray array];
    NSMutableArray *generalRows = [NSMutableArray array];
    NSMutableArray *usageRows = [NSMutableArray array];
    NSMutableArray *providerRows = [NSMutableArray array];

    NSString *name = [_subscription objectForKey:@"name"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = @"Unnamed subscription";
    [generalRows addObject:[self rowWithTitle:@"Name" detail:name action:nil]];

    NSString *url = [_subscription objectForKey:@"url"];
    if (![url isKindOfClass:[NSString class]]) url = @"";
    BOOL encryptedHappSubscription = SubscriptionDictionaryIsHappEncrypted(_subscription);
    NSString *shownURL = (_stealthMode || encryptedHappSubscription) ? kHiddenLinkText : url;
    if ([shownURL length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Subscription Link" detail:shownURL action:nil]];
    }

    NSDictionary *metadata = [_subscription objectForKey:kSubscriptionMetadataKey];
    if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
    NSString *description = [metadata objectForKey:kSubscriptionDescriptionKey];
    if ([description isKindOfClass:[NSString class]] && [description length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Description" detail:description action:nil]];
    }
    [newSections addObject:[self sectionWithTitle:@"Subscription" rows:generalRows]];

    NSArray *items = [_subscription objectForKey:@"items"];
    NSUInteger itemCount = [items isKindOfClass:[NSArray class]] ? [items count] : 0;
    [usageRows addObject:[self rowWithTitle:@"Configurations"
                                    detail:[NSString stringWithFormat:@"%lu", (unsigned long)itemCount]
                                    action:nil]];

    NSDictionary *userInfo = [_subscription objectForKey:kSubscriptionUserInfoKey];
    if ([userInfo isKindOfClass:[NSDictionary class]]) {
        NSNumber *uploadNumber = [userInfo objectForKey:kSubscriptionUploadKey];
        NSNumber *downloadNumber = [userInfo objectForKey:kSubscriptionDownloadKey];
        NSNumber *totalNumber = [userInfo objectForKey:kSubscriptionTotalKey];
        NSNumber *expireNumber = [userInfo objectForKey:kSubscriptionExpireKey];
        BOOL hasUpload = [uploadNumber isKindOfClass:[NSNumber class]];
        BOOL hasDownload = [downloadNumber isKindOfClass:[NSNumber class]];

        unsigned long long upload = hasUpload ? [uploadNumber unsignedLongLongValue] : 0;
        unsigned long long download = hasDownload ? [downloadNumber unsignedLongLongValue] : 0;
        if (hasUpload || hasDownload) {
            unsigned long long used = (ULLONG_MAX - upload < download) ? ULLONG_MAX : upload + download;
            [usageRows addObject:[self rowWithTitle:@"Traffic Used" detail:[self formattedBytes:used] action:nil]];
        }
        if (hasUpload) {
            [usageRows addObject:[self rowWithTitle:@"Uploaded" detail:[self formattedBytes:upload] action:nil]];
        }
        if (hasDownload) {
            [usageRows addObject:[self rowWithTitle:@"Downloaded" detail:[self formattedBytes:download] action:nil]];
        }
        if ([totalNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long total = [totalNumber unsignedLongLongValue];
            NSString *limit = (total == 0) ? @"Unlimited" : [self formattedBytes:total];
            [usageRows addObject:[self rowWithTitle:@"Traffic Limit" detail:limit action:nil]];
        }
        if ([expireNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long expire = [expireNumber unsignedLongLongValue];
            NSString *expiry = (expire == 0) ? @"No expiration" : [self formattedTimestamp:expire includeTime:NO];
            if ([expiry length] > 0) {
                [usageRows addObject:[self rowWithTitle:@"Expires" detail:expiry action:nil]];
            }
        }
    }

    NSNumber *refillNumber = [metadata objectForKey:kSubscriptionRefillDateKey];
    if ([refillNumber isKindOfClass:[NSNumber class]]) {
        NSString *refill = [self formattedTimestamp:[refillNumber unsignedLongLongValue] includeTime:NO];
        if ([refill length] > 0) {
            [usageRows addObject:[self rowWithTitle:@"Traffic Refill" detail:refill action:nil]];
        }
    }
    [newSections addObject:[self sectionWithTitle:@"Usage" rows:usageRows]];

    NSString *webPageURL = [metadata objectForKey:kSubscriptionWebPageURLKey];
    if ([webPageURL isKindOfClass:[NSString class]] && [webPageURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Web Page"
                                            detail:(_stealthMode ? kHiddenLinkText : webPageURL)
                                            action:nil]];
    }
    NSString *supportURL = [metadata objectForKey:kSubscriptionSupportURLKey];
    if ([supportURL isKindOfClass:[NSString class]] && [supportURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Support"
                                            detail:(_stealthMode ? kHiddenLinkText : supportURL)
                                            action:nil]];
    }
    NSNumber *intervalNumber = [metadata objectForKey:kSubscriptionUpdateIntervalKey];
    if ([intervalNumber isKindOfClass:[NSNumber class]]) {
        unsigned long long hours = [intervalNumber unsignedLongLongValue];
        NSString *interval = [NSString stringWithFormat:@"%llu hour%@", hours, (hours == 1 ? @"" : @"s")];
        [providerRows addObject:[self rowWithTitle:@"Suggested Update Interval" detail:interval action:nil]];
    }
    NSNumber *lastUpdatedNumber = [metadata objectForKey:kSubscriptionLastUpdatedKey];
    if ([lastUpdatedNumber isKindOfClass:[NSNumber class]]) {
        NSString *lastUpdated = [self formattedTimestamp:[lastUpdatedNumber unsignedLongLongValue] includeTime:YES];
        if ([lastUpdated length] > 0) {
            [providerRows addObject:[self rowWithTitle:@"Last Updated" detail:lastUpdated action:nil]];
        }
    }
    [providerRows addObject:[self rowWithTitle:@"Source"
                                       detail:(encryptedHappSubscription
                                                   ? @"HAPP (encrypted)"
                                                   : (SubscriptionDictionaryUsesHappHeaders(_subscription) ? @"HAPP" : @"URL"))
                                       action:nil]];
    [newSections addObject:[self sectionWithTitle:@"Provider" rows:providerRows]];

    NSArray *actions = [NSArray arrayWithObjects:
                        [self rowWithTitle:@"Rename Subscription" detail:nil action:@"rename"],
                        [self rowWithTitle:(_refreshing ? @"Updating..." : @"Update Now") detail:nil action:@"refresh"],
                        [self rowWithTitle:@"Delete Subscription" detail:nil action:@"delete"],
                        nil];
    [newSections addObject:[self sectionWithTitle:@"Actions" rows:actions]];

    [_sections release];
    _sections = [[NSArray alloc] initWithArray:newSections];
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    [_tableView reloadData];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Subscription Info";
    self.view.backgroundColor = VCBackgroundColor();

    UIBarButtonItem *back = [[[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                              style:UIBarButtonItemStyleBordered
                                                             target:self
                                                             action:@selector(backPressed)] autorelease];
    self.navigationItem.leftBarButtonItem = back;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    [self buildSections];
    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)backPressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)subscriptionIndex {
    return _subscriptionIndex;
}

- (void)reloadWithSubscription:(NSDictionary *)subscription {
    if (![subscription isKindOfClass:[NSDictionary class]]) return;
    [_subscription release];
    _subscription = [subscription copy];
    [self buildSections];
    [_tableView reloadData];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *section = [_sections objectAtIndex:indexPath.section];
    return [[section objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return [[[_sections objectAtIndex:section] objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    if ([row objectForKey:@"action"]) return 44.0f;

    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                          constrainedToSize:CGSizeMake(width, 1000.0f)
                              lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    NSString *reuseID = action ? @"SubscriptionActionCell" : @"SubscriptionInfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        UITableViewCellStyle style = action ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle;
        cell = [[[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseID] autorelease];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);

    if (action) {
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.textLabel.textColor = [action isEqualToString:@"delete"] ? VCErrorColor() : VCAccentColor();
        cell.selectionStyle = _refreshing ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
        if ([action isEqualToString:@"refresh"] && _refreshing) {
            UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:(VCAppearanceIsDark() ? UIActivityIndicatorViewStyleWhite
                                                                     : UIActivityIndicatorViewStyleGray)] autorelease];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    if ([action isEqualToString:@"delete"]) cell.textLabel.textColor = VCErrorColor();
    else if ([action length] > 0) cell.textLabel.textColor = VCAccentColor();
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_refreshing || !action) return;

    if ([action isEqualToString:@"rename"]) {
        NSString *name = [_subscription objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]]) name = @"";

        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Rename Subscription"
                                                        message:nil
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Save", nil] autorelease];
        alert.tag = kVCSubscriptionRenameAlertTag;
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *nameField = [alert textFieldAtIndex:0];
        nameField.text = name;
        nameField.placeholder = @"Subscription name";
        nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [alert show];
    } else if ([action isEqualToString:@"refresh"]) {
        _refreshing = YES;
        [self buildSections];
        [_tableView reloadData];
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVCRequestedRefresh:atIndex:)]) {
            [_delegate subscriptionInfoVCRequestedRefresh:self atIndex:_subscriptionIndex];
        } else {
            [self finishRefreshWithSubscription:nil errorText:@"Subscription update is unavailable"];
        }
    } else if ([action isEqualToString:@"delete"]) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Delete Subscription?"
                                                        message:@"The subscription and all of its configurations will be removed."
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Delete", nil] autorelease];
        alert.tag = kVCSubscriptionDeleteAlertTag;
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if (alertView.tag == kVCSubscriptionRenameAlertTag) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name length] == 0) {
            UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid Name"
                                                            message:@"Subscription name cannot be empty."
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil] autorelease];
            [error show];
            return;
        }
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVC:requestedRenameTo:atIndex:)]) {
            [_delegate subscriptionInfoVC:self requestedRenameTo:name atIndex:_subscriptionIndex];
        }
    } else if (alertView.tag == kVCSubscriptionDeleteAlertTag) {
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVCRequestedDelete:atIndex:)]) {
            [_delegate subscriptionInfoVCRequestedDelete:self atIndex:_subscriptionIndex];
        }
    }
}

- (void)finishRefreshWithSubscription:(NSDictionary *)subscription errorText:(NSString *)errorText {
    _refreshing = NO;
    if ([subscription isKindOfClass:[NSDictionary class]]) [self reloadWithSubscription:subscription];
    else {
        [self buildSections];
        [_tableView reloadData];
    }

    NSString *title = subscription ? @"Updated" : @"Update Failed";
    NSString *message = errorText;
    if (![message isKindOfClass:[NSString class]] || [message length] == 0) {
        NSArray *items = [_subscription objectForKey:@"items"];
        NSUInteger count = [items isKindOfClass:[NSArray class]] ? [items count] : 0;
        message = [NSString stringWithFormat:@"Subscription updated (%lu configs)", (unsigned long)count];
    }
    if (!self.view.window) return;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil] autorelease];
    [alert show];
}

- (void)cancelRefresh {
    _refreshing = NO;
    [self buildSections];
    [_tableView reloadData];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

@end

@protocol VCImportBrowserDelegate <NSObject>
- (void)importBrowserDidCancel:(UIViewController *)browser;
- (void)importBrowser:(UIViewController *)browser didSelectFileAtPath:(NSString *)path;
@end

@interface VCImportBrowserVC : UITableViewController {
    id<VCImportBrowserDelegate> _browserDelegate;
    NSString *_rootPath;
    NSString *_directoryPath;
    NSArray *_entries;
}
- (id)initWithRootPath:(NSString *)rootPath
         directoryPath:(NSString *)directoryPath
              delegate:(id<VCImportBrowserDelegate>)delegate;
@end

@implementation VCImportBrowserVC

- (id)initWithRootPath:(NSString *)rootPath
         directoryPath:(NSString *)directoryPath
              delegate:(id<VCImportBrowserDelegate>)delegate {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _browserDelegate = delegate;
        _rootPath = [[rootPath stringByStandardizingPath] copy];
        _directoryPath = [[directoryPath stringByStandardizingPath] copy];
    }
    return self;
}

- (BOOL)pathIsInsideImportDirectory:(NSString *)path {
    NSString *root = [_rootPath stringByResolvingSymlinksInPath];
    NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    if ([resolved isEqualToString:root]) return YES;
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [resolved hasPrefix:prefix];
}

- (void)reloadEntries {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directoryPath error:nil];
    NSMutableArray *directories = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];

    for (id object in names) {
        if (![object isKindOfClass:[NSString class]]) continue;
        NSString *name = (NSString *)object;
        if ([name length] == 0 || [name hasPrefix:@"."]) continue;

        NSString *path = [_directoryPath stringByAppendingPathComponent:name];
        if (![self pathIsInsideImportDirectory:path]) continue;

        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) continue;
        NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                               name, @"name",
                               path, @"path",
                               [NSNumber numberWithBool:isDirectory], @"is_directory",
                               nil];
        [(isDirectory ? directories : files) addObject:entry];
    }

    NSComparator comparator = ^NSComparisonResult(id left, id right) {
        return [[left objectForKey:@"name"] localizedCaseInsensitiveCompare:[right objectForKey:@"name"]];
    };
    [directories sortUsingComparator:comparator];
    [files sortUsingComparator:comparator];

    NSMutableArray *all = [NSMutableArray arrayWithArray:directories];
    [all addObjectsFromArray:files];
    [_entries release];
    _entries = [all copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [_directoryPath isEqualToString:_rootPath]
        ? @"Import Files"
        : [_directoryPath lastPathComponent];
    self.view.backgroundColor = VCBackgroundColor();
    self.tableView.backgroundColor = VCBackgroundColor();
    self.tableView.separatorColor = VCSeparatorColor();

    if ([_directoryPath isEqualToString:_rootPath]) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(cancelPressed)] autorelease];

        UILabel *hint = [[[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.view.bounds.size.width, 62.0f)] autorelease];
        hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        hint.backgroundColor = VCBackgroundColor();
        hint.textColor = VCSecondaryTextColor();
        hint.font = [UIFont systemFontOfSize:13.0f];
        hint.textAlignment = NSTextAlignmentCenter;
        hint.numberOfLines = 2;
        hint.text = @"Copy configuration or backup files to\n/var/mobile/vless-core-import";
        self.tableView.tableHeaderView = hint;
    }

    [self reloadEntries];
}

- (void)cancelPressed {
    if ([_browserDelegate respondsToSelector:@selector(importBrowserDidCancel:)]) {
        [_browserDelegate importBrowserDidCancel:self];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return MAX((NSInteger)[_entries count], 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"ImportFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    }

    cell.backgroundColor = VCCellBackgroundColor();
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if ([_entries count] == 0) {
        cell.textLabel.text = @"No files found";
        cell.detailTextLabel.text = @"Copy a file to the import directory, then reopen this screen.";
        cell.textLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
    BOOL isDirectory = [[entry objectForKey:@"is_directory"] boolValue];
    cell.textLabel.text = [entry objectForKey:@"name"];
    cell.detailTextLabel.text = isDirectory ? @"Folder" : @"Tap to import";
    cell.accessoryType = isDirectory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_entries count]) return;

    NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
    NSString *path = [entry objectForKey:@"path"];
    if ([[entry objectForKey:@"is_directory"] boolValue]) {
        VCImportBrowserVC *child = [[[VCImportBrowserVC alloc] initWithRootPath:_rootPath
                                                                  directoryPath:path
                                                                       delegate:_browserDelegate] autorelease];
        [self.navigationController pushViewController:child animated:YES];
    } else if ([_browserDelegate respondsToSelector:@selector(importBrowser:didSelectFileAtPath:)]) {
        [_browserDelegate importBrowser:self didSelectFileAtPath:path];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    _browserDelegate = nil;
    [_rootPath release];
    [_directoryPath release];
    [_entries release];
    [super dealloc];
}

@end

@interface MainVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UITextViewDelegate, SettingsVCDelegate, QRScanVCDelegate, SubscriptionInfoVCDelegate, VCUpdateCheckerDelegate, VCImportBrowserDelegate> {
    UIButton *_connectBtn;
    UIButton *_plusBtn;
    UIButton *_terminalBtn;
    UIButton *_clearLogsBtn;
    UIButton *_refreshBtn;
    UIButton *_settingsBtn;
    UIButton *_updateBtn;
    UILabel *_statusLabel;
    UILabel *_uptimeLabel;
    UILabel *_titleLabel;

    UITableView *_tableView;
    UIView *_logSelector;
    UIButton *_logSelectorButtons[2];
    UIView *_logSelectionIndicator;
    UITextView *_logView;
    UIView *_stickySectionHeaderView;
    NSTimer *_logTimer;
    NSTimer *_uptimeTimer;
    NSTimeInterval _connectedSince;
    NSString *_statusBaseText;
    NSString *_pendingImportDoneStatus;
    NSArray *_pendingImportRefreshIndices;
    NSArray *_pendingInsecureImportURLs;
    void (^_pendingPlainHTTPConfirmation)(void);
    void (^_pendingPlainHTTPCancellation)(void);
    NSDictionary *_subscriptionToReexpandAfterReorder;
    VCUpdateChecker *_updateChecker;
    NSString *_availableReleaseURL;
    NSString *_availableUpdateVersion;
    NSString *_pendingReconnectURI;

    NSMutableArray *_configs;
    NSMutableArray *_subscriptions;
    NSMutableDictionary *_pingDisplayByURI;
    NSMutableSet *_standalonePingURIs;
    NSMutableDictionary *_subscriptionPingPendingByIdentifier;
    NSMutableDictionary *_subscriptionPingOperationsByIdentifier;
    NSMutableDictionary *_subscriptionPingPreviousDisplayByIdentifier;
    NSMutableDictionary *_subscriptionPingTokenByIdentifier;
    NSOperationQueue *_pingQueue;

    NSInteger _selectedConfigIndex;
    NSInteger _selectedSubIndex;
    NSInteger _selectedSubItemIndex;
    NSInteger _expandedSubscription;
    NSInteger _updatingSubscriptionIndex;
    NSInteger _stickySectionHeaderSection;
    NSInteger _reorderingSection;
    NSInteger _activeLogIndex;
    NSUInteger _mainSectionTransitionToken;
    NSUInteger _nextSubscriptionPingToken;
    NSString *_logTexts[2];
    CGPoint _logContentOffsets[2];
    CGFloat _mainTableDragStartOffsetY;
    CGFloat _mainTableOffsetBeforeTransition;
    BOOL _logContentOffsetsValid[2];
    BOOL _logFollowsTail[2];
    BOOL _mainTableDragStartOffsetValid;
    BOOL _mainTableTransitionSnapshotValid;
    BOOL _phoneConnectionCompact;
    BOOL _phoneConnectionCompactBeforeTransition;

    BOOL _connected;
    BOOL _connectedWithProtectedLogs;
    BOOL _reconnectInProgress;
    BOOL _pendingReconnectProtectLogs;
    BOOL _daemonStatusCheckInFlight;
    BOOL _showingTerminal;
    BOOL _autoUpdateSubscriptions;
    BOOL _preserveCustomSubscriptionNames;
    BOOL _stealthModeEnabled;
    BOOL _darkThemeEnabled;
    BOOL _automaticUpdateChecksEnabled;
    BOOL _statusOK;
    BOOL _configurationsSectionExpanded;
    BOOL _subscriptionsSectionExpanded;
    BOOL _mainSectionTransitionInProgress;
    BOOL _didRunLaunchAutoUpdate;
    BOOL _didScheduleAutomaticUpdateCheck;
    BOOL _launchAutoUpdateInProgress;
    BOOL _queuedMainMarqueeRelayout;
    BOOL _pendingInsecureImportUsesHappHeaders;
}
- (void)reconcileConnectionStateWithDaemon;
- (void)beginPendingReconnect;
- (void)flushMainStateDefaults;
- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText;
- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts;
- (BOOL)subscriptionNeedsPlainHTTPApproval:(NSDictionary *)subscription;
- (BOOL)approvePlainHTTPForSubscriptionAtIndex:(NSInteger)index;
- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation;
- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation
                                        cancellation:(void (^)(void))cancellation;
- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL
                                  allowPlainHTTP:(BOOL)allowPlainHTTP;
- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
               allowPlainHTTP:(BOOL)allowPlainHTTP
                   happSource:(BOOL)happSource;
- (void)applyTheme;
- (UIView *)accessorySubscriptionHeaderAtIndex:(NSInteger)index expanded:(BOOL)expanded loading:(BOOL)loading;
- (void)setMainReorderingSection:(NSInteger)section showStatus:(BOOL)showStatus;
- (BOOL)mainSectionHasItems:(NSInteger)section;
- (BOOL)isMainSectionExpanded:(NSInteger)section;
- (void)updateMainEmptyState;
- (void)finishMainSectionTransition:(NSNumber *)transitionNumber;
- (void)rememberActiveLogPosition;
- (void)reloadMainTableDataAfterExternalChange;
- (void)refreshMainListCellAppearance:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
- (void)refreshVisiblePingAccessoriesForURI:(NSString *)uri;
- (void)refreshVisibleSubscriptionPingAccessories;
- (void)refreshVisibleSubscriptionHeaderAccessories;
- (void)refreshPresentedSubscriptionInfoIfNeeded;
- (void)refreshLogs;
- (BOOL)selectedSubscriptionIsHappEncrypted;
- (void)updateLogSelectorAnimated:(BOOL)animated;
- (void)updatePhoneConnectionScrollInsets;
- (void)updatePhoneConnectionLayout;
- (CGFloat)maximumMainTableContentOffsetY;
- (CGFloat)phoneConnectionSnapOffsetForProposedOffset:(CGFloat)proposedOffset
                                         currentOffset:(CGFloat)currentOffset
                                              velocity:(CGFloat)velocity;
- (void)animatePhoneConnectionToOffset:(CGFloat)targetOffset;
- (void)snapPhoneConnectionLayoutIfNeededAnimated:(BOOL)animated;
- (void)prepareMainTableStructuralTransition;
- (void)completeMainTableStructuralTransition;
- (void)stabilizeMainTableOffsetDuringStructuralTransition;
- (void)restoreMainTableAfterStructuralTransitionCompact:(BOOL)compact
                                          preservedOffset:(CGFloat)preservedOffset;
- (void)importFileAtURL:(NSURL *)url;
- (void)refreshUpdateIndicatorFromCache;
- (void)startAutomaticUpdateCheckIfNeeded;
- (void)updateMainSectionHeaderButton:(UIButton *)button section:(NSInteger)section animated:(BOOL)animated;
- (void)updateMainSectionHeaderView:(UIView *)header section:(NSInteger)section animated:(BOOL)animated;
- (void)updateStickyMainSectionHeader;
- (void)refreshStickyMainSectionHeader;
- (void)recordMainLayoutEvent:(NSString *)action section:(NSInteger)section;
@end

@implementation MainVC

- (void)recordMainLayoutEvent:(NSString *)action section:(NSInteger)section {
    if (!_tableView) return;
    NSString *sectionName = section == 0 ? @"configurations" : (section == 1 ? @"subscriptions" : @"none");
    CGFloat configurationsY = [self mainSectionHasItems:0]
        ? [_tableView rectForHeaderInSection:0].origin.y
        : -1.0f;
    CGFloat subscriptionsY = [self mainSectionHasItems:1]
        ? [_tableView rectForHeaderInSection:1].origin.y
        : -1.0f;
    NSString *detail = [NSString stringWithFormat:
                        @"section=%@ expanded=%d compact=%d offset=%.1f content=%.1f viewport=%.1f rows=%ld headers=%.1f/%.1f button=%.1fx%.1f font=%.1f",
                        sectionName,
                        section == 0 ? (_configurationsSectionExpanded ? 1 : 0) :
                                       (section == 1 ? (_subscriptionsSectionExpanded ? 1 : 0) : 0),
                        _phoneConnectionCompact ? 1 : 0,
                        _tableView.contentOffset.y,
                        _tableView.contentSize.height,
                        _tableView.bounds.size.height,
                        (long)(section >= 0 && section < [_tableView numberOfSections]
                                   ? [_tableView numberOfRowsInSection:section]
                                   : 0),
                        configurationsY,
                        subscriptionsY,
                        _connectBtn.bounds.size.width,
                        _connectBtn.bounds.size.height,
                        [_connectBtn.titleLabel.font pointSize]];
    VCRecordAppEvent(@"layout", action, detail);
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (NSString *)safeTrim:(NSString *)s {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)decodedFragmentFromURI:(NSString *)uri {
    NSRange hash = [uri rangeOfString:@"#" options:NSBackwardsSearch];
    if (hash.location == NSNotFound) return nil;
    NSString *frag = [uri substringFromIndex:(hash.location + 1)];
    NSString *decoded = [frag stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (decoded) frag = decoded;
    frag = [self safeTrim:frag];
    return [frag length] > 0 ? frag : nil;
}

- (NSString *)hostFromVLESSURI:(NSString *)uri {
    NSRange at = [uri rangeOfString:@"@"];
    if (at.location == NSNotFound) return @"vless";

    NSUInteger start = at.location + 1;
    NSUInteger i = start;
    while (i < [uri length]) {
        unichar c = [uri characterAtIndex:i];
        if (c == ':' || c == '?' || c == '/' || c == '#') break;
        i++;
    }
    if (i <= start) return @"vless";
    return [uri substringWithRange:NSMakeRange(start, i - start)];
}

- (NSString *)schemeFromURIString:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return @"vless";

    NSRange sep = [uri rangeOfString:@"://"];
    if (sep.location == NSNotFound || sep.location == 0) return @"vless";

    NSString *scheme = [self safeTrim:[uri substringToIndex:sep.location]];
    if ([scheme length] == 0) return @"vless";
    return [scheme lowercaseString];
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

- (NSString *)hostFromConfigURI:(NSString *)uri {
    NSURL *u = [NSURL URLWithString:uri];
    NSString *host = [self safeTrim:[u host]];
    if ([host length] > 0) return host;

    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) {
        NSString *parsedHost = nil;
        if ([self parseSOCKS5Host:&parsedHost port:NULL fromURI:uri] && [parsedHost length] > 0) {
            return parsedHost;
        }
        return @"socks5";
    }

    return [self hostFromVLESSURI:uri];
}

- (NSString *)displayNameForURI:(NSString *)uri index:(NSInteger)index {
    NSString *name = [self decodedFragmentFromURI:uri];
    if (name) return name;

    NSString *host = [self hostFromConfigURI:uri];
    return [NSString stringWithFormat:@"Config %ld (%@)", (long)(index + 1), host];
}

- (NSString *)displayNameForSubscriptionURI:(NSString *)uri
                                      index:(NSInteger)index
                               subscription:(NSDictionary *)subscription {
    if (!SubscriptionDictionaryIsHappEncrypted(subscription)) {
        return [self displayNameForURI:uri index:index];
    }

    NSString *name = [self decodedFragmentFromURI:uri];
    return [name length] > 0 ? name : [NSString stringWithFormat:@"Config %ld", (long)(index + 1)];
}

- (NSString *)hostFromURLString:(NSString *)urlString {
    NSURL *u = [NSURL URLWithString:urlString];
    NSString *h = [u host];
    if (!h || [h length] == 0) return @"subscription";
    return h;
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
    if (timestamp == 0) return @"no expiry";

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestamp];
    if (!date) return nil;

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setDateFormat:@"dd.MM.yyyy"];
    NSString *formatted = [formatter stringFromDate:date];
    return ([formatted length] > 0) ? [NSString stringWithFormat:@"until %@", formatted] : nil;
}

- (NSString *)subscriptionDetailTailFromDictionary:(NSDictionary *)sub {
    NSMutableArray *parts = [NSMutableArray array];
    NSString *traffic = [self subscriptionTrafficTextFromDictionary:sub];
    NSString *expiry = [self subscriptionExpiryTextFromDictionary:sub];
    if ([traffic length] > 0) [parts addObject:traffic];
    if ([expiry length] > 0) [parts addObject:expiry];
    return [parts componentsJoinedByString:@" • "];
}

- (NSString *)transportTypeFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"tcp";

    NSString *transport = [self queryValueForURLString:uri key:@"type"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"transport"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"network"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"net"];

    transport = [self safeTrim:transport];
    if ([transport length] == 0) return @"tcp";
    return [transport lowercaseString];
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

- (NSString *)subscriptionNameFromURLString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        return @"subscription";
    }

    NSArray *queryKeys = [NSArray arrayWithObjects:@"profile-title", @"title", @"name", @"subname", @"tag", @"remark", nil];
    for (NSString *key in queryKeys) {
        NSString *value = [self queryValueForURLString:urlString key:key];
        if ([value length] > 0) return value;
    }

    return [self hostFromURLString:urlString];
}

- (BOOL)isLikelyLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trim = [self safeTrim:text];
    if ([trim length] == 0) return NO;

    NSString *lower = [trim lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"vless://"] || [lower hasPrefix:@"socks5://"] || [lower hasPrefix:@"happ://"]) return YES;
    if ([trim rangeOfString:@"/"].location != NSNotFound) return YES;
    if ([trim rangeOfString:@"."].location != NSNotFound) return YES;
    if ([trim rangeOfString:@":"].location != NSNotFound) return YES;
    return NO;
}

- (NSString *)maskedLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *trim = [self safeTrim:text];
    NSUInteger len = [trim length];
    if (len == 0) return @"";

    if (!_stealthModeEnabled || ![self isLikelyLinkText:trim]) {
        return trim;
    }
    return kHiddenLinkText;
}

- (BOOL)isSubscriptionURL:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
}

- (BOOL)isVLESSURI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"vless://"];
}

- (BOOL)isSOCKS5URI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"socks5://"];
}

- (BOOL)isDirectConfigURI:(NSString *)s {
    return [self isVLESSURI:s] || [self isSOCKS5URI:s];
}

- (void)saveMainState {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *lastSelection = nil;
    if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        lastSelection = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"config", @"kind",
                         [NSNumber numberWithInteger:_selectedConfigIndex], @"index",
                         nil];
    } else if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        lastSelection = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"subscription", @"kind",
                         [NSNumber numberWithInteger:_selectedSubIndex], @"subscription_index",
                         [NSNumber numberWithInteger:_selectedSubItemIndex], @"item_index",
                         nil];
    }
    if (lastSelection) [ud setObject:lastSelection forKey:kDefaultsLastSelectionKey];
    else [ud removeObjectForKey:kDefaultsLastSelectionKey];
    [ud setBool:_configurationsSectionExpanded forKey:kDefaultsConfigurationsExpandedKey];
    [ud setBool:_subscriptionsSectionExpanded forKey:kDefaultsSubscriptionsExpandedKey];
    NSInteger expandedSubscription = _expandedSubscription;
    if (_reorderingSection == 1 && _subscriptionToReexpandAfterReorder) {
        NSUInteger index = [_subscriptions indexOfObjectIdenticalTo:_subscriptionToReexpandAfterReorder];
        expandedSubscription = (index == NSNotFound) ? -1 : (NSInteger)index;
    }
    [ud setInteger:expandedSubscription forKey:kDefaultsExpandedSubscriptionKey];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushMainStateDefaults)
                                               object:nil];
    [self performSelector:@selector(flushMainStateDefaults) withObject:nil afterDelay:0.5];
}

- (void)flushMainStateDefaults {
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveData {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL storeSaved = gVCSecureStoreWritable &&
        VCSaveProtectedConfigurationData(_configs, _subscriptions);
    if (storeSaved) {
        [ud removeObjectForKey:kDefaultsConfigsKey];
        [ud removeObjectForKey:kDefaultsSubsKey];
    }
    VCRecordAppEvent(@"storage",
                     storeSaved ? @"Configuration store saved" : @"Configuration store save failed",
                     [NSString stringWithFormat:@"configs=%lu subscriptions=%lu writable=%d",
                      (unsigned long)[_configs count],
                      (unsigned long)[_subscriptions count],
                      gVCSecureStoreWritable ? 1 : 0]);
    [ud setBool:_autoUpdateSubscriptions forKey:kDefaultsAutoUpdateSubsKey];
    [ud setBool:_preserveCustomSubscriptionNames forKey:kDefaultsPreserveCustomSubscriptionNamesKey];
    [ud setBool:_stealthModeEnabled forKey:kDefaultsStealthModeKey];
    [ud setBool:_darkThemeEnabled forKey:kDefaultsDarkThemeKey];
    [ud setBool:_automaticUpdateChecksEnabled forKey:kDefaultsAutomaticUpdateChecksKey];
    [self saveMainState];
    [self updateMainEmptyState];
    [self updateStickyMainSectionHeader];
}

- (void)loadData {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL secureFileExists = NO;
    NSDictionary *protectedData = VCLoadProtectedConfigurationData(&secureFileExists);
    NSArray *legacyConfigs = [ud objectForKey:kDefaultsConfigsKey];
    NSArray *legacySubscriptions = [ud objectForKey:kDefaultsSubsKey];
    NSArray *cfg = [protectedData objectForKey:@"configs"];
    NSArray *subs = [protectedData objectForKey:@"subscriptions"];
    if (![protectedData isKindOfClass:[NSDictionary class]]) {
        cfg = [legacyConfigs isKindOfClass:[NSArray class]] ? legacyConfigs : nil;
        subs = [legacySubscriptions isKindOfClass:[NSArray class]] ? legacySubscriptions : nil;
        if (secureFileExists && cfg == nil && subs == nil) gVCSecureStoreWritable = NO;
    }

    if ([cfg isKindOfClass:[NSArray class]]) {
        _configs = [[NSMutableArray alloc] initWithArray:cfg];
    } else {
        _configs = [[NSMutableArray alloc] init];
    }

    if ([subs isKindOfClass:[NSArray class]]) {
        _subscriptions = [[NSMutableArray alloc] initWithArray:subs];
    } else {
        _subscriptions = [[NSMutableArray alloc] init];
    }

    if ([protectedData isKindOfClass:[NSDictionary class]] &&
        ([legacyConfigs isKindOfClass:[NSArray class]] || [legacySubscriptions isKindOfClass:[NSArray class]])) {
        [ud removeObjectForKey:kDefaultsConfigsKey];
        [ud removeObjectForKey:kDefaultsSubsKey];
        [ud synchronize];
    } else if (![protectedData isKindOfClass:[NSDictionary class]] &&
        ([legacyConfigs isKindOfClass:[NSArray class]] || [legacySubscriptions isKindOfClass:[NSArray class]]) &&
        VCSaveProtectedConfigurationData(_configs, _subscriptions)) {
        [ud removeObjectForKey:kDefaultsConfigsKey];
        [ud removeObjectForKey:kDefaultsSubsKey];
        [ud synchronize];
    }

    if ([ud objectForKey:kDefaultsAutoUpdateSubsKey] == nil) {
        _autoUpdateSubscriptions = YES;
    } else {
        _autoUpdateSubscriptions = [ud boolForKey:kDefaultsAutoUpdateSubsKey];
    }

    _preserveCustomSubscriptionNames = [ud boolForKey:kDefaultsPreserveCustomSubscriptionNamesKey];

    if ([ud objectForKey:kDefaultsStealthModeKey] == nil) {
        _stealthModeEnabled = NO;
    } else {
        _stealthModeEnabled = [ud boolForKey:kDefaultsStealthModeKey];
    }

    _darkThemeEnabled = [ud boolForKey:kDefaultsDarkThemeKey];

    if ([ud objectForKey:kDefaultsAutomaticUpdateChecksKey] == nil) {
        _automaticUpdateChecksEnabled = YES;
    } else {
        _automaticUpdateChecksEnabled = [ud boolForKey:kDefaultsAutomaticUpdateChecksKey];
    }

    _selectedConfigIndex = -1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    NSNumber *savedExpandedValue = [ud objectForKey:kDefaultsExpandedSubscriptionKey];
    NSInteger savedExpandedSubscription = [savedExpandedValue isKindOfClass:[NSNumber class]]
        ? [savedExpandedValue integerValue] : -1;
    _expandedSubscription = (savedExpandedSubscription >= 0 &&
                             savedExpandedSubscription < (NSInteger)[_subscriptions count])
        ? savedExpandedSubscription : -1;
    _updatingSubscriptionIndex = -1;
    _stickySectionHeaderSection = -1;
    _reorderingSection = -1;
    _configurationsSectionExpanded = [ud boolForKey:kDefaultsConfigurationsExpandedKey];
    _subscriptionsSectionExpanded = [ud boolForKey:kDefaultsSubscriptionsExpandedKey];

    NSDictionary *lastSelection = [ud objectForKey:kDefaultsLastSelectionKey];
    NSString *selectionKind = [lastSelection isKindOfClass:[NSDictionary class]]
        ? [lastSelection objectForKey:@"kind"] : nil;
    if ([selectionKind isEqualToString:@"config"]) {
        NSInteger index = [[lastSelection objectForKey:@"index"] integerValue];
        if (index >= 0 && index < (NSInteger)[_configs count]) _selectedConfigIndex = index;
    } else if ([selectionKind isEqualToString:@"subscription"]) {
        NSInteger subIndex = [[lastSelection objectForKey:@"subscription_index"] integerValue];
        if (subIndex >= 0 && subIndex < (NSInteger)[_subscriptions count]) {
            NSDictionary *subscription = [_subscriptions objectAtIndex:subIndex];
            NSArray *items = [subscription objectForKey:@"items"];
            if (![items isKindOfClass:[NSArray class]]) items = [NSArray array];
            NSInteger itemIndex = [[lastSelection objectForKey:@"item_index"] integerValue];
            _selectedSubIndex = subIndex;
            _selectedSubItemIndex = ([items count] == 0) ? -1
                : ((itemIndex >= 0 && itemIndex < (NSInteger)[items count]) ? itemIndex : 0);
        }
    }
    if (_selectedConfigIndex < 0 && _selectedSubIndex < 0 && [_configs count] > 0) {
        _selectedConfigIndex = 0;
    }
    VCRecordAppEvent(@"storage",
                     @"Configuration store loaded",
                     [NSString stringWithFormat:@"configs=%lu subscriptions=%lu secure=%d writable=%d",
                      (unsigned long)[_configs count],
                      (unsigned long)[_subscriptions count],
                      [protectedData isKindOfClass:[NSDictionary class]] ? 1 : 0,
                      gVCSecureStoreWritable ? 1 : 0]);
}

- (NSArray *)subscriptionItemsAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return [NSArray array];
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return [NSArray array];
    return items;
}

- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return nil;
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    NSString *url = [sub objectForKey:@"url"];
    if ([url isKindOfClass:[NSString class]] && [url length] > 0) {
        return [@"url:" stringByAppendingString:url];
    }
    return [NSString stringWithFormat:@"object:%p", (void *)sub];
}

- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return NO;
    NSSet *pending = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
    return [pending count] > 0;
}

- (NSInteger)subscriptionSectionRowCount {
    NSInteger rows = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        rows += 1;
        if (i == _expandedSubscription) {
            rows += (NSInteger)[[self subscriptionItemsAtIndex:i] count];
        }
    }
    return rows;
}

- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)subIndex itemIndex:(NSInteger *)itemIndex isHeader:(BOOL *)isHeader {
    NSInteger cursor = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        if (row == cursor) {
            if (subIndex) *subIndex = i;
            if (itemIndex) *itemIndex = -1;
            if (isHeader) *isHeader = YES;
            return YES;
        }
        cursor += 1;

        if (i == _expandedSubscription) {
            NSArray *items = [self subscriptionItemsAtIndex:i];
            NSInteger cnt = (NSInteger)[items count];
            if (row < cursor + cnt) {
                if (subIndex) *subIndex = i;
                if (itemIndex) *itemIndex = row - cursor;
                if (isHeader) *isHeader = NO;
                return YES;
            }
            cursor += cnt;
        }
    }
    return NO;
}

- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return -1;

    NSInteger row = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        if (i == subIdx) {
            return row;
        }
        row += 1;
        if (i == _expandedSubscription) {
            row += (NSInteger)[[self subscriptionItemsAtIndex:i] count];
        }
    }

    return -1;
}

- (void)setUpdatingSubscriptionIndex:(NSInteger)subIdx {
    if (_updatingSubscriptionIndex == subIdx) return;

    NSInteger oldIdx = _updatingSubscriptionIndex;
    _updatingSubscriptionIndex = subIdx;

    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSInteger oldRow = [self rowForSubscriptionHeaderAtIndex:oldIdx];
    if (oldRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:oldRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            cell.accessoryView = [self accessorySubscriptionHeaderAtIndex:oldIdx
                                                                   expanded:(_expandedSubscription == oldIdx)
                                                                    loading:NO];
        }
    }

    NSInteger newRow = [self rowForSubscriptionHeaderAtIndex:subIdx];
    if (newRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:newRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            cell.accessoryView = [self accessorySubscriptionHeaderAtIndex:subIdx
                                                                   expanded:(_expandedSubscription == subIdx)
                                                                    loading:YES];
        }
    }
}

- (void)normalizeSelection {
    if (_selectedConfigIndex >= (NSInteger)[_configs count]) {
        _selectedConfigIndex = -1;
    }

    if (_selectedSubIndex >= (NSInteger)[_subscriptions count]) {
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
    }

    if (_selectedSubIndex >= 0) {
        NSArray *items = [self subscriptionItemsAtIndex:_selectedSubIndex];
        if ([items count] == 0) {
            _selectedSubItemIndex = -1;
        } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[items count]) {
            _selectedSubItemIndex = 0;
        }
    }
}

- (NSString *)sanitizeDaemonText:(NSString *)text {
    if (!text) return @"";
    NSString *s = [text stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)formatDuration:(NSTimeInterval)seconds {
    NSInteger total = (NSInteger)(seconds >= 0 ? seconds : 0);
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)h, (long)m, (long)s];
}

- (void)refreshStatusText {
    NSString *base = _statusBaseText ? _statusBaseText : @"";
    if ([base isEqualToString:@"Ready"] && [_availableUpdateVersion length] > 0) {
        _statusLabel.text = [NSString stringWithFormat:@"Ready (New version available: %@)",
                            _availableUpdateVersion];
    } else {
        _statusLabel.text = base;
    }
}

- (void)refreshUptimeText {
    if (_connected && _connectedSince > 0) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - _connectedSince;
        _uptimeLabel.text = [self formatDuration:delta];
    } else {
        _uptimeLabel.text = @"00:00:00";
    }
}

- (void)startUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;

    _connectedSince = [[NSDate date] timeIntervalSince1970];
    [self refreshUptimeText];
    _uptimeTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(uptimeTick:)
                                                   userInfo:nil
                                                    repeats:YES] retain];
}

- (void)stopUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;
    _connectedSince = 0;
    [self refreshUptimeText];
}

- (void)uptimeTick:(NSTimer *)timer {
    (void)timer;
    [self refreshUptimeText];
    [self reconcileConnectionStateWithDaemon];
}

- (void)reconcileConnectionStateWithDaemon {
    if (!_connected || _reconnectInProgress || _daemonStatusCheckInFlight) return;

    _daemonStatusCheckInFlight = YES;
    NSTimeInterval expectedConnectedSince = _connectedSince;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *response = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
        BOOL disconnected = [response hasPrefix:@"OK disconnected"];

        dispatch_async(dispatch_get_main_queue(), ^{
            _daemonStatusCheckInFlight = NO;
            if (!disconnected || !_connected ||
                _connectedSince != expectedConnectedSince) {
                return;
            }

            _connected = NO;
            _connectedWithProtectedLogs = NO;
            [self stopUptimeTimer];
            [self updateConnectButton];
            [self showStatus:@"Connection lost" ok:NO];
            VCRecordAppEvent(@"connection", @"Daemon reported connection lost", nil);
        });
        [pool drain];
    });
}

- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification {
    (void)notification;
    [self reconcileConnectionStateWithDaemon];
}

- (void)showStatus:(NSString *)text ok:(BOOL)ok {
    [_statusBaseText release];
    _statusBaseText = [[self sanitizeDaemonText:text] copy];
    _statusOK = ok;
    _statusLabel.textColor = ok ? VCSuccessColor() : VCErrorColor();
    [self refreshStatusText];
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

- (NSString *)endpointFromConfigURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return @"server";

    NSURL *u = [NSURL URLWithString:uri];
    NSString *host = [self safeTrim:[u host]];
    NSNumber *portNum = [u port];
    NSInteger port = [portNum respondsToSelector:@selector(integerValue)] ? [portNum integerValue] : 0;

    if ([host length] > 0) {
        if (port <= 0 || port > 65535) {
            NSString *scheme = [self schemeFromURIString:uri];
            if ([scheme isEqualToString:@"vless"]) {
                port = 443;
            } else if ([scheme isEqualToString:@"socks5"]) {
                port = 1080;
            }
        }

        if (port > 0 && port <= 65535) {
            return [NSString stringWithFormat:@"%@:%ld", host, (long)port];
        }
        return host;
    }

    NSString *parsedHost = nil;
    uint16_t parsedPort = 443;
    if ([self parseVLESSHost:&parsedHost port:&parsedPort fromURI:uri] && [parsedHost length] > 0) {
        return [NSString stringWithFormat:@"%@:%u", parsedHost, (unsigned int)parsedPort];
    }

    if ([self parseSOCKS5Host:&parsedHost port:&parsedPort fromURI:uri] && [parsedHost length] > 0) {
        return [NSString stringWithFormat:@"%@:%u", parsedHost, (unsigned int)parsedPort];
    }

    NSString *fallbackHost = [self hostFromVLESSURI:uri];
    if ([fallbackHost length] > 0) return fallbackHost;
    return @"server";
}

- (NSString *)configSecondaryTextFromURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *endpoint = [self configEndpointTextFromURI:uri];
    if ([prefix length] == 0) return endpoint;
    if ([endpoint length] == 0) return prefix;
    return [NSString stringWithFormat:@"%@ %@", prefix, endpoint];
}

- (NSString *)configPrefixTextFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"[socks5]";

    NSString *transport = [self transportTypeFromURI:uri];
    NSString *security = [self securityTypeFromURI:uri];
    return [NSString stringWithFormat:@"[%@/%@/%@]", scheme, transport, security];
}

- (NSString *)configEndpointTextFromURI:(NSString *)uri {
    NSString *endpoint = [self endpointFromConfigURI:uri];
    return [self maskedLinkText:endpoint];
}

- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri {
    NSString *queryReason = [self configURIQueryValidationReason:uri];
    if ([queryReason length] > 0) return queryReason;

    NSString *scheme = [[self schemeFromURIString:uri] lowercaseString];
    NSString *transport = [[self transportTypeFromURI:uri] lowercaseString];
    NSString *security = [[self securityTypeFromURI:uri] lowercaseString];

    if ([scheme isEqualToString:@"socks5"]) {
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

    if ([transport isEqualToString:@"tcp"] && [security isEqualToString:@"none"]) {
        NSString *flow = [self realityFlowFromURI:uri];
        if ([flow length] > 0) {
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

- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri {
    return ([self unsupportedConfigReasonForURI:uri] == nil);
}

- (UIColor *)configPrefixColorForURI:(NSString *)uri {
    if ([self isSupportedConfigTupleForURI:uri]) {
        return VCSecondaryTextColor();
    }
    return VCErrorColor();
}

- (NSString *)unsupportedConfigStatusTextForURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    if (![prefix isKindOfClass:[NSString class]] || [prefix length] == 0) {
        prefix = @"[unknown]";
    }
    NSString *reason = [self unsupportedConfigReasonForURI:uri];
    if ([reason length] > 0) {
        return [NSString stringWithFormat:@"Error: unsupported config %@ (%@)",
                prefix,
                reason];
    }
    return [NSString stringWithFormat:@"Error: unsupported config %@",
            prefix];
}

- (UIView *)mainDetailContainerForCell:(UITableViewCell *)cell createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    UIView *container = [cell.contentView viewWithTag:kVCMainDetailContainerTag];
    if (!container && createIfNeeded) {
        container = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        container.tag = kVCMainDetailContainerTag;
        container.backgroundColor = [UIColor clearColor];
        container.userInteractionEnabled = NO;
        container.clipsToBounds = YES;
        [cell.contentView addSubview:container];
    }
    return container;
}

- (UILabel *)mainDetailPrefixLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    UILabel *label = (UILabel *)[container viewWithTag:kVCMainDetailPrefixTag];
    if (!label && createIfNeeded) {
        label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
        label.tag = kVCMainDetailPrefixTag;
        label.backgroundColor = [UIColor clearColor];
        label.numberOfLines = 1;
        label.lineBreakMode = NSLineBreakByClipping;
        [container addSubview:label];
    }
    return label;
}

- (VCMarqueeLabel *)mainDetailTailMarqueeForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[container viewWithTag:kVCMainDetailTailTag];
    if (!marquee && createIfNeeded) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = kVCMainDetailTailTag;
        marquee.backgroundColor = [UIColor clearColor];
        marquee.userInteractionEnabled = NO;
        [container addSubview:marquee];
    }
    return marquee;
}

- (CGRect)mainDetailContentFrameForCell:(UITableViewCell *)cell {
    if (!cell) return CGRectZero;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    CGRect contentBounds = cell.contentView.bounds;
    CGFloat contentW = CGRectGetWidth(contentBounds);
    CGFloat contentH = CGRectGetHeight(contentBounds);
    if (contentW < 1.0f || contentH < 1.0f) return CGRectZero;

    CGRect titleFrame = cell.textLabel.frame;
    CGRect legacyDetailFrame = cell.detailTextLabel.frame;

    CGFloat left = titleFrame.origin.x;
    if (left < 6.0f) {
        left = legacyDetailFrame.origin.x;
    }
    if (left < 6.0f) {
        left = 10.0f;
    }

    CGFloat top = CGRectGetMaxY(titleFrame) + 1.0f;
    if (top < 1.0f || top > contentH - 6.0f) {
        top = legacyDetailFrame.origin.y;
    }
    if (top < 1.0f) {
        top = 24.0f;
    }

    CGFloat right = contentW - 10.0f;
    if (cell.accessoryView && !cell.accessoryView.hidden) {
        CGRect accessoryFrame = cell.accessoryView.frame;
        if (CGRectGetWidth(accessoryFrame) > 1.0f && CGRectGetMinX(accessoryFrame) > 1.0f) {
            right = MIN(right, CGRectGetMinX(accessoryFrame) - 8.0f);
        }
    }
    if (right < left + 12.0f) {
        right = left + 12.0f;
    }

    CGFloat height = contentH - top - 2.0f;
    if (legacyDetailFrame.size.height > 0.0f) {
        height = MAX(height, legacyDetailFrame.size.height);
    }
    if ([cell isKindOfClass:[VCMainListCell class]] &&
        [(VCMainListCell *)cell usesConfigurationItemLayout]) {
        top += 2.0f;
        height = 14.0f;
    }
    if (top + height > contentH) {
        height = contentH - top;
    }
    if (height < 10.0f) {
        height = 14.0f;
        if (top + height > contentH) {
            top = MAX(0.0f, contentH - height);
        }
    }

    return CGRectMake(left, top, right - left, height);
}

- (void)clearDetailMarqueeForCell:(UITableViewCell *)cell {
    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:NO];
    if (!container) return;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:NO];
    VCMarqueeLabel *tailMarquee = [self mainDetailTailMarqueeForContainer:container createIfNeeded:NO];
    if (tailMarquee) {
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;
    }
    if (prefixLabel) {
        prefixLabel.text = @"";
        prefixLabel.hidden = YES;
    }
    container.hidden = YES;
}

- (void)applyDetailPrefix:(NSString *)prefix
              prefixColor:(UIColor *)prefixColor
              marqueeTail:(NSString *)tail
                   toCell:(UITableViewCell *)cell {
    if (!cell) return;

    NSString *prefixText = ([prefix isKindOfClass:[NSString class]] ? prefix : @"");
    NSString *tailText = ([tail isKindOfClass:[NSString class]] ? tail : @"");
    UIColor *effectivePrefixColor = [prefixColor isKindOfClass:[UIColor class]] ? prefixColor : VCSecondaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();
    UIFont *detailFont = cell.detailTextLabel.font;
    if (!detailFont) detailFont = [UIFont systemFontOfSize:11.0f];

    // Keep subtitle geometry stable: non-empty detail preserves UIKit two-line layout metrics.
    BOOL hasDetail = ([prefixText length] > 0 || [tailText length] > 0);
    cell.detailTextLabel.text = hasDetail ? @" " : @"";
    cell.detailTextLabel.textColor = [UIColor clearColor];

    if ([prefixText length] == 0 && [tailText length] == 0) {
        [self clearDetailMarqueeForCell:cell];
        return;
    }

    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:YES];
    CGRect containerFrame = [self mainDetailContentFrameForCell:cell];
    if (CGRectGetWidth(containerFrame) < 8.0f || CGRectGetHeight(containerFrame) < 8.0f) {
        [self clearDetailMarqueeForCell:cell];
        return;
    }

    container.hidden = NO;
    container.frame = containerFrame;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:YES];
    VCMarqueeLabel *tailMarquee = [self mainDetailTailMarqueeForContainer:container createIfNeeded:YES];
    CGFloat lineH = CGRectGetHeight(container.bounds);
    CGFloat lineW = CGRectGetWidth(container.bounds);

    prefixLabel.font = detailFont;
    prefixLabel.textColor = effectivePrefixColor;
    prefixLabel.backgroundColor = [UIColor clearColor];

    tailMarquee.font = detailFont;
    tailMarquee.textColor = detailColor;
    tailMarquee.backgroundColor = [UIColor clearColor];

    if ([tailText length] == 0) {
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;

        prefixLabel.hidden = NO;
        prefixLabel.text = prefixText;
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        return;
    }

    if ([prefixText length] == 0) {
        prefixLabel.hidden = YES;
        prefixLabel.text = @"";
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, 0.0f, lineH);

        tailMarquee.hidden = NO;
        tailMarquee.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        tailMarquee.text = tailText;
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize prefixSize = [prefixText sizeWithFont:detailFont];
#pragma clang diagnostic pop

    CGFloat prefixWidth = ceilf(prefixSize.width);
    CGFloat maxPrefixWidth = lineW - 16.0f;
    if (maxPrefixWidth < 8.0f) maxPrefixWidth = lineW;
    if (prefixWidth > maxPrefixWidth) prefixWidth = maxPrefixWidth;
    if (prefixWidth < 0.0f) prefixWidth = 0.0f;

    CGFloat tailX = prefixWidth + kVCDetailMarqueeGap;
    CGFloat tailWidth = lineW - tailX;
    if (tailWidth < 8.0f) {
        prefixLabel.hidden = NO;
        prefixLabel.text = [NSString stringWithFormat:@"%@ %@", prefixText, tailText];
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;
        return;
    }

    prefixLabel.hidden = NO;
    prefixLabel.text = prefixText;
    prefixLabel.frame = CGRectMake(0.0f, 0.0f, prefixWidth, lineH);

    tailMarquee.hidden = NO;
    tailMarquee.frame = CGRectMake(tailX, 0.0f, tailWidth, lineH);
    tailMarquee.text = tailText;
}

- (void)applyDetailPrefix:(NSString *)prefix marqueeTail:(NSString *)tail toCell:(UITableViewCell *)cell {
    [self applyDetailPrefix:prefix
                prefixColor:VCSecondaryTextColor()
                marqueeTail:tail
                     toCell:cell];
}

- (BOOL)isXHTTPTransportURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;

    NSRange q = [uri rangeOfString:@"?"];
    if (q.location == NSNotFound) return NO;

    NSUInteger start = q.location + 1;
    NSUInteger end = [uri length];
    NSRange hash = [uri rangeOfString:@"#" options:0 range:NSMakeRange(start, end - start)];
    if (hash.location != NSNotFound) {
        end = hash.location;
    }
    if (end <= start) return NO;

    NSString *query = [uri substringWithRange:NSMakeRange(start, end - start)];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        if (![pair isKindOfClass:[NSString class]] || [pair length] == 0) continue;

        NSRange eq = [pair rangeOfString:@"="];
        NSString *k = (eq.location == NSNotFound) ? pair : [pair substringToIndex:eq.location];
        NSString *v = (eq.location == NSNotFound) ? @"" : [pair substringFromIndex:(eq.location + 1)];

        k = [k lowercaseString];
        NSString *decoded = [v stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (decoded) v = decoded;
        v = [v lowercaseString];

        if ([k isEqualToString:@"type"] && ([v isEqualToString:@"xhttp"] || [v isEqualToString:@"splithttp"])) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)xhttpPinKeyFromURI:(NSString *)uri {
    NSString *host = nil;
    uint16_t port = 443;
    if (![self parseVLESSHost:&host port:&port fromURI:uri]) return nil;
    NSString *trimmedHost = [[self safeTrim:host] lowercaseString];
    if (![trimmedHost isKindOfClass:[NSString class]] || [trimmedHost length] == 0) return nil;
    return [NSString stringWithFormat:@"%@:%u", trimmedHost, (unsigned int)port];
}

- (NSString *)xhttpTOFUPinMismatchStatusForURI:(NSString *)uri {
    NSString *tail = ReadDaemonLog(1, 12288);
    if (![tail isKindOfClass:[NSString class]] || [tail length] == 0) return nil;

    NSString *lowerTail = [tail lowercaseString];
    if ([lowerTail rangeOfString:@"tofu pin mismatch"].location == NSNotFound) return nil;

    NSString *pinKey = [self xhttpPinKeyFromURI:uri];
    if ([pinKey length] > 0) {
        NSString *needle = [NSString stringWithFormat:@"tofu pin mismatch for %@", pinKey];
        if ([lowerTail rangeOfString:needle].location == NSNotFound &&
            [lowerTail rangeOfString:pinKey].location == NSNotFound) {
            return nil;
        }
        return [NSString stringWithFormat:@"Error: TOFU pin mismatch for %@ (clear old entry in xhttp-pins.txt)", pinKey];
    }

    return @"Error: TOFU pin mismatch (clear old entry in xhttp-pins.txt)";
}

- (NSInteger)socksPortFromDaemonStatusText:(NSString *)statusText {
    if (![statusText isKindOfClass:[NSString class]] || [statusText length] == 0) return -1;
    NSRange marker = [statusText rangeOfString:@"socks="];
    if (marker.location == NSNotFound) return -1;

    NSUInteger start = marker.location + marker.length;
    NSUInteger end = start;
    while (end < [statusText length]) {
        unichar c = [statusText characterAtIndex:end];
        if (c < '0' || c > '9') break;
        end++;
    }
    if (end <= start) return -1;

    NSInteger p = [[statusText substringWithRange:NSMakeRange(start, end - start)] integerValue];
    if (p <= 0 || p > 65535) return -1;
    return p;
}

- (NSInteger)currentDaemonSocksPort {
    NSString *status = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
    if (![status hasPrefix:@"OK connected"]) return -1;
    return [self socksPortFromDaemonStatusText:status];
}

- (void)xhttpConnectHealthCheckWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];

    BOOL ok = NO;
    for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        NSInteger socksPort = [self currentDaemonSocksPort];
        if (socksPort > 0 && socksPort <= 65535) {
            int ms = 0;
            if (TunnelConnectOnceMs((uint16_t)socksPort, 3500, &ms) == 0) {
                ok = YES;
                break;
            }
        }
        usleep(250 * 1000);
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:3];
    [out setObject:(ok ? @"1" : @"0") forKey:@"ok"];
    if (![uri isKindOfClass:[NSString class]]) uri = @"";
    [out setObject:uri forKey:@"uri"];

    if (!ok) {
        NSString *reason = [self xhttpTOFUPinMismatchStatusForURI:uri];
        if (![reason isKindOfClass:[NSString class]] || [reason length] == 0) {
            reason = @"Error: xhttp tunnel failed health-check";
        }
        [out setObject:reason forKey:@"reason"];
    }

    [self performSelectorOnMainThread:@selector(xhttpConnectHealthCheckResultOnMain:) withObject:out waitUntilDone:NO];
    [pool drain];
}

- (void)xhttpConnectHealthCheckResultOnMain:(NSDictionary *)payload {
    BOOL ok = [[payload objectForKey:@"ok"] isEqualToString:@"1"];
    if (ok) return;
    if (!_connected || _reconnectInProgress || [_pendingReconnectURI length]) return;

    NSString *reason = [payload objectForKey:@"reason"];
    if ([reason rangeOfString:@"TOFU pin mismatch"].location == NSNotFound) {
        return;
    }

    NSString *discResp = [self sanitizeDaemonText:SendCommand(@"DISCONNECT\n")];
    if (![discResp hasPrefix:@"OK"]) {
        [self showStatus:[NSString stringWithFormat:@"%@ (disconnect failed: %@)", reason, discResp] ok:NO];
        return;
    }
    _connected = NO;
    _connectedWithProtectedLogs = NO;
    [self stopUptimeTimer];
    [self updateConnectButton];
    [self showStatus:reason ok:NO];
}

- (void)scheduleXHTTPConnectHealthCheckForURI:(NSString *)uri {
    if (![self isXHTTPTransportURI:uri]) return;
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             (uri ? uri : @""), @"uri",
                             nil];
    [NSThread detachNewThreadSelector:@selector(xhttpConnectHealthCheckWorker:) toTarget:self withObject:payload];
}

- (void)pingWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];
    VCPingType pingType = (VCPingType)[[payload objectForKey:@"type"] integerValue];
    NSString *host = nil;
    uint16_t port = 0;
    int latencyMs = -1;
    BOOL ok = NO;
    NSString *scheme = [self schemeFromURIString:uri];
    BOOL isSOCKS5Config = [scheme isEqualToString:@"socks5"];
    BOOL parsed = isSOCKS5Config
        ? [self parseSOCKS5Host:&host port:&port fromURI:uri]
        : [self parseVLESSHost:&host port:&port fromURI:uri];
    if (parsed) {
        int rc = -1;

        if (pingType == VCPingTypeProxyGET) {
            NSString *xrayVersion = VCActiveXrayVersion();
            rc = ProxyGetViaTempCoreMs([uri UTF8String], [xrayVersion UTF8String],
                                       5000, 2, &latencyMs);
        } else if (pingType == VCPingTypeTCP) {
            rc = ConnectLatencyBestOfNMs([host UTF8String], port, 3500, 2, &latencyMs);
        } else if (pingType == VCPingTypeICMP) {
            rc = ICMPLatencyBestOfNMs([host UTF8String], 3500, 2, &latencyMs);
        }
        ok = (rc == 0 && latencyMs >= 0);
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:5];
    [out setObject:([uri isKindOfClass:[NSString class]] ? uri : @"") forKey:@"uri"];
    [out setObject:[NSNumber numberWithBool:ok] forKey:@"ok"];
    NSString *batchIdentifier = [payload objectForKey:@"batch_identifier"];
    NSNumber *batchToken = [payload objectForKey:@"batch_token"];
    if (batchIdentifier && batchToken) {
        [out setObject:batchIdentifier forKey:@"batch_identifier"];
        [out setObject:batchToken forKey:@"batch_token"];
    }
    if (ok) {
        [out setObject:[NSNumber numberWithInt:latencyMs] forKey:@"ms"];
    }
    [self performSelectorOnMainThread:@selector(pingResultOnMain:) withObject:out waitUntilDone:NO];

    [pool drain];
}

- (void)pingResultOnMain:(NSDictionary *)payload {
    NSString *uri = [payload objectForKey:@"uri"];
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return;

    NSString *batchIdentifier = [payload objectForKey:@"batch_identifier"];
    NSNumber *batchToken = [payload objectForKey:@"batch_token"];
    if (batchIdentifier && batchToken) {
        NSNumber *currentToken = [_subscriptionPingTokenByIdentifier objectForKey:batchIdentifier];
        if (![currentToken isEqualToNumber:batchToken]) {
            return;
        }
    }
    if (!batchIdentifier) {
        [_standalonePingURIs removeObject:uri];
    }

    BOOL ok = [[payload objectForKey:@"ok"] boolValue];
    NSString *display = ok
        ? [NSString stringWithFormat:@"%d ms", [[payload objectForKey:@"ms"] intValue]]
        : kVCPingFailureValue;
    [_pingDisplayByURI setObject:display forKey:uri];
    if (!batchIdentifier) {
        VCRecordAppEvent(@"ping", @"Configuration ping finished",
                         ok ? [NSString stringWithFormat:@"success=1 latency_ms=%d", [[payload objectForKey:@"ms"] intValue]]
                            : @"success=0");
    }

    BOOL completedSubscriptionPing = NO;
    if (batchIdentifier) {
        NSMutableSet *pending = [_subscriptionPingPendingByIdentifier objectForKey:batchIdentifier];
        [pending removeObject:uri];
        if ([pending count] == 0) {
            [_subscriptionPingPendingByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingOperationsByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingTokenByIdentifier removeObjectForKey:batchIdentifier];
            completedSubscriptionPing = YES;
        }
    }

    [self refreshVisiblePingAccessoriesForURI:uri];
    if (completedSubscriptionPing) {
        VCRecordAppEvent(@"ping", @"Subscription ping batch finished", nil);
        [self refreshVisibleSubscriptionPingAccessories];
        [self refreshVisibleSubscriptionHeaderAccessories];
    }
}

- (NSOperation *)enqueuePingForURI:(NSString *)uri
                              type:(VCPingType)pingType
                          priority:(NSOperationQueuePriority)priority
                   batchIdentifier:(NSString *)batchIdentifier
                        batchToken:(NSNumber *)batchToken {
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    uri, @"uri",
                                    [NSNumber numberWithInteger:pingType], @"type",
                                    nil];
    if (batchIdentifier && batchToken) {
        [payload setObject:batchIdentifier forKey:@"batch_identifier"];
        [payload setObject:batchToken forKey:@"batch_token"];
    }
    NSInvocationOperation *operation = [[[NSInvocationOperation alloc]
        initWithTarget:self
              selector:@selector(pingWorker:)
                object:payload] autorelease];
    operation.queuePriority = priority;
    [_pingQueue addOperation:operation];
    return operation;
}

- (void)startPingForURI:(NSString *)uri type:(VCPingType)pingType {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return;
    if ([_standalonePingURIs containsObject:uri]) return;
    if ([[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) return;

    [_standalonePingURIs addObject:uri];
    VCRecordAppEvent(@"ping", @"Configuration ping started",
                     [NSString stringWithFormat:@"type=%ld", (long)pingType]);
    [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
    [self refreshVisiblePingAccessoriesForURI:uri];
    [self enqueuePingForURI:uri
                       type:pingType
                   priority:NSOperationQueuePriorityHigh
            batchIdentifier:nil
                 batchToken:nil];
}

- (void)pingButtonPressed:(UIButton *)sender {
    NSInteger tag = sender.tag;
    NSString *uri = nil;

    if (tag >= 10000 && tag < 20000) {
        NSInteger idx = tag - 10000;
        if (idx >= 0 && idx < (NSInteger)[_configs count]) {
            NSDictionary *cfg = [_configs objectAtIndex:idx];
            uri = [cfg objectForKey:@"uri"];
        }
    } else if (tag >= 20000) {
        NSInteger code = tag - 20000;
        NSInteger subIdx = code / 1000;
        NSInteger itemIdx = code % 1000;
        if ([self isSubscriptionPingInProgressAtIndex:subIdx]) return;
        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        if (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) {
            uri = [items objectAtIndex:itemIdx];
        }
    }

    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) {
        return;
    }
    if ([_standalonePingURIs containsObject:uri]) return;
    if ([[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) return;

    sender.enabled = NO;
    [self startPingForURI:uri type:VCSelectedPingType()];
}

- (void)startSubscriptionPingAtIndex:(NSInteger)subIdx {
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([items count] == 0 || [self isSubscriptionPingInProgressAtIndex:subIdx]) return;

    NSMutableArray *urisToPing = [NSMutableArray arrayWithCapacity:[items count]];
    NSMutableSet *seenURIs = [NSMutableSet setWithCapacity:[items count]];
    for (NSString *uri in items) {
        if (![uri isKindOfClass:[NSString class]] || [uri length] == 0 ||
            [seenURIs containsObject:uri]) {
            continue;
        }
        [seenURIs addObject:uri];
        [urisToPing addObject:uri];
    }
    if ([urisToPing count] == 0) return;

    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;
    [_subscriptionPingPendingByIdentifier setObject:[NSMutableSet setWithArray:urisToPing]
                                             forKey:identifier];

    _nextSubscriptionPingToken++;
    if (_nextSubscriptionPingToken == 0) _nextSubscriptionPingToken++;
    NSNumber *batchToken = [NSNumber numberWithUnsignedInteger:_nextSubscriptionPingToken];
    [_subscriptionPingTokenByIdentifier setObject:batchToken forKey:identifier];

    NSMutableDictionary *previousDisplay = [NSMutableDictionary dictionaryWithCapacity:[urisToPing count]];
    NSMutableArray *operations = [NSMutableArray arrayWithCapacity:[urisToPing count]];
    [_subscriptionPingPreviousDisplayByIdentifier setObject:previousDisplay forKey:identifier];
    [_subscriptionPingOperationsByIdentifier setObject:operations forKey:identifier];

    VCPingType pingType = VCSelectedPingType();
    VCRecordAppEvent(@"ping", @"Subscription ping batch started",
                     [NSString stringWithFormat:@"configs=%lu type=%ld",
                      (unsigned long)[urisToPing count], (long)pingType]);
    for (NSString *uri in urisToPing) {
        NSString *previous = [_pingDisplayByURI objectForKey:uri];
        if ([previous length] > 0 && ![previous isEqualToString:kVCPingLoadingValue]) {
            [previousDisplay setObject:previous forKey:uri];
        }
        [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
        NSOperation *operation = [self enqueuePingForURI:uri
                                                    type:pingType
                                                priority:NSOperationQueuePriorityNormal
                                         batchIdentifier:identifier
                                              batchToken:batchToken];
        if (operation) [operations addObject:operation];
    }
    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
}

- (BOOL)isURIInActiveSubscriptionPing:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    for (NSString *identifier in _subscriptionPingPendingByIdentifier) {
        NSSet *pending = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
        if ([pending containsObject:uri]) return YES;
    }
    return NO;
}

- (void)stopSubscriptionPingAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;

    NSArray *operations = [[_subscriptionPingOperationsByIdentifier objectForKey:identifier] copy];
    NSSet *pending = [[_subscriptionPingPendingByIdentifier objectForKey:identifier] copy];
    NSUInteger pendingCount = [pending count];
    NSDictionary *previousDisplay = [[_subscriptionPingPreviousDisplayByIdentifier objectForKey:identifier] copy];

    [_subscriptionPingPendingByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingOperationsByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingTokenByIdentifier removeObjectForKey:identifier];

    for (NSOperation *operation in operations) {
        [operation cancel];
    }

    for (NSString *uri in pending) {
        if (![[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) continue;
        if ([self isURIInActiveSubscriptionPing:uri]) {
            continue;
        }
        NSString *previous = [previousDisplay objectForKey:uri];
        if ([previous length] > 0) {
            [_pingDisplayByURI setObject:previous forKey:uri];
        } else {
            [_pingDisplayByURI removeObjectForKey:uri];
        }
    }

    [operations release];
    [pending release];
    [previousDisplay release];

    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
    [self showStatus:@"Subscription ping stopped" ok:YES];
    VCRecordAppEvent(@"ping", @"Subscription ping batch canceled",
                     [NSString stringWithFormat:@"pending=%lu", (unsigned long)pendingCount]);
}

- (void)subscriptionPingButtonPressed:(UIButton *)sender {
    NSInteger subIdx = sender.tag - kVCSubscriptionPingButtonTagBase;
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([self isSubscriptionPingInProgressAtIndex:subIdx]) {
        [self stopSubscriptionPingAtIndex:subIdx];
        return;
    }
    if ([items count] == 0) return;

    [self startSubscriptionPingAtIndex:subIdx];
}

- (void)updateConnectButton {
    NSString *title = _connected ? @"Disconnect" : @"Connect";
    [_connectBtn setTitle:title forState:UIControlStateNormal];

    UIColor *fill = _connected
        ? [UIColor colorWithRed:0.12f green:0.58f blue:0.20f alpha:1.0f]
        : [UIColor colorWithRed:0.10f green:0.40f blue:0.82f alpha:1.0f];
    _connectBtn.backgroundColor = fill;
}

- (void)applyTouchFeedbackToButton:(UIButton *)btn {
    if (!btn) return;
    btn.showsTouchWhenHighlighted = YES;
    btn.adjustsImageWhenHighlighted = YES;
    btn.layer.masksToBounds = NO;
    [btn addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpOutside];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchCancel];
}

- (void)applyTopButtonFeedbackToButton:(UIButton *)btn {
    if (!btn) return;
    btn.showsTouchWhenHighlighted = NO;
    btn.adjustsImageWhenHighlighted = NO;
    btn.layer.cornerRadius = 6.0f;
    btn.layer.masksToBounds = YES;
    [btn setBackgroundImage:SolidImageWithColor([UIColor colorWithWhite:0.0f alpha:0.0f]) forState:UIControlStateNormal];
    UIColor *highlight = VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                               : [UIColor colorWithWhite:0.72f alpha:1.0f];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateHighlighted];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateSelected];
}

- (void)buttonTouchDown:(UIButton *)sender {
    sender.layer.shadowColor = [UIColor blackColor].CGColor;
    sender.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
    sender.layer.shadowRadius = 4.0f;
    sender.layer.shadowOpacity = 0.35f;
}

- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.12
                     animations:^{
                         sender.layer.shadowOpacity = 0.0f;
                     }];
}

- (void)updateTopButtonsIcons {
    [_plusBtn setImage:MakeIconImage(VCIconTypeAdd, 20.0f, NO) forState:UIControlStateNormal];
    UIColor *iconColor = VCPrimaryTextColor();
    UIImage *refresh = LoadBundledIconTinted(@"icon-refresh", 20.0f, iconColor);
    UIImage *terminal = _showingTerminal
        ? LoadBundledIconTinted(@"icon-list", 20.0f, iconColor)
        : LoadBundledIconTinted(@"icon-terminal", 20.0f, iconColor);
    UIImage *settings = LoadBundledIconTinted(@"icon-settings", 20.0f, iconColor);
    UIImage *trash = LoadBundledIconTinted(@"icon-trash", 20.0f, iconColor);
    UIImage *update = LoadBundledIconScaled(VCAppearanceIsDark() ? @"update-dark" : @"update-white", 20.0f);

    [_refreshBtn setImage:(refresh ? refresh : MakeIconImage(VCIconTypeRefresh, 20.0f, NO)) forState:UIControlStateNormal];
    [_terminalBtn setImage:(terminal ? terminal : MakeIconImage(_showingTerminal ? VCIconTypeList : VCIconTypeTerminal, 20.0f, _showingTerminal))
                  forState:UIControlStateNormal];
    [_clearLogsBtn setImage:trash forState:UIControlStateNormal];
    _clearLogsBtn.hidden = !_showingTerminal;
    [_settingsBtn setImage:(settings ? settings : MakeIconImage(VCIconTypeSettings, 20.0f, NO)) forState:UIControlStateNormal];
    [_updateBtn setImage:update forState:UIControlStateNormal];
    _updateBtn.hidden = !([_availableUpdateVersion length] > 0);
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

- (NSString *)happJSONStringValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return nil;
}

- (NSDictionary *)happJSONDictionaryValue:(id)value {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

- (NSArray *)happJSONArrayValue:(id)value {
    return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : nil;
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

- (NSString *)happJSONStringFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]] || [dictionary count] == 0) return nil;
    if (![NSJSONSerialization isValidJSONObject:dictionary]) return nil;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!data || error) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (void)addHappURIQueryValue:(NSString *)value key:(NSString *)key toParts:(NSMutableArray *)parts {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;
    if (![key isKindOfClass:[NSString class]] || [key length] == 0) return;
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, [self percentEncodedHappURIValue:value]]];
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
    NSString *encryption = [[self safeTrim:[self happJSONStringValue:[user objectForKey:@"encryption"]]] lowercaseString];
    if ([address length] == 0 || [portText length] == 0 || [uuid length] == 0) return nil;
    NSInteger port = [portText integerValue];
    if (port <= 0 || port > 65535) return nil;
    if ([encryption length] > 0 && ![encryption isEqualToString:@"none"]) return nil;

    NSDictionary *stream = [self happJSONDictionaryValue:[proxy objectForKey:@"streamSettings"]];
    NSString *network = [[self safeTrim:[self happJSONStringValue:[stream objectForKey:@"network"]]] lowercaseString];
    NSString *security = [[self safeTrim:[self happJSONStringValue:[stream objectForKey:@"security"]]] lowercaseString];
    if ([network isEqualToString:@"splithttp"]) network = @"xhttp";
    if ([network length] == 0) network = @"tcp";
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

    NSMutableArray *query = [NSMutableArray arrayWithObjects:@"encryption=none", nil];
    [self addHappURIQueryValue:network key:@"type" toParts:query];
    [self addHappURIQueryValue:security key:@"security" toParts:query];

    NSString *flow = [self safeTrim:[self happJSONStringValue:[user objectForKey:@"flow"]]];
    if (tcpSupported && [flow length] > 0) {
        if ([security isEqualToString:@"none"]) return nil;
        if (![flow isEqualToString:@"xtls-rprx-vision"]) return nil;
        [self addHappURIQueryValue:flow key:@"flow" toParts:query];
    }

    NSDictionary *securitySettings = nil;
    if ([security isEqualToString:@"reality"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"realitySettings"]];
    } else if ([security isEqualToString:@"tls"]) {
        securitySettings = [self happJSONDictionaryValue:[stream objectForKey:@"tlsSettings"]];
    }

    NSString *sni = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"serverName"]]];
    NSString *fingerprint = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"fingerprint"]]];
    [self addHappURIQueryValue:sni key:@"sni" toParts:query];
    [self addHappURIQueryValue:fingerprint key:@"fp" toParts:query];

    NSArray *alpnValues = [self happJSONArrayValue:[securitySettings objectForKey:@"alpn"]];
    NSMutableArray *cleanALPN = [NSMutableArray array];
    for (id value in alpnValues) {
        NSString *alpn = [self safeTrim:[self happJSONStringValue:value]];
        if ([alpn length] > 0) [cleanALPN addObject:alpn];
    }
    if ([cleanALPN count] > 0) {
        [self addHappURIQueryValue:[cleanALPN componentsJoinedByString:@","] key:@"alpn" toParts:query];
    }

    id allowInsecure = [securitySettings objectForKey:@"allowInsecure"];
    if ([allowInsecure respondsToSelector:@selector(boolValue)] && [allowInsecure boolValue]) {
        [query addObject:@"allowInsecure=1"];
    }

    if ([security isEqualToString:@"reality"]) {
        NSString *publicKey = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"publicKey"]]];
        NSString *shortID = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"shortId"]]];
        NSString *spiderX = [self safeTrim:[self happJSONStringValue:[securitySettings objectForKey:@"spiderX"]]];
        if ([publicKey length] == 0) return nil;
        [self addHappURIQueryValue:publicKey key:@"pbk" toParts:query];
        [self addHappURIQueryValue:shortID key:@"sid" toParts:query];
        [self addHappURIQueryValue:spiderX key:@"spx" toParts:query];
    }

    if (xhttpSupported) {
        NSDictionary *xhttp = [self happJSONDictionaryValue:[stream objectForKey:@"xhttpSettings"]];
        NSString *path = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"path"]]];
        NSString *host = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"host"]]];
        NSString *mode = [self safeTrim:[self happJSONStringValue:[xhttp objectForKey:@"mode"]]];
        NSDictionary *extra = [self happJSONDictionaryValue:[xhttp objectForKey:@"extra"]];
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
        [self addHappURIQueryValue:mode key:@"mode" toParts:query];
        [self addHappURIQueryValue:[self happJSONStringFromDictionary:extra] key:@"extra" toParts:query];
    } else if (wsSupported) {
        NSDictionary *ws = [self happJSONDictionaryValue:[stream objectForKey:@"wsSettings"]];
        NSString *path = [self safeTrim:[self happJSONStringValue:[ws objectForKey:@"path"]]];
        NSDictionary *headers = [self happJSONDictionaryValue:[ws objectForKey:@"headers"]];
        NSString *host = [self safeTrim:[self happJSONStringValue:[headers objectForKey:@"Host"]]];
        if ([host length] == 0) host = [self safeTrim:[self happJSONStringValue:[headers objectForKey:@"host"]]];
        [self addHappURIQueryValue:([path length] > 0 ? path : @"/") key:@"path" toParts:query];
        [self addHappURIQueryValue:host key:@"host" toParts:query];
    } else if (grpcSupported) {
        NSDictionary *grpc = [self happJSONDictionaryValue:[stream objectForKey:@"grpcSettings"]];
        id multiMode = [grpc objectForKey:@"multiMode"];
        if (!multiMode) multiMode = [grpc objectForKey:@"multi_mode"];
        if ([multiMode respondsToSelector:@selector(boolValue)] && [multiMode boolValue]) {
            [self addHappURIQueryValue:@"multi" key:@"mode" toParts:query];
        }

        NSString *serviceName = [self safeTrim:[self happJSONStringValue:[grpc objectForKey:@"serviceName"]]];
        if ([serviceName length] == 0) {
            serviceName = [self safeTrim:[self happJSONStringValue:[grpc objectForKey:@"service_name"]]];
        }
        NSString *authority = [self safeTrim:[self happJSONStringValue:[grpc objectForKey:@"authority"]]];
        [self addHappURIQueryValue:serviceName key:@"serviceName" toParts:query];
        [self addHappURIQueryValue:authority key:@"authority" toParts:query];
    }

    NSString *authorityHost = address;
    if ([address rangeOfString:@":"].location != NSNotFound && ![address hasPrefix:@"["]) {
        authorityHost = [NSString stringWithFormat:@"[%@]", address];
    }
    NSString *title = [self safeTrim:[self happJSONStringValue:[config objectForKey:@"remarks"]]];
    NSString *fragment = ([title length] > 0)
                             ? [NSString stringWithFormat:@"#%@", [self percentEncodedHappURIValue:title]]
                             : @"";
    return [NSString stringWithFormat:@"vless://%@@%@:%ld?%@%@",
                                      uuid,
                                      authorityHost,
                                      (long)port,
                                      [query componentsJoinedByString:@"&"],
                                      fragment];
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

- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    return [uri rangeOfString:@"@0.0.0.0:1?"].location != NSNotFound;
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

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut insecureRetryAvailable:(BOOL *)insecureRetryAvailableOut {
    if (errorTextOut) *errorTextOut = nil;
    if (insecureRetryAvailableOut) *insecureRetryAvailableOut = NO;
    if (![sub isKindOfClass:[NSDictionary class]]) {
        if (errorTextOut) *errorTextOut = @"Subscription entry is invalid";
        return nil;
    }

    NSString *urlString = [sub objectForKey:@"url"];
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is missing";
        return nil;
    }

    BOOL useHappHeaders = SubscriptionDictionaryUsesHappHeaders(sub);
    NSString *fetchURLString = urlString;
    if (useHappHeaders && [self isHappEncryptedLink:urlString]) {
        NSString *decryptError = nil;
        fetchURLString = [self decryptedHappLink:urlString errorText:&decryptError];
        if (![fetchURLString isKindOfClass:[NSString class]] || [fetchURLString length] == 0) {
            if (errorTextOut) {
                *errorTextOut = ([decryptError length] > 0) ? decryptError : @"HAPP link decryption failed";
            }
            return nil;
        }
    }

    NSURL *url = [NSURL URLWithString:fetchURLString];
    if (!url) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is invalid";
        return nil;
    }

    NSString *nameFromURL = useHappHeaders ? @"HAPP subscription" : [self subscriptionNameFromURLString:fetchURLString];
    NSString *hostName = useHappHeaders ? @"HAPP subscription" : [self hostFromURLString:fetchURLString];
    NSString *nameFromMeta = nil;
    NSDictionary *userInfoFromMeta = nil;
    NSDictionary *metadataFromMeta = nil;
    BOOL allowInsecureFetch = SubscriptionDictionaryAllowsInsecureFetch(sub);
    BOOL allowPlainHTTP = SubscriptionDictionaryAllowsPlainHTTP(sub);

    NSString *fetchErr = nil;
    NSString *curlHeaders = nil;
    NSString *userAgent = AppUserAgent();
    int curlExitCode = -1;
    NSData *data = FetchURLViaVlessCoreCurl(fetchURLString,
                                            allowInsecureFetch,
                                            allowPlainHTTP,
                                            useHappHeaders,
                                            YES,
                                            userAgent,
                                            &fetchErr,
                                            &curlHeaders,
                                            &curlExitCode);
    if (!data && !allowInsecureFetch && CurlExitCodeCanRetryInsecurely(curlExitCode)) {
        if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
    }
    if ([nameFromMeta length] == 0 && [curlHeaders length] > 0) {
        nameFromMeta = [self subscriptionTitleFromMetadataText:curlHeaders];
    }
    if ([curlHeaders length] > 0) {
        userInfoFromMeta = [self subscriptionUserInfoFromMetadataText:curlHeaders];
        metadataFromMeta = [self subscriptionMetadataFromMetadataText:curlHeaders];
    }
    if (useHappHeaders && !data && !allowInsecureFetch &&
        (!fetchErr || [fetchErr hasPrefix:@"vless-core-curl not found"])) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20.0];
        NSString *hwid = SubscriptionHWID();
        if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
            [req setValue:hwid forHTTPHeaderField:@"X-HWID"];
        }
        if (useHappHeaders) {
            [req setValue:kHappSubscriptionUserAgent forHTTPHeaderField:@"User-Agent"];
            UIDevice *device = [UIDevice currentDevice];
            NSString *locale = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
            NSString *systemVersion = TrimSimpleString([device systemVersion]);
            NSString *model = DeviceModelName();
            if ([locale length] > 0) [req setValue:locale forHTTPHeaderField:@"X-Device-Locale"];
            [req setValue:@"iOS" forHTTPHeaderField:@"X-Device-OS"];
            if ([systemVersion length] > 0) [req setValue:systemVersion forHTTPHeaderField:@"X-Ver-OS"];
            if ([model length] > 0) [req setValue:model forHTTPHeaderField:@"X-Device-Model"];
        }
        NSURLResponse *resp = nil;
        NSError *err = nil;
        data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        if (!data || err) {
            fetchErr = [err localizedDescription];
            if (!allowInsecureFetch && NSURLErrorCanRetryInsecurely(err)) {
                if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
            }
        } else if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSDictionary *headers = [(NSHTTPURLResponse *)resp allHeaderFields];
            nameFromMeta = [self subscriptionTitleFromHTTPHeaders:headers];
            userInfoFromMeta = [self subscriptionUserInfoFromHTTPHeaders:headers];
            metadataFromMeta = [self subscriptionMetadataFromHTTPHeaders:headers];
        }
    }

    if (!data) {
        if (![fetchErr isKindOfClass:[NSString class]] || [fetchErr length] == 0) {
            fetchErr = @"unknown error";
        }
        if (errorTextOut) *errorTextOut = [NSString stringWithFormat:@"Subscription fetch failed: %@", fetchErr];
        return nil;
    }

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
    [storedMetadata setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)[[NSDate date] timeIntervalSince1970]]
                       forKey:kSubscriptionLastUpdatedKey];
    [updated setObject:storedMetadata forKey:kSubscriptionMetadataKey];

    NSString *customName = [sub objectForKey:kSubscriptionCustomNameKey];
    BOOL hasCustomName = [customName isKindOfClass:[NSString class]] && [customName length] > 0;
    if (_preserveCustomSubscriptionNames && hasCustomName) {
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

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut {
    return [self updatedSubscriptionDictionaryFromSource:sub errorText:errorTextOut insecureRetryAvailable:NULL];
}

- (BOOL)subscriptionNeedsPlainHTTPApproval:(NSDictionary *)sub {
    if (![sub isKindOfClass:[NSDictionary class]] || SubscriptionDictionaryUsesHappHeaders(sub)) return NO;
    return URLStringUsesPlainHTTP([sub objectForKey:@"url"]) &&
           !SubscriptionDictionaryAllowsPlainHTTP(sub);
}

- (BOOL)approvePlainHTTPForSubscriptionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return NO;
    NSDictionary *sub = [_subscriptions objectAtIndex:index];
    if (![self subscriptionNeedsPlainHTTPApproval:sub]) {
        return SubscriptionDictionaryAllowsPlainHTTP(sub);
    }

    NSMutableDictionary *approved = [NSMutableDictionary dictionaryWithDictionary:sub];
    [approved setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
    [_subscriptions replaceObjectAtIndex:index withObject:approved];
    return YES;
}

- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus {
    if (idx < 0 || idx >= (NSInteger)[_subscriptions count]) return NO;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"subscription", @"Single subscription update started", nil);

    NSDictionary *sub = [_subscriptions objectAtIndex:idx];
    if ([self subscriptionNeedsPlainHTTPApproval:sub]) {
        [self showPlainHTTPSubscriptionWarningForCount:1 confirmation:^{
            if ([self approvePlainHTTPForSubscriptionAtIndex:idx]) {
                [self saveData];
                if ([self refreshSubscriptionAtIndex:idx showStatus:YES]) {
                    [self reloadMainTableDataAfterExternalChange];
                }
            }
        }];
        return NO;
    }

    NSString *errorText = nil;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
    if (![updated isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"subscription", @"Single subscription update failed",
                         [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                          VCDiagnosticErrorSummary(errorText),
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        if (showStatus) {
            [self showStatus:([errorText length] > 0 ? errorText : @"Subscription update failed") ok:NO];
            [self showSubscriptionUpdateFailures:[NSArray arrayWithObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]]];
        }
        return NO;
    }

    NSArray *uris = [updated objectForKey:@"items"];
    [_subscriptions replaceObjectAtIndex:idx withObject:updated];
    if (_selectedSubIndex == idx) {
        if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
            _selectedSubItemIndex = -1;
        } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
            _selectedSubItemIndex = 0;
        }
    }
    [self saveData];
    VCRecordAppEvent(@"subscription", @"Single subscription update finished",
                     [NSString stringWithFormat:@"configs=%lu duration_ms=%.0f",
                      (unsigned long)[uris count],
                      ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
    if (showStatus) {
        [self showStatus:[NSString stringWithFormat:@"Subscription updated (%lu configs)", (unsigned long)[uris count]] ok:YES];
    }
    return YES;
}

- (BOOL)subscriptionsMatchSnapshotForLaunchAutoUpdate:(NSArray *)snapshot {
    if (![snapshot isKindOfClass:[NSArray class]]) return NO;
    if ((NSInteger)[snapshot count] != (NSInteger)[_subscriptions count]) return NO;

    for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
        NSDictionary *oldSub = [snapshot objectAtIndex:i];
        NSDictionary *curSub = [_subscriptions objectAtIndex:i];
        NSString *oldURL = [oldSub objectForKey:@"url"];
        NSString *curURL = [curSub objectForKey:@"url"];
        if (![oldURL isKindOfClass:[NSString class]]) oldURL = @"";
        if (![curURL isKindOfClass:[NSString class]]) curURL = @"";
        if (![oldURL isEqualToString:curURL]) return NO;

        NSString *oldName = [oldSub objectForKey:@"name"];
        NSString *curName = [curSub objectForKey:@"name"];
        if (![oldName isKindOfClass:[NSString class]]) oldName = @"";
        if (![curName isKindOfClass:[NSString class]]) curName = @"";
        if (![oldName isEqualToString:curName]) return NO;

        NSString *oldCustomName = [oldSub objectForKey:kSubscriptionCustomNameKey];
        NSString *curCustomName = [curSub objectForKey:kSubscriptionCustomNameKey];
        if (![oldCustomName isKindOfClass:[NSString class]]) oldCustomName = @"";
        if (![curCustomName isKindOfClass:[NSString class]]) curCustomName = @"";
        if (![oldCustomName isEqualToString:curCustomName]) return NO;
    }
    return YES;
}

- (void)startBackgroundSubscriptionRefreshWithStatus:(NSString *)startStatus {
    if ([_subscriptions count] == 0) {
        if (_pendingImportDoneStatus) {
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        }
        if (_pendingImportRefreshIndices) {
            [_pendingImportRefreshIndices release];
            _pendingImportRefreshIndices = nil;
        }
        [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        if (_pendingImportDoneStatus) {
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        }
        if (_pendingImportRefreshIndices) {
            [_pendingImportRefreshIndices release];
            _pendingImportRefreshIndices = nil;
        }
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    NSMutableArray *plainHTTPIndices = [NSMutableArray array];
    if ([_pendingImportRefreshIndices count] > 0) {
        for (id indexValue in _pendingImportRefreshIndices) {
            NSInteger index = [indexValue integerValue];
            if (index >= 0 && index < (NSInteger)[_subscriptions count] &&
                [self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
                [plainHTTPIndices addObject:[NSNumber numberWithInteger:index]];
            }
        }
    } else {
        for (NSInteger index = 0; index < (NSInteger)[_subscriptions count]; index++) {
            if ([self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
                [plainHTTPIndices addObject:[NSNumber numberWithInteger:index]];
            }
        }
    }
    if ([plainHTTPIndices count] > 0) {
        [self showPlainHTTPSubscriptionWarningForCount:[plainHTTPIndices count] confirmation:^{
            BOOL changed = NO;
            for (NSNumber *indexValue in plainHTTPIndices) {
                changed |= [self approvePlainHTTPForSubscriptionAtIndex:[indexValue integerValue]];
            }
            if (changed) [self saveData];
            [self startBackgroundSubscriptionRefreshWithStatus:startStatus];
        }];
        return;
    }

    NSArray *requestedIndices = nil;
    if (_pendingImportRefreshIndices && [_pendingImportRefreshIndices count] > 0) {
        requestedIndices = [_pendingImportRefreshIndices copy];
    }
    [_pendingImportRefreshIndices release];
    _pendingImportRefreshIndices = nil;

    NSArray *snapshot = [[NSArray alloc] initWithArray:_subscriptions copyItems:YES];
    NSMutableArray *refreshIndicesMutable = [NSMutableArray array];
    if ([requestedIndices count] > 0) {
        for (id idxObj in requestedIndices) {
            NSInteger idx = [idxObj integerValue];
            if (idx >= 0 && idx < (NSInteger)[snapshot count]) {
                [refreshIndicesMutable addObject:[NSNumber numberWithInteger:idx]];
            }
        }
    } else {
        for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
            [refreshIndicesMutable addObject:[NSNumber numberWithInteger:i]];
        }
    }
    [requestedIndices release];

    if ([refreshIndicesMutable count] == 0) {
        if (_pendingImportDoneStatus) {
            [self showStatus:_pendingImportDoneStatus ok:YES];
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        } else {
            [self showStatus:@"No subscriptions to update" ok:NO];
        }
        [snapshot release];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];

    NSArray *refreshIndices = [[NSArray alloc] initWithArray:refreshIndicesMutable];
    VCRecordAppEvent(@"subscription", @"Subscription update batch started",
                     [NSString stringWithFormat:@"requested=%lu", (unsigned long)[refreshIndices count]]);
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Updating subscriptions...";
    [self showStatus:startText ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *updatedSubs = [[NSMutableArray alloc] initWithArray:snapshot];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSMutableDictionary *failureCategories = [[NSMutableDictionary alloc] init];
        NSUInteger okCount = 0;
        for (NSNumber *idxObj in refreshIndices) {
            NSInteger i = [idxObj integerValue];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self setUpdatingSubscriptionIndex:i];
            });

            NSDictionary *sub = [snapshot objectAtIndex:i];
            NSString *errorText = nil;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
            if (updated) {
                [updatedSubs replaceObjectAtIndex:i withObject:updated];
                okCount++;
            } else {
                [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
                VCIncrementDiagnosticCategory(failureCategories, errorText);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setUpdatingSubscriptionIndex:-1];
            _launchAutoUpdateInProgress = NO;

            if (![self subscriptionsMatchSnapshotForLaunchAutoUpdate:snapshot]) {
                VCRecordAppEvent(@"subscription", @"Subscription update batch discarded",
                                 @"reason=list_changed_during_update");
                [self showStatus:@"Auto-update skipped: subscriptions changed" ok:YES];
                if (_pendingImportDoneStatus) {
                    [_pendingImportDoneStatus release];
                    _pendingImportDoneStatus = nil;
                }
                [failureTexts release];
                [failureCategories release];
                [updatedSubs release];
                [refreshIndices release];
                [snapshot release];
                return;
            }

            [_subscriptions removeAllObjects];
            [_subscriptions addObjectsFromArray:updatedSubs];

            [self normalizeSelection];
            [self reloadMainTableDataAfterExternalChange];
            [self saveData];
            [self refreshPresentedSubscriptionInfoIfNeeded];

            BOOL ok = okCount > 0;
            if (_pendingImportDoneStatus) {
                [self showStatus:_pendingImportDoneStatus ok:YES];
                [_pendingImportDoneStatus release];
                _pendingImportDoneStatus = nil;
            } else {
	                [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
	                                  (unsigned long)okCount,
	                                  (unsigned long)[refreshIndices count]]
	                         ok:ok];
            }

            if ([failureTexts count] > 0) {
                [self showSubscriptionUpdateFailures:failureTexts];
            }
            VCRecordAppEvent(@"subscription", @"Subscription update batch finished",
                             [NSString stringWithFormat:@"requested=%lu updated=%lu failed=%lu failure_types=%@ duration_ms=%.0f",
                              (unsigned long)[refreshIndices count],
                              (unsigned long)okCount,
                              (unsigned long)[failureTexts count],
                              VCDiagnosticCategoryCountsText(failureCategories),
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);

            [failureTexts release];
            [failureCategories release];
            [updatedSubs release];
            [refreshIndices release];
            [snapshot release];
        });

        [pool drain];
    });
}

- (void)startLaunchAutoUpdateIfNeeded {
    if (_didRunLaunchAutoUpdate) return;
    _didRunLaunchAutoUpdate = YES;

    if (!_autoUpdateSubscriptions || [_subscriptions count] == 0) return;

    [self startBackgroundSubscriptionRefreshWithStatus:@"Auto-updating subscriptions in background..."];
}

- (void)refreshAllSubscriptions:(BOOL)showStatus {
    if ([_subscriptions count] == 0) {
        if (showStatus) [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }

    NSUInteger okCount = 0;
    NSMutableArray *failureTexts = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *sub = [_subscriptions objectAtIndex:i];
        NSString *errorText = nil;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            NSArray *uris = [updated objectForKey:@"items"];
            [_subscriptions replaceObjectAtIndex:i withObject:updated];
            if (_selectedSubIndex == i) {
                if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
                    _selectedSubItemIndex = -1;
                } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
                    _selectedSubItemIndex = 0;
                }
            }
            [self saveData];
            okCount++;
        } else {
            [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
        }
    }

    [self normalizeSelection];
    [self reloadMainTableDataAfterExternalChange];
    [self refreshPresentedSubscriptionInfoIfNeeded];

    if (showStatus) {
        BOOL ok = okCount > 0;
        [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
                          (unsigned long)okCount,
                          (unsigned long)[_subscriptions count]]
                     ok:ok];
        if ([failureTexts count] > 0) {
            [self showSubscriptionUpdateFailures:failureTexts];
        }
    }
}

- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled {
    (void)vc;
    _autoUpdateSubscriptions = enabled;
    VCRecordAppEvent(@"settings", @"Subscription auto-update changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [self showStatus:_autoUpdateSubscriptions ? @"Auto-update subscriptions: ON"
                                           : @"Auto-update subscriptions: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)enabled {
    (void)vc;
    _automaticUpdateChecksEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Application update checks changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startAutomaticUpdateCheckIfNeeded)
                                               object:nil];
    if (enabled) {
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:0.5];
    } else if (_updateChecker) {
        _updateChecker.delegate = nil;
        [_updateChecker release];
        _updateChecker = nil;
    }

    [self showStatus:enabled ? @"Automatic update checks: ON"
                             : @"Automatic update checks: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)enabled {
    (void)vc;
    _preserveCustomSubscriptionNames = enabled;
    VCRecordAppEvent(@"settings", @"Preserve custom names changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [self showStatus:_preserveCustomSubscriptionNames ? @"Preserve custom names: ON"
                                                      : @"Preserve custom names: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled {
    (void)vc;
    _stealthModeEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Stealth mode changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [_tableView reloadData];
    [self showStatus:_stealthModeEnabled ? @"Stealth mode: ON"
                                   : @"Stealth mode: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled {
    (void)vc;
    _darkThemeEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Appearance changed", enabled ? @"theme=dark" : @"theme=light");
    [self saveData];
    [self applyTheme];
}

- (UIView *)accessoryChevronExpanded:(BOOL)expanded {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)] autorelease];
    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(2, 2, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];
    return v;
}

- (UIView *)accessorySubscriptionHeaderAtIndex:(NSInteger)index expanded:(BOOL)expanded loading:(BOOL)loading {
    BOOL pingLoading = [self isSubscriptionPingInProgressAtIndex:index];
    CGFloat width = loading ? 100.0f : 80.0f;
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 24)] autorelease];
    v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    UIButton *pingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    pingButton.frame = CGRectMake(0.0f, 0.0f, 24.0f, 24.0f);
    pingButton.tag = kVCSubscriptionPingButtonTagBase + index;
    if (pingLoading) {
        [pingButton setImage:MakeIconImage(VCIconTypeStop, 20.0f, NO)
                    forState:UIControlStateNormal];
        pingButton.accessibilityLabel = @"Stop subscription ping";
        pingButton.accessibilityHint = @"Stops the remaining latency tests";
    } else {
        UIImage *pingIcon = LoadBundledIconTinted(@"icon-ping", 20.0f, VCPrimaryTextColor());
        [pingButton setImage:(pingIcon ? pingIcon : MakeIconImage(VCIconTypeWifi, 18.0f, NO))
                    forState:UIControlStateNormal];
        pingButton.accessibilityLabel = @"Ping all subscription configurations";
        pingButton.accessibilityHint = [NSString stringWithFormat:@"Runs %@ latency tests",
                                                                  VCPingTypeName(VCSelectedPingType())];
    }
    pingButton.enabled = pingLoading || ([[self subscriptionItemsAtIndex:index] count] > 0);
    [pingButton addTarget:self
                   action:@selector(subscriptionPingButtonPressed:)
         forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:pingButton];
    [v addSubview:pingButton];

    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    infoButton.frame = CGRectMake(32.0f, 0.0f, 24.0f, 24.0f);
    infoButton.tag = kVCSubscriptionInfoButtonTagBase + index;
    UIImage *infoIcon = LoadBundledIconTinted(@"info", 21.0f, VCSecondaryTextColor());
    [infoButton setImage:infoIcon forState:UIControlStateNormal];
    infoButton.accessibilityLabel = @"Subscription information";
    infoButton.accessibilityHint = @"Opens subscription details and actions";
    [infoButton addTarget:self action:@selector(subscriptionInfoButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:infoButton];
    [v addSubview:infoButton];

    if (loading) {
        UIActivityIndicatorView *spinner =
            [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray)] autorelease];
        spinner.frame = CGRectMake(58.0f, 2.0f, 20.0f, 20.0f);
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        [v addSubview:spinner];
    }

    CGFloat chevronX = loading ? 84.0f : 64.0f;
    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(chevronX, 4, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];
    return v;
}

- (UIView *)accessoryPingWithTag:(NSInteger)tag uri:(NSString *)uri {
    NSString *display = ([uri isKindOfClass:[NSString class]] ? [_pingDisplayByURI objectForKey:uri] : nil);
    BOOL loading = [display isEqualToString:kVCPingLoadingValue];
    BOOL hasResult = ([display length] > 0 && !loading);
    BOOL failed = [display isEqualToString:kVCPingFailureValue];
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 24.0f, 24.0f)] autorelease];
    v.clipsToBounds = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    if (hasResult) {
        UIFont *font = [UIFont boldSystemFontOfSize:9.0f];
        CGFloat labelWidth = MAX(34.0f, ceilf([display sizeWithFont:font].width) + 2.0f);
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(floorf((24.0f - labelWidth) * 0.5f),
                                                                           21.0f,
                                                                           labelWidth,
                                                                           12.0f)] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.font = font;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = NO;
        label.textColor = failed ? VCErrorColor() : VCSuccessColor();
        label.text = display;
        [v addSubview:label];
    }

    if (loading) {
        UIActivityIndicatorView *spinner =
            [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray)] autorelease];
        spinner.frame = CGRectMake(2.0f, 2.0f, 20.0f, 20.0f);
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        [v addSubview:spinner];
        return v;
    }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0.0f, 0.0f, 24.0f, 24.0f);
    UIImage *pingIcon = LoadBundledIconTinted(@"icon-ping", 20.0f, VCPrimaryTextColor());
    [btn setImage:(pingIcon ? pingIcon : MakeIconImage(VCIconTypeWifi, 18.0f, NO)) forState:UIControlStateNormal];
    btn.tag = tag;
    btn.accessibilityLabel = hasResult ? [NSString stringWithFormat:@"Ping result %@", display]
                                       : @"Check ping";
    NSString *pingTypeName = VCPingTypeName(VCSelectedPingType());
    BOOL subscriptionPingRunning = NO;
    if (tag >= 20000) {
        NSInteger subIdx = (tag - 20000) / 1000;
        subscriptionPingRunning = [self isSubscriptionPingInProgressAtIndex:subIdx];
    }
    btn.enabled = !subscriptionPingRunning;
    btn.adjustsImageWhenDisabled = YES;
    btn.accessibilityHint = subscriptionPingRunning
        ? @"All configurations in this subscription are being pinged"
        : (hasResult
            ? [NSString stringWithFormat:@"Double tap to run %@ again", pingTypeName]
            : [NSString stringWithFormat:@"Runs %@ latency test", pingTypeName]);
    [btn addTarget:self action:@selector(pingButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:btn];
    [v addSubview:btn];

    return v;
}

- (NSInteger)existingConfigIndexForURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_configs count]; i++) {
        NSDictionary *it = [_configs objectAtIndex:i];
        NSString *existingURI = [it objectForKey:@"uri"];
        if ([existingURI isKindOfClass:[NSString class]] && [existingURI isEqualToString:uri]) {
            return i;
        }
    }
    return -1;
}

- (NSInteger)existingSubscriptionIndexForURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *it = [_subscriptions objectAtIndex:i];
        NSString *existingURL = [it objectForKey:@"url"];
        if ([existingURL isKindOfClass:[NSString class]] && [existingURL isEqualToString:urlString]) {
            return i;
        }
    }
    return -1;
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                 allowPlainHTTP:(BOOL)allowPlainHTTP
                                     happSource:(BOOL)happSource {
    NSString *name = happSource ? @"HAPP subscription" : [self subscriptionNameFromURLString:urlString];
    NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                name, @"name",
                                urlString, @"url",
                                [NSArray array], @"items",
                                nil];
    if (allowInsecureFetch) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
    }
    if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(urlString)) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
    }
    if (happSource) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
    }
    return sub;
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                     happSource:(BOOL)happSource {
    return [self subscriptionDictionaryForURL:urlString
                           allowInsecureFetch:allowInsecureFetch
                               allowPlainHTTP:NO
                                   happSource:happSource];
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    return [self subscriptionDictionaryForURL:urlString
                           allowInsecureFetch:allowInsecureFetch
                                   happSource:NO];
}

- (void)selectSubscriptionAtIndex:(NSInteger)subIndex {
    _subscriptionsSectionExpanded = YES;
    _expandedSubscription = subIndex;
    _selectedConfigIndex = -1;
    _selectedSubIndex = subIndex;
    _selectedSubItemIndex = 0;
    [self normalizeSelection];
    [self saveMainState];
    [_tableView reloadData];
}

- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation {
    [self showPlainHTTPSubscriptionWarningForCount:count
                                      confirmation:confirmation
                                        cancellation:nil];
}

- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation
                                        cancellation:(void (^)(void))cancellation {
    if (!confirmation || count == 0) return;

    if (_pendingPlainHTTPConfirmation) {
        Block_release(_pendingPlainHTTPConfirmation);
        _pendingPlainHTTPConfirmation = NULL;
    }
    if (_pendingPlainHTTPCancellation) {
        Block_release(_pendingPlainHTTPCancellation);
        _pendingPlainHTTPCancellation = NULL;
    }
    _pendingPlainHTTPConfirmation = Block_copy(confirmation);
    if (cancellation) _pendingPlainHTTPCancellation = Block_copy(cancellation);

    NSString *message = count == 1
        ? @"This subscription uses unencrypted HTTP. Its access token and configurations can be read or changed by anyone on the network. Continue and allow HTTP for this subscription?"
        : [NSString stringWithFormat:@"%lu subscriptions use unencrypted HTTP. Their access tokens and configurations can be read or changed by anyone on the network. Continue and allow HTTP for them?",
                                     (unsigned long)count];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Unencrypted Subscription"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Continue", nil] autorelease];
    alert.tag = VCAlertTagPlainHTTPSubscription;
    [alert show];
    [self showStatus:@"HTTP subscription requires confirmation" ok:NO];
}

- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings
                                    fromBatchImport:(BOOL)fromBatchImport
                                         happSource:(BOOL)happSource {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        VCRecordAppEvent(@"import", @"Batch subscription import rejected", @"reason=no_valid_entries");
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    [_pendingInsecureImportURLs release];
    _pendingInsecureImportURLs = [cleanURLs copy];
    _pendingInsecureImportUsesHappHeaders = happSource;

    NSUInteger count = [cleanURLs count];
    NSString *detail = nil;
    if (!fromBatchImport && count == 1) {
        detail = @"This subscription cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for this subscription. Continue?";
    } else {
        detail = @"One of your subscriptions cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for subscriptions that need it. Continue?";
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Warning"
                                                  message:detail
                                                 delegate:self
                                        cancelButtonTitle:@"No"
                                        otherButtonTitles:@"Yes", nil] autorelease];
    av.tag = VCAlertTagImportInsecureSubscription;
    [av show];
    [self showStatus:((!fromBatchImport && count == 1) ? @"Subscription requires insecure fetch confirmation"
                                                       : @"Some subscriptions require insecure fetch confirmation")
                  ok:NO];
}

- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings fromBatchImport:(BOOL)fromBatchImport {
    [self showInsecureSubscriptionImportPromptForURLs:urlStrings
                                      fromBatchImport:fromBatchImport
                                           happSource:NO];
}

- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString {
    [self showInsecureSubscriptionImportPromptForURLs:[NSArray arrayWithObject:urlString] fromBatchImport:NO];
}

- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString happSource:(BOOL)happSource {
    [self showInsecureSubscriptionImportPromptForURLs:[NSArray arrayWithObject:urlString]
                                      fromBatchImport:NO
                                           happSource:happSource];
}

- (void)commitUpdatedSubscription:(NSDictionary *)updated existingIndex:(NSInteger)existingIndex {
    if (![updated isKindOfClass:[NSDictionary class]]) return;

    NSArray *uris = [updated objectForKey:@"items"];
    NSInteger subIndex = existingIndex;
    if (existingIndex >= 0 && existingIndex < (NSInteger)[_subscriptions count]) {
        [_subscriptions replaceObjectAtIndex:existingIndex withObject:updated];
    } else {
        [_subscriptions addObject:updated];
        subIndex = [_subscriptions count] - 1;
    }

    [self saveData];
    VCRecordAppEvent(@"subscription",
                     existingIndex >= 0 ? @"Subscription replaced" : @"Subscription added",
                     [NSString stringWithFormat:@"configs=%lu subscriptions=%lu",
                      (unsigned long)[uris count],
                      (unsigned long)[_subscriptions count]]);
    [self selectSubscriptionAtIndex:subIndex];

    NSString *verb = (existingIndex >= 0) ? @"updated" : @"imported";
    [self showStatus:[NSString stringWithFormat:@"Subscription %@ (%lu configs)",
                      verb,
                      (unsigned long)[uris count]]
                 ok:YES];
}

- (NSString *)subscriptionImportCountText:(NSUInteger)count {
    return [NSString stringWithFormat:@"%lu subscription%@",
            (unsigned long)count,
            (count == 1 ? @"" : @"s")];
}

- (NSString *)shortSubscriptionFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText defaultReason:(NSString *)defaultReason {
    NSString *host = [self hostFromURLString:urlString];
    if (![host isKindOfClass:[NSString class]] || [host length] == 0) {
        host = @"subscription";
    }

    NSString *reason = [self safeTrim:errorText];
    NSString *prefix = @"Subscription fetch failed: ";
    if ([reason hasPrefix:prefix] && [reason length] > [prefix length]) {
        reason = [reason substringFromIndex:[prefix length]];
    }
    if ([reason length] == 0) {
        reason = ([defaultReason isKindOfClass:[NSString class]] && [defaultReason length] > 0)
                     ? defaultReason
                     : @"failed";
    }
    if ([reason length] > 120) {
        reason = [[reason substringToIndex:120] stringByAppendingString:@"..."];
    }

    return [NSString stringWithFormat:@"%@: %@", host, reason];
}

- (NSString *)shortImportFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText {
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"import failed"];
}

- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText {
    NSString *urlString = [sub objectForKey:@"url"];
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"update failed"];
}

- (void)showSubscriptionFailureAlertWithTitle:(NSString *)title failureTexts:(NSArray *)failureTexts {
    if (![failureTexts isKindOfClass:[NSArray class]] || [failureTexts count] == 0) return;

    NSMutableString *message = [NSMutableString string];
    NSUInteger limit = MIN((NSUInteger)[failureTexts count], (NSUInteger)5);
    for (NSUInteger i = 0; i < limit; i++) {
        id obj = [failureTexts objectAtIndex:i];
        if (![obj isKindOfClass:[NSString class]] || [(NSString *)obj length] == 0) continue;
        if ([message length] > 0) [message appendString:@"\n"];
        [message appendFormat:@"- %@", (NSString *)obj];
    }
    if ([failureTexts count] > limit) {
        [message appendFormat:@"\n- ... and %lu more", (unsigned long)([failureTexts count] - limit)];
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil] autorelease];
    [av show];
}

- (void)showSubscriptionImportFailures:(NSArray *)failureTexts {
    [self showSubscriptionFailureAlertWithTitle:@"Some subscriptions were not imported" failureTexts:failureTexts];
}

- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts {
    NSString *title = ([failureTexts count] == 1) ? @"Subscription was not updated" : @"Some subscriptions were not updated";
    [self showSubscriptionFailureAlertWithTitle:title failureTexts:failureTexts];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart {
    [self startBackgroundSubscriptionImportForURLs:urlStrings
                               allowInsecureFetch:allowInsecureFetch
                                      startStatus:startStatus
                               importedPrefixPart:importedPrefixPart
                      fallbackSubscriptionsByURL:nil];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL {
    [self startBackgroundSubscriptionImportForURLs:urlStrings
                               allowInsecureFetch:allowInsecureFetch
                                      startStatus:startStatus
                               importedPrefixPart:importedPrefixPart
                      fallbackSubscriptionsByURL:fallbackSubscriptionsByURL
                                   allowPlainHTTP:NO];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL
                                  allowPlainHTTP:(BOOL)allowPlainHTTP {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        [self showStatus:@"No subscriptions to import" ok:NO];
        return;
    }

    if (!allowPlainHTTP) {
        NSUInteger plainHTTPCount = 0;
        for (NSString *urlString in cleanURLs) {
            if (![self isHappAddLink:urlString] && ![self isHappEncryptedLink:urlString] &&
                URLStringUsesPlainHTTP(urlString)) {
                plainHTTPCount++;
            }
        }
        if (plainHTTPCount > 0) {
            [self showPlainHTTPSubscriptionWarningForCount:plainHTTPCount confirmation:^{
                [self startBackgroundSubscriptionImportForURLs:cleanURLs
                                           allowInsecureFetch:allowInsecureFetch
                                                  startStatus:startStatus
                                           importedPrefixPart:importedPrefixPart
                                  fallbackSubscriptionsByURL:fallbackSubscriptionsByURL
                                               allowPlainHTTP:YES];
            }];
            return;
        }
    }

    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Batch subscription import started",
                     [NSString stringWithFormat:@"requested=%lu insecure=%d",
                      (unsigned long)[cleanURLs count], allowInsecureFetch ? 1 : 0]);
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Importing subscriptions...";
    [self showStatus:startText ok:YES];

    NSArray *urlsToImport = [[NSArray alloc] initWithArray:cleanURLs];
    NSString *prefixPart = [importedPrefixPart copy];
    NSDictionary *fallbackSubscriptions = [fallbackSubscriptionsByURL copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *importedSubs = [[NSMutableArray alloc] init];
        NSMutableArray *insecureURLs = [[NSMutableArray alloc] init];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSMutableDictionary *failureCategories = [[NSMutableDictionary alloc] init];
        NSUInteger failedCount = 0;
        NSUInteger fallbackCount = 0;

        for (NSString *urlString in urlsToImport) {
            BOOL happAddSource = [self isHappAddLink:urlString];
            BOOL happSource = happAddSource || [self isHappEncryptedLink:urlString];
            NSString *subscriptionURL = happAddSource ? [self targetFromHappAddLink:urlString] : urlString;
            if (happAddSource &&
                (![subscriptionURL isKindOfClass:[NSString class]] ||
                 ![self isSubscriptionURL:subscriptionURL])) {
                failedCount++;
                VCIncrementDiagnosticCategory(failureCategories, @"invalid HAPP add link");
                [failureTexts addObject:[self shortImportFailureTextForURL:urlString
                                                                errorText:@"HAPP add link does not contain a valid subscription URL"]];
                continue;
            }
            NSDictionary *sub = [self subscriptionDictionaryForURL:subscriptionURL
                                                 allowInsecureFetch:allowInsecureFetch
                                                     allowPlainHTTP:(allowPlainHTTP && !happSource &&
                                                                     URLStringUsesPlainHTTP(subscriptionURL))
                                                         happSource:happSource];
            NSString *errorText = nil;
            BOOL insecureRetryAvailable = NO;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                        errorText:&errorText
                                                           insecureRetryAvailable:&insecureRetryAvailable];
            if ([updated isKindOfClass:[NSDictionary class]]) {
                [importedSubs addObject:updated];
            } else if (!allowInsecureFetch && insecureRetryAvailable) {
                [insecureURLs addObject:urlString];
            } else if ([[fallbackSubscriptions objectForKey:subscriptionURL] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *fallback = [fallbackSubscriptions objectForKey:subscriptionURL];
                if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(subscriptionURL)) {
                    NSMutableDictionary *approvedFallback = [NSMutableDictionary dictionaryWithDictionary:fallback];
                    [approvedFallback setObject:[NSNumber numberWithBool:YES]
                                         forKey:kSubscriptionAllowPlainHTTPKey];
                    fallback = approvedFallback;
                }
                [importedSubs addObject:fallback];
                fallbackCount++;
            } else {
                failedCount++;
                VCIncrementDiagnosticCategory(failureCategories, errorText);
                [failureTexts addObject:[self shortImportFailureTextForURL:urlString errorText:errorText]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;

            NSUInteger addedCount = 0;
            NSInteger lastAddedIndex = -1;
            BOOL savedPlainHTTPApproval = NO;
            for (NSDictionary *sub in importedSubs) {
                NSString *urlString = [sub objectForKey:@"url"];
                if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) continue;
                NSInteger existingIndex = [self existingSubscriptionIndexForURL:urlString];
                if (existingIndex >= 0) {
                    NSDictionary *existingSub = [_subscriptions objectAtIndex:existingIndex];
                    if (SubscriptionDictionaryAllowsPlainHTTP(sub) &&
                        !SubscriptionDictionaryAllowsPlainHTTP(existingSub)) {
                        NSMutableDictionary *approved = [NSMutableDictionary dictionaryWithDictionary:existingSub];
                        [approved setObject:[NSNumber numberWithBool:YES]
                                    forKey:kSubscriptionAllowPlainHTTPKey];
                        [_subscriptions replaceObjectAtIndex:existingIndex withObject:approved];
                        savedPlainHTTPApproval = YES;
                    }
                    continue;
                }

                [_subscriptions addObject:sub];
                addedCount++;
                lastAddedIndex = [_subscriptions count] - 1;
            }

            if (addedCount > 0 || savedPlainHTTPApproval) {
                [self saveData];
            }
            if (addedCount > 0) {
                [self selectSubscriptionAtIndex:lastAddedIndex];
            } else {
                [self normalizeSelection];
                [_tableView reloadData];
            }

            NSMutableArray *parts = [NSMutableArray array];
            if ([prefixPart isKindOfClass:[NSString class]] && [prefixPart length] > 0) {
                [parts addObject:prefixPart];
            }
            if (addedCount > 0) {
                [parts addObject:[self subscriptionImportCountText:addedCount]];
            }

            NSString *status = nil;
            if ([parts count] > 0) {
                status = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            } else {
                status = @"No subscriptions imported";
            }
            if (failedCount > 0) {
                status = [NSString stringWithFormat:@"%@ (failed: %@)",
                          status,
                          [self subscriptionImportCountText:failedCount]];
            }
            if (fallbackCount > 0) {
                status = [NSString stringWithFormat:@"%@ (%lu restored from backup cache)",
                          status,
                          (unsigned long)fallbackCount];
            }
            if ([insecureURLs count] > 0) {
                status = [NSString stringWithFormat:@"%@; %@ require insecure mode",
                          status,
                          [self subscriptionImportCountText:[insecureURLs count]]];
            }
            [self showStatus:status ok:([parts count] > 0 || [insecureURLs count] > 0)];

            if ([insecureURLs count] > 0) {
                BOOL allHappSources = YES;
                for (NSString *urlString in insecureURLs) {
                    if (![self isHappEncryptedLink:urlString] && ![self isHappAddLink:urlString]) {
                        allHappSources = NO;
                        break;
                    }
                }
                [self showInsecureSubscriptionImportPromptForURLs:insecureURLs
                                                   fromBatchImport:([urlsToImport count] > 1)
                                                        happSource:allHappSources];
            }
            if ([failureTexts count] > 0) {
                [self showSubscriptionImportFailures:failureTexts];
            }
            VCRecordAppEvent(@"import", @"Batch subscription import finished",
                             [NSString stringWithFormat:@"requested=%lu added=%lu failed=%lu failure_types=%@ fallback=%lu pending_insecure=%lu duration_ms=%.0f",
                              (unsigned long)[urlsToImport count],
                              (unsigned long)addedCount,
                              (unsigned long)failedCount,
                              VCDiagnosticCategoryCountsText(failureCategories),
                              (unsigned long)fallbackCount,
                              (unsigned long)[insecureURLs count],
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);

            [importedSubs release];
            [insecureURLs release];
            [failureTexts release];
            [failureCategories release];
            [urlsToImport release];
            [prefixPart release];
            [fallbackSubscriptions release];
        });

        [pool drain];
    });
}

- (void)importDirectURI:(NSString *)uri {
    VCRecordAppEvent(@"import", @"Configuration import started", @"type=direct");
    NSString *normalizedURI = [self safeTrim:uri];
    if (![normalizedURI isKindOfClass:[NSString class]] || [normalizedURI length] == 0) {
        VCRecordAppEvent(@"import", @"Configuration import failed", @"reason=empty");
        [self showStatus:@"Invalid configuration link" ok:NO];
        return;
    }
    if (![self isSupportedConfigTupleForURI:normalizedURI]) {
        VCRecordAppEvent(@"import", @"Configuration import failed", @"reason=unsupported");
        [self showStatus:[self unsupportedConfigStatusTextForURI:normalizedURI] ok:NO];
        return;
    }

    NSInteger existing = [self existingConfigIndexForURI:normalizedURI];
    if (existing >= 0) {
        VCRecordAppEvent(@"import", @"Configuration import skipped", @"reason=duplicate");
        _configurationsSectionExpanded = YES;
        _selectedConfigIndex = existing;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        [self normalizeSelection];
        [self saveData];
        [_tableView reloadData];
        [self showStatus:@"Configuration already exists (skipped)" ok:YES];
        return;
    }

    NSString *name = [self displayNameForURI:normalizedURI index:[_configs count]];
    NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                         name, @"name",
                         normalizedURI, @"uri",
                         nil];
    [_configs addObject:cfg];
    VCRecordAppEvent(@"import", @"Configuration imported",
                     [NSString stringWithFormat:@"configs=%lu", (unsigned long)[_configs count]]);

    _configurationsSectionExpanded = YES;
    _selectedConfigIndex = [_configs count] - 1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    [self saveData];
    [_tableView reloadData];
    [self showStatus:@"Configuration imported" ok:YES];
}

- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
               allowPlainHTTP:(BOOL)allowPlainHTTP
                   happSource:(BOOL)happSource {
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Subscription import started",
                     [NSString stringWithFormat:@"happ=%d insecure=%d plain_http=%d",
                      happSource ? 1 : 0, allowInsecureFetch ? 1 : 0, allowPlainHTTP ? 1 : 0]);
    NSString *normalizedURL = [self safeTrim:urlString];
    if (![normalizedURL isKindOfClass:[NSString class]] || [normalizedURL length] == 0) {
        VCRecordAppEvent(@"import", @"Subscription import failed", @"reason=empty");
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    NSInteger existing = [self existingSubscriptionIndexForURL:normalizedURL];
    if (!happSource && URLStringUsesPlainHTTP(normalizedURL) && !allowPlainHTTP) {
        if (existing >= 0 &&
            SubscriptionDictionaryAllowsPlainHTTP([_subscriptions objectAtIndex:existing])) {
            allowPlainHTTP = YES;
        } else {
            VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=plain_http_confirmation");
            [self showPlainHTTPSubscriptionWarningForCount:1 confirmation:^{
                [self importSubscriptionURL:normalizedURL
                         allowInsecureFetch:allowInsecureFetch
                             allowPlainHTTP:YES
                                  happSource:NO];
            }];
            return;
        }
    }

    if (existing >= 0) {
        NSArray *items = [self subscriptionItemsAtIndex:existing];
        if (!allowInsecureFetch && [items count] > 0) {
            NSDictionary *existingSubscription = [_subscriptions objectAtIndex:existing];
            BOOL needsHappFlag = happSource && !SubscriptionDictionaryUsesHappHeaders(existingSubscription);
            BOOL needsPlainHTTPFlag = allowPlainHTTP && !happSource &&
                                      URLStringUsesPlainHTTP(normalizedURL) &&
                                      !SubscriptionDictionaryAllowsPlainHTTP(existingSubscription);
            if (needsHappFlag || needsPlainHTTPFlag) {
                NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithDictionary:existingSubscription];
                if (needsHappFlag) {
                    [stored setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
                }
                if (needsPlainHTTPFlag) {
                    [stored setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
                }
                [_subscriptions replaceObjectAtIndex:existing withObject:stored];
                [self saveData];
            }
            [self selectSubscriptionAtIndex:existing];
            VCRecordAppEvent(@"import", @"Subscription import skipped", @"reason=duplicate");
            [self showStatus:@"Subscription already exists (skipped)" ok:YES];
            return;
        }

        NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithDictionary:[_subscriptions objectAtIndex:existing]];
        [sub setObject:normalizedURL forKey:@"url"];
        if (allowInsecureFetch) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
        }
        if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(normalizedURL)) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
        }
        if (happSource) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
        }

        NSString *errorText = nil;
        BOOL insecureRetryAvailable = NO;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                    errorText:&errorText
                                                       insecureRetryAvailable:&insecureRetryAvailable];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            VCRecordAppEvent(@"import", @"Subscription fetched",
                             [NSString stringWithFormat:@"result=update configs=%lu duration_ms=%.0f",
                              (unsigned long)[[updated objectForKey:@"items"] count],
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
            [self commitUpdatedSubscription:updated existingIndex:existing];
            return;
        }

        if (!allowInsecureFetch &&
            !SubscriptionDictionaryAllowsInsecureFetch(sub) &&
            insecureRetryAvailable) {
            VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=insecure_confirmation");
            [self showInsecureSubscriptionImportPromptForURL:normalizedURL
                                                  happSource:SubscriptionDictionaryUsesHappHeaders(sub)];
            return;
        }

        VCRecordAppEvent(@"import", @"Subscription import failed",
                         [NSString stringWithFormat:@"stage=fetch error=%@ duration_ms=%.0f",
                          VCDiagnosticErrorSummary(errorText),
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
        return;
    }

    NSDictionary *sub = [self subscriptionDictionaryForURL:normalizedURL
                                         allowInsecureFetch:allowInsecureFetch
                                             allowPlainHTTP:allowPlainHTTP
                                                 happSource:happSource];
    NSString *errorText = nil;
    BOOL insecureRetryAvailable = NO;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                errorText:&errorText
                                                   insecureRetryAvailable:&insecureRetryAvailable];
    if ([updated isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"import", @"Subscription fetched",
                         [NSString stringWithFormat:@"result=new configs=%lu duration_ms=%.0f",
                          (unsigned long)[[updated objectForKey:@"items"] count],
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        [self commitUpdatedSubscription:updated existingIndex:-1];
        return;
    }

    if (!allowInsecureFetch && insecureRetryAvailable) {
        VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=insecure_confirmation");
        [self showInsecureSubscriptionImportPromptForURL:normalizedURL happSource:happSource];
        return;
    }

    VCRecordAppEvent(@"import", @"Subscription import failed",
                     [NSString stringWithFormat:@"stage=fetch error=%@ duration_ms=%.0f",
                      VCDiagnosticErrorSummary(errorText),
                      ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
    [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
}

- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
                   happSource:(BOOL)happSource {
    [self importSubscriptionURL:urlString
             allowInsecureFetch:allowInsecureFetch
                 allowPlainHTTP:NO
                      happSource:happSource];
}

- (void)importSubscriptionURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    [self importSubscriptionURL:urlString allowInsecureFetch:allowInsecureFetch happSource:NO];
}

- (void)importSubscriptionURL:(NSString *)urlString {
    [self importSubscriptionURL:urlString allowInsecureFetch:NO];
}

- (BOOL)isHappEncryptedLink:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;
    const char *utf8 = [text UTF8String];
    return utf8 && VCHappIsEncryptedLink(utf8);
}

- (BOOL)isHappAddLink:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;
    return [[text lowercaseString] hasPrefix:kHappAddPrefix];
}

- (NSString *)targetFromHappAddLink:(NSString *)link {
    if (![self isHappAddLink:link] || [link length] <= [kHappAddPrefix length]) return nil;
    return [self safeTrim:[link substringFromIndex:[kHappAddPrefix length]]];
}

- (NSString *)decryptedHappLink:(NSString *)link errorText:(NSString **)errorTextOut {
    if (errorTextOut) *errorTextOut = nil;

    const char *utf8 = [link UTF8String];
    if (!utf8) {
        if (errorTextOut) *errorTextOut = @"HAPP link is not valid UTF-8";
        return nil;
    }

    unsigned char *plaintext = NULL;
    size_t plaintextLength = 0;
    char error[256];
    char mode[16];
    memset(error, 0, sizeof(error));
    memset(mode, 0, sizeof(mode));
    int result = VCHappDecryptLink(utf8,
                                   &plaintext,
                                   &plaintextLength,
                                   mode,
                                   sizeof(mode),
                                   error,
                                   sizeof(error));
    if (result != 1 || !plaintext || plaintextLength == 0) {
        if (plaintext) VCHappFreePlaintext(plaintext);
        if (errorTextOut) {
            NSString *detail = (error[0] != '\0') ? [NSString stringWithUTF8String:error] : nil;
            *errorTextOut = ([detail length] > 0)
                                ? [NSString stringWithFormat:@"Invalid HAPP link: %@", detail]
                                : @"Invalid HAPP link";
        }
        return nil;
    }

    NSString *decoded = [[[NSString alloc] initWithBytes:plaintext
                                                   length:plaintextLength
                                                 encoding:NSUTF8StringEncoding] autorelease];
    VCHappFreePlaintext(plaintext);
    decoded = [self safeTrim:decoded];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        if (errorTextOut) *errorTextOut = @"HAPP payload is not valid UTF-8";
        return nil;
    }
    return decoded;
}

- (void)importHappEncryptedLink:(NSString *)link {
    NSString *errorText = nil;
    NSString *decoded = [self decryptedHappLink:link errorText:&errorText];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        [self showStatus:([errorText length] > 0 ? errorText : @"Invalid HAPP link") ok:NO];
        return;
    }

    if ([self isDirectConfigURI:decoded]) {
        [self importDirectURI:decoded];
        return;
    }
    if ([self isSubscriptionURL:decoded]) {
        [self importSubscriptionURL:link allowInsecureFetch:NO happSource:YES];
        return;
    }

    [self showStatus:@"HAPP link does not contain a supported config or subscription URL" ok:NO];
}

- (void)importHappAddLink:(NSString *)link {
    NSString *target = [self targetFromHappAddLink:link];
    if (![target isKindOfClass:[NSString class]] || [target length] == 0) {
        [self showStatus:@"HAPP add link does not contain an import URL" ok:NO];
        return;
    }

    if ([self isDirectConfigURI:target]) {
        [self importDirectURI:target];
        return;
    }
    if ([self isSubscriptionURL:target]) {
        [self importSubscriptionURL:target allowInsecureFetch:NO happSource:YES];
        return;
    }

    [self showStatus:@"HAPP add link does not contain a supported config or subscription URL" ok:NO];
}

- (void)importTextEntry:(NSString *)rawText {
    NSString *text = [self safeTrim:rawText];
    if ([text length] == 0) {
        VCRecordAppEvent(@"import", @"Import rejected", @"reason=empty_text");
        [self showStatus:@"Import text is empty" ok:NO];
        return;
    }

    NSString *karingError = nil;
    NSDictionary *karingDescriptor = VCKaringLANDownloadDescriptor(text, &karingError);
    if ([karingDescriptor isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"import", @"Karing LAN import recognized", nil);
        [self receiveKaringBackupWithDescriptor:karingDescriptor];
        return;
    }
    if ([karingError length] > 0) {
        VCRecordAppEvent(@"import", @"Import rejected", @"type=karing reason=invalid_descriptor");
        [self showStatus:karingError ok:NO];
        return;
    }

    if ([self isHappEncryptedLink:text]) {
        VCRecordAppEvent(@"import", @"HAPP encrypted import recognized", nil);
        [self importHappEncryptedLink:text];
        return;
    }

    if ([self isHappAddLink:text]) {
        VCRecordAppEvent(@"import", @"HAPP add import recognized", nil);
        [self importHappAddLink:text];
        return;
    }

    if ([[text lowercaseString] hasPrefix:@"happ://"]) {
        VCRecordAppEvent(@"import", @"Import rejected", @"type=happ reason=unsupported_format");
        [self showStatus:@"Unsupported HAPP link format (use happ://add/, crypt4/ or crypt5/)" ok:NO];
        return;
    }

    BOOL hasWhitespace = ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound);
    if (!hasWhitespace && [self isDirectConfigURI:text]) {
        [self importDirectURI:text];
        return;
    }

    if (!hasWhitespace && [self isSubscriptionURL:text]) {
        [self importSubscriptionURL:text];
        return;
    }

    NSArray *links = [self extractImportLinksFromText:text];
    if ([links count] > 0) {
        if ([links count] == 1) {
            NSString *single = [links objectAtIndex:0];
            if ([self isHappEncryptedLink:single]) {
                [self importHappEncryptedLink:single];
            } else if ([self isHappAddLink:single]) {
                [self importHappAddLink:single];
            } else if ([self isDirectConfigURI:single]) {
                [self importDirectURI:single];
            } else if ([self isSubscriptionURL:single]) {
                [self importSubscriptionURL:single];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
            return;
        }

        NSInteger importedConfigs = 0;
        NSInteger pendingSubs = 0;
        NSInteger skippedConfigs = 0;
        NSInteger skippedSubs = 0;
        NSMutableArray *subscriptionURLsToImport = [NSMutableArray array];

        for (NSString *link in links) {
            NSString *importLink = link;
            BOOL happEncryptedLink = [self isHappEncryptedLink:link];
            BOOL happAddLink = [self isHappAddLink:link];
            BOOL happLink = happEncryptedLink || happAddLink;
            if (happEncryptedLink) {
                NSString *decryptError = nil;
                NSString *decoded = [self decryptedHappLink:link errorText:&decryptError];
                if ([self isDirectConfigURI:decoded]) {
                    importLink = decoded;
                } else if ([self isSubscriptionURL:decoded]) {
                    importLink = link;
                } else {
                    skippedSubs++;
                    continue;
                }
            } else if (happAddLink) {
                NSString *target = [self targetFromHappAddLink:link];
                if ([self isDirectConfigURI:target] || [self isSubscriptionURL:target]) {
                    importLink = target;
                } else {
                    skippedSubs++;
                    continue;
                }
            }

            if ([self isDirectConfigURI:importLink]) {
                if (![self isSupportedConfigTupleForURI:importLink]) {
                    skippedConfigs++;
                    continue;
                }
                if ([self existingConfigIndexForURI:importLink] >= 0) {
                    skippedConfigs++;
                    continue;
                }

                NSString *name = [self displayNameForURI:importLink index:[_configs count]];
                NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                                     name, @"name",
                                     importLink, @"uri",
                                     nil];
                [_configs addObject:cfg];
                importedConfigs++;
            } else if ([self isSubscriptionURL:importLink] || happLink) {
                if ([self existingSubscriptionIndexForURL:importLink] >= 0) {
                    skippedSubs++;
                    continue;
                }

                NSString *queuedLink = happAddLink ? link : importLink;
                if (![subscriptionURLsToImport containsObject:queuedLink]) {
                    [subscriptionURLsToImport addObject:queuedLink];
                    pendingSubs++;
                }
            }
        }

        if (importedConfigs > 0 || pendingSubs > 0) {
            if (importedConfigs > 0) {
                _configurationsSectionExpanded = YES;
                _selectedConfigIndex = [_configs count] - 1;
                _selectedSubIndex = -1;
                _selectedSubItemIndex = -1;
                [self normalizeSelection];
                [self saveData];
                [_tableView reloadData];
            }
        }

        NSMutableArray *parts = [NSMutableArray array];
        if (importedConfigs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld config%@", (long)importedConfigs, (importedConfigs == 1 ? @"" : @"s")]];
        }
        if (pendingSubs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)pendingSubs, (pendingSubs == 1 ? @"" : @"s")]];
        }

        if ([parts count] > 0) {
            VCRecordAppEvent(@"import", @"Text import parsed",
                             [NSString stringWithFormat:@"configs=%ld subscriptions=%ld skipped_configs=%ld skipped_subscriptions=%ld",
                              (long)importedConfigs,
                              (long)pendingSubs,
                              (long)skippedConfigs,
                              (long)skippedSubs]);
            NSString *importText = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                importText = [NSString stringWithFormat:@"%@ (skipped duplicates: %@)",
                              importText,
                              [skippedParts componentsJoinedByString:@", "]];
            }

            if ([subscriptionURLsToImport count] > 0) {
                NSString *configPart = nil;
                if (importedConfigs > 0) {
                    configPart = [NSString stringWithFormat:@"%ld config%@",
                                  (long)importedConfigs,
                                  (importedConfigs == 1 ? @"" : @"s")];
                }
                [self startBackgroundSubscriptionImportForURLs:subscriptionURLsToImport
                                            allowInsecureFetch:NO
                                                   startStatus:@"Importing subscriptions from file..."
                                            importedPrefixPart:configPart];
            } else {
                [self showStatus:importText ok:YES];
            }
        } else {
            VCRecordAppEvent(@"import", @"Text import produced no new entries",
                             [NSString stringWithFormat:@"skipped_configs=%ld skipped_subscriptions=%ld",
                              (long)skippedConfigs,
                              (long)skippedSubs]);
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                [self showStatus:[NSString stringWithFormat:@"Nothing imported: all links already exist (%@)",
                                  [skippedParts componentsJoinedByString:@", "]]
                             ok:YES];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
        }
        return;
    }

    VCRecordAppEvent(@"import", @"Import rejected", @"reason=unsupported_format");
    [self showStatus:@"Unsupported import format (use vless://, socks5://, happ://, karing://sync-download/, or an HTTP(S) subscription)" ok:NO];
}

- (void)importKaringSubscriptionEntries:(NSArray *)entries {
    if (![entries isKindOfClass:[NSArray class]] || [entries count] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup contained no entries", nil);
        [self showStatus:@"The Karing backup has no supported subscriptions" ok:NO];
        return;
    }

    NSMutableArray *urls = [NSMutableArray array];
    NSMutableDictionary *cachedSubscriptions = [NSMutableDictionary dictionary];
    NSUInteger duplicateCount = 0;
    for (id value in entries) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = [self safeTrim:[value objectForKey:@"url"]];
        if (![self isSubscriptionURL:url] || [urls containsObject:url]) continue;
        if ([self existingSubscriptionIndexForURL:url] >= 0) {
            duplicateCount++;
            continue;
        }
        [urls addObject:url];

        NSArray *storedItems = [value objectForKey:@"items"];
        NSMutableArray *supportedItems = [NSMutableArray array];
        if ([storedItems isKindOfClass:[NSArray class]]) {
            for (id item in storedItems) {
                if (![item isKindOfClass:[NSString class]]) continue;
                if ([self isSupportedConfigTupleForURI:item] && ![supportedItems containsObject:item]) {
                    [supportedItems addObject:item];
                }
            }
        }
        if ([supportedItems count] > 0) {
            NSMutableDictionary *subscription =
                [NSMutableDictionary dictionaryWithDictionary:
                 [self subscriptionDictionaryForURL:url allowInsecureFetch:NO]];
            [subscription setObject:supportedItems forKey:@"items"];
            [cachedSubscriptions setObject:subscription forKey:url];
        }
    }

    if ([urls count] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup produced no new subscriptions",
                         [NSString stringWithFormat:@"entries=%lu duplicates=%lu",
                          (unsigned long)[entries count],
                          (unsigned long)duplicateCount]);
        [self showStatus:(duplicateCount > 0
                          ? @"All Karing subscriptions already exist"
                          : @"The Karing backup has no supported subscriptions")
                     ok:(duplicateCount > 0)];
        return;
    }

    VCRecordAppEvent(@"import", @"Karing subscriptions parsed",
                     [NSString stringWithFormat:@"entries=%lu queued=%lu duplicates=%lu cached=%lu",
                      (unsigned long)[entries count],
                      (unsigned long)[urls count],
                      (unsigned long)duplicateCount,
                      (unsigned long)[cachedSubscriptions count]]);
    [self startBackgroundSubscriptionImportForURLs:urls
                               allowInsecureFetch:NO
                                      startStatus:@"Importing Karing subscriptions..."
                               importedPrefixPart:nil
                      fallbackSubscriptionsByURL:cachedSubscriptions];
}

- (void)importKaringBackupData:(NSData *)data {
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup read failed", @"reason=empty_data");
        [self showStatus:@"Unable to read the Karing backup" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Karing backup parsing started",
                     [NSString stringWithFormat:@"bytes=%lu", (unsigned long)[data length]]);
    [self showStatus:@"Reading Karing backup..." ok:YES];
    NSData *copiedData = [data copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = nil;
        NSArray *entries = VCKaringSubscriptionsFromBackupData(copiedData, &errorText);
        NSArray *copiedEntries = [entries copy];
        NSString *copiedError = [errorText copy];

        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;
            if ([copiedEntries isKindOfClass:[NSArray class]]) {
                VCRecordAppEvent(@"import", @"Karing backup parsed",
                                 [NSString stringWithFormat:@"entries=%lu duration_ms=%.0f",
                                  (unsigned long)[copiedEntries count],
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self importKaringSubscriptionEntries:copiedEntries];
            } else {
                VCRecordAppEvent(@"import", @"Karing backup parsing failed",
                                 [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                                  VCDiagnosticErrorSummary(copiedError),
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self showStatus:([copiedError length] > 0
                                  ? copiedError
                                  : @"Unable to read the Karing backup")
                             ok:NO];
            }
            [copiedEntries release];
            [copiedError release];
            [copiedData release];
        });
        [pool drain];
    });
}

- (void)receiveKaringBackupWithDescriptor:(NSDictionary *)descriptor {
    NSArray *hosts = [descriptor objectForKey:@"hosts"];
    NSInteger port = [[descriptor objectForKey:@"port"] integerValue];
    if (![hosts isKindOfClass:[NSArray class]] || [hosts count] == 0 ||
        port < 1 || port > 65535) {
        VCRecordAppEvent(@"import", @"Karing LAN sync rejected", @"reason=invalid_descriptor");
        [self showStatus:@"Invalid Karing LAN sync address" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Karing LAN sync started",
                     [NSString stringWithFormat:@"candidate_hosts=%lu", (unsigned long)[hosts count]]);
    [self showStatus:@"Receiving Karing backup..." ok:YES];
    NSDictionary *copiedDescriptor = [descriptor copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *downloadHosts = [copiedDescriptor objectForKey:@"hosts"];
        NSInteger downloadPort = [[copiedDescriptor objectForKey:@"port"] integerValue];
        NSArray *entries = nil;
        NSString *lastError = nil;

        for (NSString *host in downloadHosts) {
            NSString *routeAdd = [NSString stringWithFormat:@"ROUTE_DIRECT_ADD\t%@\n", host];
            NSString *routeRemove = [NSString stringWithFormat:@"ROUTE_DIRECT_REMOVE\t%@\n", host];
            (void)SendCommand(routeAdd);

            NSString *baseURLText = [NSString stringWithFormat:@"http://%@:%ld",
                                     host, (long)downloadPort];
            NSMutableURLRequest *probe =
                [NSMutableURLRequest requestWithURL:
                 [NSURL URLWithString:[baseURLText stringByAppendingString:@"/"]]
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:3.0];
            [probe setValue:@"close" forHTTPHeaderField:@"Connection"];

            NSURLResponse *response = nil;
            NSError *requestError = nil;
            (void)[NSURLConnection sendSynchronousRequest:probe
                                         returningResponse:&response
                                                     error:&requestError];
            NSInteger probeStatus = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                probeStatus = [(NSHTTPURLResponse *)response statusCode];
            }
            if (requestError || (probeStatus != 200 && probeStatus != 404)) {
                lastError = requestError
                    ? [requestError localizedDescription]
                    : [NSString stringWithFormat:@"Karing probe returned HTTP %ld",
                       (long)probeStatus];
                (void)SendCommand(routeRemove);
                continue;
            }

            NSMutableURLRequest *request =
                [NSMutableURLRequest requestWithURL:
                 [NSURL URLWithString:[baseURLText stringByAppendingString:@"/sync-download"]]
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:20.0];
            [request setValue:@"close" forHTTPHeaderField:@"Connection"];
            response = nil;
            requestError = nil;
            NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&requestError];
            (void)SendCommand(routeRemove);

            NSInteger statusCode = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = [(NSHTTPURLResponse *)response statusCode];
            }
            if (requestError || !data || [data length] == 0 || statusCode != 200) {
                if (requestError) {
                    lastError = [requestError localizedDescription];
                } else if (statusCode != 0) {
                    lastError = [NSString stringWithFormat:@"Karing returned HTTP %ld", (long)statusCode];
                } else {
                    lastError = @"Karing returned an empty response";
                }
                continue;
            }
            if ([data length] > 32U * 1024U * 1024U) {
                lastError = @"The Karing backup is too large";
                continue;
            }

            NSString *parseError = nil;
            entries = VCKaringSubscriptionsFromBackupData(data, &parseError);
            if ([entries isKindOfClass:[NSArray class]]) break;
            lastError = parseError;
        }

        NSArray *copiedEntries = [entries copy];
        NSString *copiedError = [lastError copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;
            if ([copiedEntries isKindOfClass:[NSArray class]]) {
                VCRecordAppEvent(@"import", @"Karing LAN sync finished",
                                 [NSString stringWithFormat:@"entries=%lu duration_ms=%.0f",
                                  (unsigned long)[copiedEntries count],
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self importKaringSubscriptionEntries:copiedEntries];
            } else {
                VCRecordAppEvent(@"import", @"Karing LAN sync failed",
                                 [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                                  VCDiagnosticErrorSummary(copiedError),
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                NSString *message = ([copiedError length] > 0)
                    ? [NSString stringWithFormat:@"Karing sync failed: %@", copiedError]
                    : @"Karing sync failed: no LAN address responded";
                [self showStatus:message ok:NO];
            }
            [copiedEntries release];
            [copiedError release];
            [copiedDescriptor release];
        });
        [pool drain];
    });
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

- (void)importTextFileAtPath:(NSString *)rawPath {
    VCRecordAppEvent(@"import", @"File import started", nil);
    NSString *path = [self safeTrim:rawPath];
    if ([path hasPrefix:@"\""] && [path hasSuffix:@"\""] && [path length] >= 2) {
        path = [path substringWithRange:NSMakeRange(1, [path length] - 2)];
        path = [self safeTrim:path];
    }
    path = [path stringByExpandingTildeInPath];
    if ([path length] == 0) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=path_validation");
        [self showStatus:@"File path is empty" ok:NO];
        return;
    }

    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (exists && isDir) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=file_selection");
        [self showStatus:@"Import file not found" ok:NO];
        return;
    }

    [self showStatus:@"Importing data from file..." ok:YES];

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] == 0) {
        if (!exists) {
            VCRecordAppEvent(@"import", @"File import failed", @"stage=file_missing");
            [self showStatus:@"Import file not found" ok:NO];
            return;
        }
        VCRecordAppEvent(@"import", @"File import failed", @"stage=file_read");
        [self showStatus:@"Failed to read import file" ok:NO];
        return;
    }

    if (VCKaringBackupDataLooksLikeZip(data)) {
        VCRecordAppEvent(@"import", @"Karing backup detected", nil);
        [self importKaringBackupData:data];
        return;
    }

    NSString *text = [self decodeImportTextData:data];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=text_decode");
        [self showStatus:@"Unsupported text encoding" ok:NO];
        return;
    }

    [self importTextEntry:text];
}

- (void)importFileAtURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]] || ![url isFileURL]) {
        VCRecordAppEvent(@"import", @"File import rejected", @"reason=unsupported_url");
        [self showStatus:@"Unsupported import file URL" ok:NO];
        return;
    }
    NSString *path = [url path];
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
        [self showStatus:@"Import file path is empty" ok:NO];
        return;
    }
    [self importTextFileAtPath:path];
}

- (void)startFileBrowserImportFlow {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:kImportDirectoryPath isDirectory:&isDirectory] || !isDirectory) {
        VCRecordAppEvent(@"import", @"File browser unavailable", nil);
        [self showStatus:@"Import directory is unavailable" ok:NO];
        return;
    }

    VCImportBrowserVC *browser = [[[VCImportBrowserVC alloc] initWithRootPath:kImportDirectoryPath
                                                                directoryPath:kImportDirectoryPath
                                                                     delegate:self] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:browser] autorelease];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
    VCRecordAppEvent(@"ui", @"File browser opened", nil);
}

- (void)importBrowserDidCancel:(UIViewController *)browser {
    (void)browser;
    [self dismissViewControllerAnimated:YES completion:nil];
    VCRecordAppEvent(@"import", @"File browser canceled", nil);
}

- (void)importBrowser:(UIViewController *)browser didSelectFileAtPath:(NSString *)path {
    (void)browser;
    NSString *selectedPath = [path copy];
    VCRecordAppEvent(@"import", @"File selected", nil);
    [self dismissViewControllerAnimated:YES completion:^{
        [self importTextFileAtPath:selectedPath];
        [selectedPath release];
    }];
}

- (void)startQRImportFlow {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        VCRecordAppEvent(@"import", @"QR scanner unavailable", @"reason=camera_unavailable");
        [self showStatus:@"Camera is unavailable" ok:NO];
        return;
    }

    QRScanVC *scanner = [[[QRScanVC alloc] init] autorelease];
    scanner.delegate = self;
    scanner.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:scanner animated:YES completion:nil];
    VCRecordAppEvent(@"ui", @"QR scanner opened", nil);
    [self showStatus:@"Scan QR code to import links..." ok:YES];
}

- (NSString *)uriForCurrentSelection {
    if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        NSDictionary *cfg = [_configs objectAtIndex:_selectedConfigIndex];
        NSString *uri = [cfg objectForKey:@"uri"];
        if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
            return uri;
        }
    }

    if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        NSDictionary *sub = [_subscriptions objectAtIndex:_selectedSubIndex];
        NSArray *items = [sub objectForKey:@"items"];
        if (![items isKindOfClass:[NSArray class]] || [items count] == 0) {
            if (![self refreshSubscriptionAtIndex:_selectedSubIndex showStatus:NO]) {
                return nil;
            }
            sub = [_subscriptions objectAtIndex:_selectedSubIndex];
            items = [sub objectForKey:@"items"];
        }

        if ([items isKindOfClass:[NSArray class]] && [items count] > 0) {
            NSInteger idx = _selectedSubItemIndex;
            if (idx < 0 || idx >= (NSInteger)[items count]) idx = 0;
            NSString *uri = [items objectAtIndex:idx];
            if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
                return uri;
            }
        }
    }

    return nil;
}

- (BOOL)selectedSubscriptionIsHappEncrypted {
    if (_selectedSubIndex < 0 || _selectedSubIndex >= (NSInteger)[_subscriptions count]) {
        return NO;
    }
    return SubscriptionDictionaryIsHappEncrypted([_subscriptions objectAtIndex:_selectedSubIndex]);
}

- (void)reconnectToURIIfNeededFrom:(NSString *)oldURI to:(NSString *)newURI {
    if (!_connected) return;
    if (![oldURI isKindOfClass:[NSString class]] || ![newURI isKindOfClass:[NSString class]]) return;
    if ([oldURI length] == 0 || [newURI length] == 0) return;
    BOOL protectLogs = [self selectedSubscriptionIsHappEncrypted];
    if ([oldURI isEqualToString:newURI] && _connectedWithProtectedLogs == protectLogs) return;
    if (![self isSupportedConfigTupleForURI:newURI]) {
        [self showStatus:[self unsupportedConfigStatusTextForURI:newURI] ok:NO];
        return;
    }

    [_pendingReconnectURI release];
    _pendingReconnectURI = [newURI copy];
    _pendingReconnectProtectLogs = protectLogs;
    VCRecordAppEvent(@"connection", @"Configuration switch queued", protectLogs ? @"protected_logs=1" : @"protected_logs=0");
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(beginPendingReconnect)
                                               object:nil];
    if (!_reconnectInProgress) {
        [self performSelector:@selector(beginPendingReconnect) withObject:nil afterDelay:0.2];
    }
    [self showStatus:@"Switching to selected config..." ok:YES];
}

- (void)beginPendingReconnect {
    if (_reconnectInProgress || ![_pendingReconnectURI length]) return;
    VCRecordAppEvent(@"connection", @"Configuration switch started", nil);

    NSString *uri = [_pendingReconnectURI copy];
    BOOL protectLogs = _pendingReconnectProtectLogs;
    [_pendingReconnectURI release];
    _pendingReconnectURI = nil;
    _pendingReconnectProtectLogs = NO;
    _reconnectInProgress = YES;

    NSString *routingCommand = [[NSString stringWithFormat:@"ROUTING\t%@\n", RoutingPolicyText()] copy];
    NSString *connectCommand = [ConnectCommandForURI(uri, protectLogs) copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *disconnectResponse = [SendCommand(@"DISCONNECT\n") copy];
        NSString *routingResponse = nil;
        NSString *connectResponse = nil;
        if ([disconnectResponse hasPrefix:@"OK"]) {
            routingResponse = [SendCommand(routingCommand) copy];
            if ([routingResponse hasPrefix:@"OK"]) {
                connectResponse = [SendCommand(connectCommand) copy];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *disconnectText = [self sanitizeDaemonText:disconnectResponse];
            NSString *routingText = [self sanitizeDaemonText:routingResponse];
            NSString *connectText = [self sanitizeDaemonText:connectResponse];
            BOOL disconnected = [disconnectText hasPrefix:@"OK"];
            BOOL routingSaved = disconnected && [routingText hasPrefix:@"OK"];
            BOOL connected = routingSaved && [connectText hasPrefix:@"OK"];

            if (connected) {
                VCRecordAppEvent(@"connection", @"Configuration switch completed", nil);
                _connected = YES;
                _connectedWithProtectedLogs = protectLogs;
                [self startUptimeTimer];
                [self updateConnectButton];
                [self showStatus:@"Connected (switched config)" ok:YES];
            } else if (!disconnected) {
                VCRecordAppEvent(@"connection", @"Configuration switch failed", @"stage=disconnect");
                [self showStatus:[NSString stringWithFormat:@"Reconnect failed (disconnect): %@", disconnectText] ok:NO];
            } else {
                _connected = NO;
                _connectedWithProtectedLogs = NO;
                [self stopUptimeTimer];
                [self updateConnectButton];
                NSString *stage = routingSaved ? @"connect" : @"routing";
                VCRecordAppEvent(@"connection", @"Configuration switch failed",
                                 [NSString stringWithFormat:@"stage=%@", stage]);
                NSString *detail = routingSaved ? connectText : routingText;
                [self showStatus:[NSString stringWithFormat:@"Reconnect failed (%@): %@", stage, detail] ok:NO];
            }

            _reconnectInProgress = NO;
            if ([_pendingReconnectURI isEqualToString:uri] &&
                _pendingReconnectProtectLogs == protectLogs) {
                [_pendingReconnectURI release];
                _pendingReconnectURI = nil;
                _pendingReconnectProtectLogs = NO;
            }
            if ([_pendingReconnectURI length]) {
                [self performSelector:@selector(beginPendingReconnect) withObject:nil afterDelay:0.05];
            } else if (connected) {
                [self scheduleXHTTPConnectHealthCheckForURI:uri];
            }

            [disconnectResponse release];
            [routingResponse release];
            [connectResponse release];
            [routingCommand release];
            [connectCommand release];
            [uri release];
        });
        [pool drain];
    });
}

- (void)togglePressed {
    VCRecordAppEvent(@"ui", _connected ? @"Disconnect button pressed" : @"Connect button pressed", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    if (_reconnectInProgress) {
        VCRecordAppEvent(@"connection", @"Connection action blocked", @"reason=config_switch_in_progress");
        [self showStatus:@"Config switch is still in progress" ok:YES];
        return;
    }
    if (_pendingReconnectURI) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(beginPendingReconnect)
                                                   object:nil];
        [_pendingReconnectURI release];
        _pendingReconnectURI = nil;
        _pendingReconnectProtectLogs = NO;
    }
    if (!_connected) {
        NSString *uri = [self uriForCurrentSelection];
        if (!uri) {
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=selection reason=none_selected");
            [self showStatus:@"Select/import a configuration first" ok:NO];
            return;
        }
        if (![self isSupportedConfigTupleForURI:uri]) {
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=validation reason=unsupported_config");
            [self showStatus:[self unsupportedConfigStatusTextForURI:uri] ok:NO];
            return;
        }

        NSString *routingResp = [self sanitizeDaemonText:SyncRoutingPolicyToDaemon()];
        if (![routingResp hasPrefix:@"OK"]) {
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=routing_sync");
            [self showStatus:[NSString stringWithFormat:@"Routing sync failed: %@", routingResp] ok:NO];
            return;
        }
        BOOL protectLogs = [self selectedSubscriptionIsHappEncrypted];
        NSString *cmd = ConnectCommandForURI(uri, protectLogs);
        NSString *resp = [self sanitizeDaemonText:SendCommand(cmd)];
        if ([resp hasPrefix:@"OK"]) {
            VCRecordAppEvent(@"connection", @"VPN connected", protectLogs ? @"protected_logs=1" : @"protected_logs=0");
            _connected = YES;
            _connectedWithProtectedLogs = protectLogs;
            [self startUptimeTimer];
            [self updateConnectButton];
            [self showStatus:@"Connected" ok:YES];
            [self scheduleXHTTPConnectHealthCheckForURI:uri];
        } else {
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=daemon_connect");
            [self showStatus:resp ok:NO];
        }
        return;
    }

    NSString *resp = [self sanitizeDaemonText:SendCommand(@"DISCONNECT\n")];
    if ([resp hasPrefix:@"OK"]) {
        VCRecordAppEvent(@"connection", @"VPN disconnected", nil);
        _connected = NO;
        _connectedWithProtectedLogs = NO;
        [self stopUptimeTimer];
        [self updateConnectButton];
        [self showStatus:@"Ready" ok:YES];
    } else {
        VCRecordAppEvent(@"connection", @"Disconnect failed", nil);
        [self showStatus:resp ok:NO];
    }
}

- (void)plusPressed {
    VCRecordAppEvent(@"ui", @"Import menu opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Import"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"Import from Clipboard", @"Import from File", @"Scan QR Code", @"Manual Input", nil] autorelease];
    sheet.tag = VCActionSheetTagImport;
    [sheet showInView:self.view];
}

- (void)refreshPressed {
    VCRecordAppEvent(@"ui", @"Refresh subscriptions button pressed", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    [self startBackgroundSubscriptionRefreshWithStatus:@"Updating subscriptions..."];
}

- (void)settingsPressed {
    VCRecordAppEvent(@"ui", @"Settings opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    SettingsVC *settings = [[[SettingsVC alloc] init] autorelease];
    settings.autoUpdate = _autoUpdateSubscriptions;
    settings.preserveCustomNames = _preserveCustomSubscriptionNames;
    settings.stealthMode = _stealthModeEnabled;
    settings.darkTheme = _darkThemeEnabled;
    settings.automaticUpdateChecks = _automaticUpdateChecksEnabled;
    settings.delegate = self;

    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:settings] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)subscriptionInfoButtonPressed:(UIButton *)sender {
    NSInteger index = sender.tag - kVCSubscriptionInfoButtonTagBase;
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;
    VCRecordAppEvent(@"ui", @"Subscription details opened", nil);

    NSDictionary *subscription = [_subscriptions objectAtIndex:index];
    SubscriptionInfoVC *info = [[[SubscriptionInfoVC alloc] initWithSubscription:subscription
                                                                           index:index
                                                                     stealthMode:_stealthModeEnabled
                                                                        delegate:self] autorelease];
    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:info] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)refreshPresentedSubscriptionInfoIfNeeded {
    UIViewController *presented = self.presentedViewController;
    if (![presented isKindOfClass:[UINavigationController class]]) return;
    UIViewController *top = [(UINavigationController *)presented topViewController];
    if (![top isKindOfClass:[SubscriptionInfoVC class]]) return;

    SubscriptionInfoVC *info = (SubscriptionInfoVC *)top;
    NSInteger index = [info subscriptionIndex];
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;
    [info reloadWithSubscription:[_subscriptions objectAtIndex:index]];
}

- (void)subscriptionInfoVCRequestedRefresh:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index {
    if (_launchAutoUpdateInProgress) {
        [vc finishRefreshWithSubscription:nil errorText:@"Another subscription update is already running"];
        return;
    }
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) {
        [vc finishRefreshWithSubscription:nil errorText:@"Subscription no longer exists"];
        return;
    }
    if ([self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
        [self showPlainHTTPSubscriptionWarningForCount:1
                                          confirmation:^{
                                              if ([self approvePlainHTTPForSubscriptionAtIndex:index]) {
                                                  [self saveData];
                                                  [self subscriptionInfoVCRequestedRefresh:vc atIndex:index];
                                              }
                                          }
                                            cancellation:^{
                                                [vc cancelRefresh];
                                            }];
        return;
    }

    NSDictionary *snapshot = [[_subscriptions objectAtIndex:index] copy];
    NSString *expectedURL = [[snapshot objectForKey:@"url"] copy];
    SubscriptionInfoVC *infoVC = [vc retain];
    _launchAutoUpdateInProgress = YES;
    [self setUpdatingSubscriptionIndex:index];
    [self showStatus:@"Updating subscription..." ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = nil;
        NSDictionary *updated = [[self updatedSubscriptionDictionaryFromSource:snapshot errorText:&errorText] retain];
        NSString *copiedError = [errorText copy];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setUpdatingSubscriptionIndex:-1];
            _launchAutoUpdateInProgress = NO;

            BOOL stillExists = (index >= 0 && index < (NSInteger)[_subscriptions count]);
            NSString *currentURL = stillExists ? [[_subscriptions objectAtIndex:index] objectForKey:@"url"] : nil;
            BOOL unchanged = stillExists && [expectedURL isKindOfClass:[NSString class]] &&
                             [currentURL isKindOfClass:[NSString class]] && [currentURL isEqualToString:expectedURL];

            if (updated && unchanged) {
                [_subscriptions replaceObjectAtIndex:index withObject:updated];
                [self normalizeSelection];
                [self saveData];
                [self reloadMainTableDataAfterExternalChange];
                NSArray *items = [updated objectForKey:@"items"];
                [self showStatus:[NSString stringWithFormat:@"Subscription updated (%lu configs)",
                                  (unsigned long)([items isKindOfClass:[NSArray class]] ? [items count] : 0)]
                              ok:YES];
                [infoVC finishRefreshWithSubscription:updated errorText:nil];
            } else {
                NSString *message = copiedError;
                if (!unchanged) message = @"Subscription changed while it was updating";
                if (![message isKindOfClass:[NSString class]] || [message length] == 0) {
                    message = @"Subscription update failed";
                }
                [self showStatus:message ok:NO];
                [infoVC finishRefreshWithSubscription:nil errorText:message];
            }

            [updated release];
            [copiedError release];
            [expectedURL release];
            [snapshot release];
            [infoVC release];
        });
        [pool drain];
    });
}

- (void)subscriptionInfoVC:(SubscriptionInfoVC *)vc requestedRenameTo:(NSString *)name atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;

    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) return;

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:[_subscriptions objectAtIndex:index]];
    [updated setObject:trimmed forKey:@"name"];
    [updated setObject:trimmed forKey:kSubscriptionCustomNameKey];
    [_subscriptions replaceObjectAtIndex:index withObject:updated];
    VCRecordAppEvent(@"subscription", @"Subscription renamed", nil);

    [self saveData];
    [self reloadMainTableDataAfterExternalChange];
    [vc reloadWithSubscription:updated];
    [self showStatus:@"Subscription renamed" ok:YES];
}

- (BOOL)deleteSubscriptionAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return NO;
    [_subscriptions removeObjectAtIndex:subIdx];
    VCRecordAppEvent(@"subscription", @"Subscription deleted",
                     [NSString stringWithFormat:@"remaining=%lu", (unsigned long)[_subscriptions count]]);

    if (_expandedSubscription == subIdx) {
        _expandedSubscription = -1;
    } else if (_expandedSubscription > subIdx) {
        _expandedSubscription--;
    }
    if (_selectedSubIndex == subIdx) {
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
    } else if (_selectedSubIndex > subIdx) {
        _selectedSubIndex--;
    }
    [self normalizeSelection];
    [self saveData];
    return YES;
}

- (void)subscriptionInfoVCRequestedDelete:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index {
    if (![self deleteSubscriptionAtIndex:index]) return;
    [self reloadMainTableDataAfterExternalChange];
    [self showStatus:@"Subscription deleted" ok:YES];
    [vc dismissViewControllerAnimated:YES completion:nil];
}

- (void)terminalPressed {
    VCRecordAppEvent(@"ui", _showingTerminal ? @"Log viewer closed" : @"Log viewer opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    if (_connectedWithProtectedLogs || [self selectedSubscriptionIsHappEncrypted]) {
        [self showStatus:@"Logs are unavailable for encrypted HAPP subscriptions" ok:NO];
        return;
    }
    _showingTerminal = !_showingTerminal;

    _tableView.hidden = _showingTerminal;
    _logSelector.hidden = !_showingTerminal;
    _logView.hidden = !_showingTerminal;
    [self updateStickyMainSectionHeader];
    [UIView animateWithDuration:0.18
                     animations:^{
                         [self updatePhoneConnectionLayout];
                     }];

    if (_showingTerminal) {
        [self refreshLogs];
        if (!_logTimer) {
            _logTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(refreshLogsTick:)
                                                        userInfo:nil
                                                         repeats:YES] retain];
        }
    } else {
        [self rememberActiveLogPosition];
        [_logTimer invalidate];
        [_logTimer release];
        _logTimer = nil;
    }

    [self updateTopButtonsIcons];
}

- (CGFloat)maximumLogOffsetY {
    CGFloat maxOffsetY = _logView.contentSize.height - _logView.bounds.size.height;
    return (maxOffsetY > 0.0f) ? maxOffsetY : 0.0f;
}

- (void)rememberActiveLogPosition {
    if (_activeLogIndex < 0 || _activeLogIndex > 1 || !_logView) return;

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    _logContentOffsets[_activeLogIndex] = _logView.contentOffset;
    _logContentOffsetsValid[_activeLogIndex] = YES;
    _logFollowsTail[_activeLogIndex] = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
}

- (void)displayLogText:(NSString *)text
               atIndex:(NSInteger)index
                offset:(CGPoint)savedOffset
            followTail:(BOOL)followTail {
    if (index < 0 || index > 1) return;

    NSString *copiedText = [(text ? text : @"") copy];
    [_logTexts[index] release];
    _logTexts[index] = copiedText;
    _logView.text = _logTexts[index];
    [_logView setNeedsLayout];
    [_logView layoutIfNeeded];

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    CGPoint targetOffset = savedOffset;
    targetOffset.x = 0.0f;
    if (followTail) {
        targetOffset.y = maxOffsetY;
    } else {
        if (targetOffset.y < 0.0f) targetOffset.y = 0.0f;
        if (targetOffset.y > maxOffsetY) targetOffset.y = maxOffsetY;
    }
    [_logView setContentOffset:targetOffset animated:NO];

    _logContentOffsets[index] = _logView.contentOffset;
    _logContentOffsetsValid[index] = YES;
    _logFollowsTail[index] = followTail || maxOffsetY <= 0.0f;
}

- (void)updateLogSelectorAnimated:(BOOL)animated {
    if (!_logSelector || !_logSelectionIndicator) return;

    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = _logSelectorButtons[i];
        [button setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
        [button setTitleColor:VCAccentColor() forState:UIControlStateSelected];
        [button setTitleColor:VCPrimaryTextColor() forState:UIControlStateHighlighted];
        button.selected = (i == _activeLogIndex);
    }

    _logSelectionIndicator.backgroundColor = VCAccentColor();
    CGFloat segmentWidth = _logSelector.bounds.size.width * 0.5f;
    CGRect indicatorFrame = _logSelectionIndicator.frame;
    indicatorFrame.origin.x = segmentWidth * _activeLogIndex + (segmentWidth - indicatorFrame.size.width) * 0.5f;
    void (^updates)(void) = ^{
        _logSelectionIndicator.frame = indicatorFrame;
    };
    if (animated) {
        [UIView animateWithDuration:0.16 animations:updates];
    } else {
        updates();
    }
}

- (void)logSourceChanged:(UIButton *)sender {
    NSInteger newIndex = sender.tag;
    if (newIndex < 0 || newIndex > 1 || newIndex == _activeLogIndex) return;

    [self rememberActiveLogPosition];
    _activeLogIndex = newIndex;
    [self updateLogSelectorAnimated:YES];

    CGPoint savedOffset = _logContentOffsetsValid[newIndex]
        ? _logContentOffsets[newIndex]
        : CGPointZero;
    BOOL followTail = _logContentOffsetsValid[newIndex]
        ? _logFollowsTail[newIndex]
        : YES;
    [self displayLogText:ReadLogAtIndex(newIndex)
                 atIndex:newIndex
                  offset:savedOffset
              followTail:followTail];
}

- (void)refreshLogs {
    if (!_showingTerminal || _activeLogIndex < 0 || _activeLogIndex > 1) {
        return;
    }
    if (_logView.tracking || _logView.dragging || _logView.decelerating ||
        _logView.selectedRange.length > 0) {
        return;
    }

    NSString *newText = ReadLogAtIndex(_activeLogIndex);
    NSString *oldText = _logTexts[_activeLogIndex] ? _logTexts[_activeLogIndex] : @"";
    if ([newText isEqualToString:oldText]) {
        return;
    }

    CGPoint savedOffset = _logView.contentOffset;
    CGFloat maxOffsetY = [self maximumLogOffsetY];
    BOOL wasNearBottom = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
    [self displayLogText:newText
                 atIndex:_activeLogIndex
                  offset:savedOffset
              followTail:wasNearBottom];
}

- (void)forceRefreshLogs {
    for (NSInteger i = 0; i < 2; i++) {
        [_logTexts[i] release];
        _logTexts[i] = nil;
        _logContentOffsets[i] = CGPointZero;
        _logContentOffsetsValid[i] = NO;
        _logFollowsTail[i] = YES;
    }
    [self displayLogText:ReadLogAtIndex(_activeLogIndex)
                 atIndex:_activeLogIndex
                  offset:CGPointZero
              followTail:NO];
}

- (void)clearLogsPressed {
    VCRecordAppEvent(@"ui", @"Clear logs button pressed", nil);
    NSString *resp = [self sanitizeDaemonText:ClearLogsViaDaemon()];
    [self forceRefreshLogs];

    if ([resp hasPrefix:@"OK"]) {
        [self showStatus:@"Logs cleared" ok:YES];
    } else {
        NSString *msg = ([resp length] > 0) ? resp : @"Failed to clear logs";
        [self showStatus:msg ok:NO];
    }
}

- (void)refreshLogsTick:(NSTimer *)timer {
    (void)timer;
    [self refreshLogs];
}

- (void)queryInitialStatus {
    [self showStatus:@"Checking daemon..." ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *resp = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
        BOOL connectedNow = [resp hasPrefix:@"OK connected"];
        BOOL protectedLogsNow = connectedNow &&
            [resp rangeOfString:@"protected=1"].location != NSNotFound;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (connectedNow) {
                VCRecordAppEvent(@"connection", @"Existing VPN session detected", protectedLogsNow ? @"protected_logs=1" : @"protected_logs=0");
                _connected = YES;
                _connectedWithProtectedLogs = protectedLogsNow;
                [self startUptimeTimer];
                [self showStatus:@"Connected" ok:YES];
            } else {
                VCRecordAppEvent(@"connection", @"No existing VPN session", nil);
                _connected = NO;
                _connectedWithProtectedLogs = NO;
                [self stopUptimeTimer];
                [self showStatus:@"Ready" ok:YES];
            }
            [self updateConnectButton];
        });
        [pool drain];
    });
}

- (void)updatePhoneConnectionScrollInsets {
    if (IsPadDevice() || !_tableView || _mainSectionTransitionInProgress) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat requiredBottomInset = _tableView.bounds.size.height - _tableView.contentSize.height;
    if (requiredBottomInset < 0.0f) requiredBottomInset = 0.0f;

    UIEdgeInsets insets = _tableView.contentInset;
    if (fabs(insets.top - collapseDistance) <= 0.5f &&
        fabs(insets.bottom - requiredBottomInset) <= 0.5f) {
        return;
    }
    insets.top = collapseDistance;
    insets.bottom = requiredBottomInset;
    _tableView.contentInset = insets;
}

- (void)updatePhoneConnectionLayout {
    if (IsPadDevice() || !_tableView || !_connectBtn || !_uptimeLabel || !_statusLabel) return;
    if (_mainSectionTransitionInProgress) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat progress = 0.0f;
    if (collapseDistance > 0.0f) {
        progress = _showingTerminal
            ? (_phoneConnectionCompact ? 1.0f : 0.0f)
            : VCClampUnit((_tableView.contentOffset.y + collapseDistance) / collapseDistance);
    }

    CGFloat width = self.view.bounds.size.width;
    CGFloat topInset = VCMainStatusBarInset();
    CGRect expandedButtonFrame = CGRectMake((width - 122.0f) * 0.5f, topInset + 60.0f, 122.0f, 122.0f);
    CGRect compactButtonFrame = CGRectMake(12.0f, topInset + 52.0f, 104.0f, 48.0f);
    CGRect expandedUptimeFrame = CGRectMake(16.0f, topInset + 190.0f, width - 32.0f, 20.0f);
    CGRect compactUptimeFrame = CGRectMake(128.0f, topInset + 50.0f, width - 140.0f, 18.0f);
    CGRect expandedStatusFrame = CGRectMake(16.0f, topInset + 216.0f, width - 32.0f, 30.0f);
    CGRect compactStatusFrame = CGRectMake(128.0f, topInset + 71.0f, width - 140.0f, 37.0f);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _connectBtn.frame = VCInterpolateRect(expandedButtonFrame, compactButtonFrame, progress);
    _connectBtn.layer.cornerRadius = _connectBtn.bounds.size.height * 0.5f;
    CGFloat buttonFontSize = 20.0f - 5.0f * progress;
    if (fabs([_connectBtn.titleLabel.font pointSize] - buttonFontSize) > 0.35f) {
        _connectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:buttonFontSize];
    }

    _uptimeLabel.frame = VCInterpolateRect(expandedUptimeFrame, compactUptimeFrame, progress);
    CGFloat uptimeFontSize = 13.0f - progress;
    if (fabs([_uptimeLabel.font pointSize] - uptimeFontSize) > 0.35f) {
        _uptimeLabel.font = [UIFont boldSystemFontOfSize:uptimeFontSize];
    }
    _uptimeLabel.textAlignment = (progress < 0.5f) ? NSTextAlignmentCenter : NSTextAlignmentLeft;

    _statusLabel.frame = VCInterpolateRect(expandedStatusFrame, compactStatusFrame, progress);
    CGFloat statusFontSize = 12.5f - progress;
    if (fabs([_statusLabel.font pointSize] - statusFontSize) > 0.35f) {
        _statusLabel.font = [UIFont systemFontOfSize:statusFontSize];
    }

    if (_showingTerminal && _logSelector && _logView) {
        CGFloat logY = topInset + kVCMainContentStartY - collapseDistance * progress;
        CGRect selectorFrame = _logSelector.frame;
        selectorFrame.origin.y = logY + 2.0f;
        _logSelector.frame = selectorFrame;

        CGRect logFrame = _logView.frame;
        logFrame.origin.y = logY + 32.0f;
        logFrame.size.height = self.view.bounds.size.height - logFrame.origin.y;
        if (logFrame.size.height < 120.0f) logFrame.size.height = 120.0f;
        _logView.frame = logFrame;
    }

    CGFloat labelAlpha = fabs(progress * 2.0f - 1.0f);
    _uptimeLabel.alpha = labelAlpha;
    _statusLabel.alpha = labelAlpha;

    UIEdgeInsets indicators = _tableView.scrollIndicatorInsets;
    indicators.top = collapseDistance * (1.0f - progress);
    _tableView.scrollIndicatorInsets = indicators;
    [CATransaction commit];

    if (progress <= 0.001f) {
        _phoneConnectionCompact = NO;
    } else if (progress >= 0.999f) {
        _phoneConnectionCompact = YES;
    }
}

- (CGFloat)maximumMainTableContentOffsetY {
    if (!_tableView) return 0.0f;

    CGFloat minimumOffset = -_tableView.contentInset.top;
    CGFloat maximumOffset = _tableView.contentSize.height - _tableView.bounds.size.height +
                            _tableView.contentInset.bottom;
    return (maximumOffset > minimumOffset) ? maximumOffset : minimumOffset;
}

- (CGFloat)phoneConnectionSnapOffsetForProposedOffset:(CGFloat)proposedOffset
                                         currentOffset:(CGFloat)currentOffset
                                              velocity:(CGFloat)velocity {
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    if (collapseDistance <= 0.0f) return proposedOffset;
    if ([self maximumMainTableContentOffsetY] < -0.5f) return expandedOffset;
    if (proposedOffset <= expandedOffset) return expandedOffset;
    if (proposedOffset >= 0.0f) return proposedOffset;

    if (velocity > 0.05f) return 0.0f;
    if (velocity < -0.05f) return expandedOffset;

    CGFloat movement = proposedOffset - currentOffset;
    if (movement > 3.0f) return 0.0f;
    if (movement < -3.0f) return expandedOffset;

    CGFloat compactTrigger = expandedOffset + collapseDistance * 0.28f;
    return (proposedOffset >= compactTrigger) ? 0.0f : expandedOffset;
}

- (void)animatePhoneConnectionToOffset:(CGFloat)targetOffset {
    if (!_tableView) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    CGFloat maximumOffset = [self maximumMainTableContentOffsetY];
    if (targetOffset < expandedOffset) targetOffset = expandedOffset;
    if (targetOffset > maximumOffset) targetOffset = maximumOffset;

    CGFloat distance = fabs(targetOffset - _tableView.contentOffset.y);
    _phoneConnectionCompact = targetOffset >= -0.5f;
    if (distance <= 0.5f || collapseDistance <= 0.0f) {
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                            animated:NO];
        [self updatePhoneConnectionLayout];
        return;
    }

    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:YES];
}

- (void)snapPhoneConnectionLayoutIfNeededAnimated:(BOOL)animated {
    if (IsPadDevice() || _showingTerminal || !_tableView) return;

    [_tableView layoutIfNeeded];
    [self updatePhoneConnectionScrollInsets];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    CGFloat currentOffset = _tableView.contentOffset.y;
    if ([self maximumMainTableContentOffsetY] < -0.5f) {
        if (fabs(currentOffset - expandedOffset) > 0.5f) {
            if (animated) {
                [self animatePhoneConnectionToOffset:expandedOffset];
            } else {
                [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, expandedOffset)
                                    animated:NO];
            }
        }
        return;
    }
    if (currentOffset <= expandedOffset + 0.5f) {
        _phoneConnectionCompact = NO;
        return;
    }
    if (currentOffset >= -0.5f) {
        _phoneConnectionCompact = YES;
        return;
    }

    if (_tableView.tracking || _tableView.dragging || _tableView.decelerating) return;

    CGFloat targetOffset = _phoneConnectionCompact ? 0.0f : expandedOffset;
    if (animated) {
        [self animatePhoneConnectionToOffset:targetOffset];
    } else {
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                            animated:NO];
        [self updatePhoneConnectionLayout];
    }
}

- (void)prepareMainTableStructuralTransition {
    if (!_mainSectionTransitionInProgress && !IsPadDevice() && _tableView) {
        _mainTableOffsetBeforeTransition = _tableView.contentOffset.y;
        _phoneConnectionCompactBeforeTransition = (_tableView.contentOffset.y >= -0.5f)
            ? YES
            : _phoneConnectionCompact;
        _mainTableTransitionSnapshotValid = YES;
    }
    _mainSectionTransitionInProgress = YES;
    if (IsPadDevice() || !_tableView) return;

    UIEdgeInsets insets = _tableView.contentInset;
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat positiveOffset = _tableView.contentOffset.y;
    if (positiveOffset < 0.0f) positiveOffset = 0.0f;
    CGFloat safeBottomInset = _tableView.bounds.size.height + positiveOffset + collapseDistance;
    if (insets.bottom < safeBottomInset) {
        insets.bottom = safeBottomInset;
        _tableView.contentInset = insets;
    }
}

- (void)stabilizeMainTableOffsetDuringStructuralTransition {
    if (IsPadDevice() || !_tableView || !_mainSectionTransitionInProgress ||
        !_mainTableTransitionSnapshotValid || !_phoneConnectionCompactBeforeTransition) {
        return;
    }

    CGFloat targetOffset = _mainTableOffsetBeforeTransition;
    if (targetOffset < 0.0f) targetOffset = 0.0f;
    if (fabs(_tableView.contentOffset.y - targetOffset) <= 0.5f) return;

    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:NO];
}

- (void)restoreMainTableAfterStructuralTransitionCompact:(BOOL)compact
                                          preservedOffset:(CGFloat)preservedOffset {
    if (IsPadDevice() || !_tableView) return;

    [self updatePhoneConnectionScrollInsets];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat targetOffset = -collapseDistance;
    if (compact) {
        targetOffset = preservedOffset;
        if (targetOffset < 0.0f) targetOffset = 0.0f;
        CGFloat maximumOffset = [self maximumMainTableContentOffsetY];
        if (maximumOffset < 0.0f) maximumOffset = 0.0f;
        if (targetOffset > maximumOffset) targetOffset = maximumOffset;
    }

    _phoneConnectionCompact = compact;
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:NO];
    [self updatePhoneConnectionLayout];
}

- (void)completeMainTableStructuralTransition {
    if (!_tableView) {
        _mainSectionTransitionInProgress = NO;
        _mainTableTransitionSnapshotValid = NO;
        return;
    }

    [_tableView layoutIfNeeded];
    BOOL restoreSnapshot = _mainTableTransitionSnapshotValid && !IsPadDevice();
    BOOL restoreCompact = _phoneConnectionCompactBeforeTransition;
    CGFloat restoreOffset = _mainTableOffsetBeforeTransition;

    _mainSectionTransitionInProgress = NO;
    [self updatePhoneConnectionScrollInsets];

    if (restoreSnapshot) {
        [self restoreMainTableAfterStructuralTransitionCompact:restoreCompact
                                                preservedOffset:restoreOffset];

        NSUInteger transitionToken = _mainSectionTransitionToken;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (transitionToken != _mainSectionTransitionToken ||
                _mainSectionTransitionInProgress ||
                _tableView.tracking || _tableView.dragging || _tableView.decelerating) {
                return;
            }
            [_tableView layoutIfNeeded];
            [self restoreMainTableAfterStructuralTransitionCompact:restoreCompact
                                                    preservedOffset:restoreOffset];
            [self updateStickyMainSectionHeader];
        });
    } else {
        [self snapPhoneConnectionLayoutIfNeededAnimated:NO];
    }

    _mainTableTransitionSnapshotValid = NO;
}

- (void)refreshUpdateIndicatorFromCache {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *latestVersion = [defaults objectForKey:kDefaultsLatestVersionKey];
    NSString *releaseURL = [defaults objectForKey:kDefaultsLatestReleaseURLKey];
    BOOL available = [latestVersion isKindOfClass:[NSString class]] &&
                     VCCompareVersions(AppShortVersion(), latestVersion) == NSOrderedAscending;

    [_availableUpdateVersion release];
    _availableUpdateVersion = available ? [latestVersion copy] : nil;
    [_availableReleaseURL release];
    _availableReleaseURL = available && [releaseURL isKindOfClass:[NSString class]]
        ? [releaseURL copy]
        : nil;
    [self updateTopButtonsIcons];
    [self refreshStatusText];
}

- (void)updateIndicatorPressed {
    if ([_availableUpdateVersion length] == 0) return;

    NSString *releaseURL = [_availableReleaseURL length] > 0
        ? _availableReleaseURL
        : kUpdateReleasesURL;
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"update", @"status",
                            AppShortVersion(), @"current_version",
                            _availableUpdateVersion, @"latest_version",
                            releaseURL, @"release_url",
                            nil];
    VCShowUpdateAvailableAlert(result, self, VCAlertTagUpdateAvailable);
}

- (void)startAutomaticUpdateCheckIfNeeded {
    if (!_automaticUpdateChecksEnabled || _updateChecker || VCAutomaticUpdateCheckIsFresh()) return;

    if (_launchAutoUpdateInProgress || self.presentedViewController || !self.view.window) {
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:1.0];
        return;
    }

    _updateChecker = [[VCUpdateChecker alloc] initWithDelegate:self];
    [_updateChecker start];
}

- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result {
    if (checker != _updateChecker) return;

    checker.delegate = nil;
    [_updateChecker release];
    _updateChecker = nil;

    if (!VCUpdateResultIsSuccessful(result)) return;
    VCCacheSuccessfulUpdateResult(result);
    [self refreshUpdateIndicatorFromCache];
}

- (void)updateMainEmptyState {
    if (!_tableView) return;

    if ([_configs count] > 0 || [_subscriptions count] > 0) {
        _tableView.scrollEnabled = YES;
        _tableView.backgroundView = nil;
        return;
    }

    if (!IsPadDevice()) {
        CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
        _phoneConnectionCompact = NO;
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, -collapseDistance)
                            animated:NO];
        [self updatePhoneConnectionLayout];
    }
    _tableView.scrollEnabled = NO;

    CGRect bounds = _tableView.bounds;
    UIView *background = [[[UIView alloc] initWithFrame:CGRectMake(0.0f,
                                                                   0.0f,
                                                                   bounds.size.width,
                                                                   bounds.size.height)] autorelease];
    background.backgroundColor = VCBackgroundColor();
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGFloat containerWidth = bounds.size.width - 32.0f;
    if (containerWidth > 300.0f) containerWidth = 300.0f;
    if (containerWidth < 220.0f) containerWidth = 220.0f;
    CGFloat containerHeight = 200.0f;
    CGFloat reservedTop = IsPadDevice() ? 0.0f : (kVCMainContentStartY - kVCMainCompactContentStartY);
    CGFloat availableHeight = bounds.size.height - reservedTop;
    if (availableHeight < containerHeight) availableHeight = containerHeight;
    CGFloat containerY = reservedTop + floorf((availableHeight - containerHeight) * 0.5f);
    if (containerY < 12.0f) containerY = 12.0f;

    UIView *container = [[[UIView alloc] initWithFrame:CGRectMake(floorf((bounds.size.width - containerWidth) * 0.5f),
                                                                         containerY,
                                                                         containerWidth,
                                                                         containerHeight)] autorelease];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                 UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin |
                                 UIViewAutoresizingFlexibleBottomMargin;

    UIView *iconCircle = [[[UIView alloc] initWithFrame:CGRectMake(floorf((containerWidth - 58.0f) * 0.5f),
                                                                          0.0f,
                                                                          58.0f,
                                                                          58.0f)] autorelease];
    iconCircle.backgroundColor = VCCellBackgroundColor();
    iconCircle.layer.cornerRadius = 29.0f;
    iconCircle.layer.borderWidth = 1.5f;
    iconCircle.layer.borderColor = VCAccentColor().CGColor;

    UIImageView *icon = [[[UIImageView alloc] initWithFrame:CGRectMake(16.0f, 16.0f, 26.0f, 26.0f)] autorelease];
    icon.image = TintImageWithColor(MakeIconImage(VCIconTypeAdd, 26.0f, YES), VCAccentColor());
    icon.contentMode = UIViewContentModeCenter;
    [iconCircle addSubview:icon];
    [container addSubview:iconCircle];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(0.0f, 72.0f, containerWidth, 24.0f)] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.textColor = VCPrimaryTextColor();
    title.font = [UIFont boldSystemFontOfSize:17.0f];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"Add your first connection";
    [container addSubview:title];

    UILabel *detail = [[[UILabel alloc] initWithFrame:CGRectMake(8.0f, 101.0f, containerWidth - 16.0f, 42.0f)] autorelease];
    detail.backgroundColor = [UIColor clearColor];
    detail.textColor = VCSecondaryTextColor();
    detail.font = [UIFont systemFontOfSize:13.0f];
    detail.textAlignment = NSTextAlignmentCenter;
    detail.numberOfLines = 2;
    detail.text = @"Import a configuration or subscription\nto start using vless-core.";
    [container addSubview:detail];

    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeCustom];
    addButton.frame = CGRectMake(floorf((containerWidth - 164.0f) * 0.5f), 156.0f, 164.0f, 40.0f);
    addButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    [addButton setTitle:@"Add connection" forState:UIControlStateNormal];
    [addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [addButton setBackgroundImage:SolidImageWithColor(VCAccentColor()) forState:UIControlStateNormal];
    [addButton setBackgroundImage:SolidImageWithColor([VCAccentColor() colorWithAlphaComponent:0.72f])
                          forState:UIControlStateHighlighted];
    addButton.layer.cornerRadius = 8.0f;
    addButton.layer.masksToBounds = YES;
    addButton.accessibilityHint = @"Opens configuration and subscription import options";
    [addButton addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:addButton];

    [background addSubview:container];
    _tableView.backgroundView = background;
}

- (void)applyTheme {
    _darkThemeEnabled = VCAppearanceIsDark();
    UIColor *background = VCBackgroundColor();
    self.view.backgroundColor = background;
    _titleLabel.textColor = VCPrimaryTextColor();
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _statusLabel.textColor = _statusOK ? VCSuccessColor() : VCErrorColor();
    [self updateLogSelectorAnimated:NO];
    _logView.backgroundColor = background;
    _logView.textColor = VCPrimaryTextColor();
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    VCAppearanceApplyTable(_tableView);
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.separatorColor = [UIColor clearColor];
    VCAppearanceApplyStatusBar();

    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self applyTopButtonFeedbackToButton:_updateBtn];
    [self updateTopButtonsIcons];
    [_tableView reloadData];
    [self updateMainEmptyState];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActiveNotification:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [self loadData];
    _pingDisplayByURI = [[NSMutableDictionary alloc] init];
    _standalonePingURIs = [[NSMutableSet alloc] init];
    _subscriptionPingPendingByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingOperationsByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingPreviousDisplayByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingTokenByIdentifier = [[NSMutableDictionary alloc] init];
    _pingQueue = [[NSOperationQueue alloc] init];
    _pingQueue.maxConcurrentOperationCount = 4;

    CGRect b = self.view.bounds;
    BOOL collapsiblePhoneLayout = !IsPadDevice();
    CGFloat topInset = VCMainStatusBarInset();
    CGFloat listY = topInset + (collapsiblePhoneLayout ? kVCMainCompactContentStartY : kVCMainContentStartY);
    UIColor *bg = VCBackgroundColor();
    self.view.backgroundColor = bg;

    CGFloat topButtonY = topInset + 4.0f;
    CGFloat topButtonWidth = 34.0f;
    CGFloat topButtonHeight = 40.0f;
    CGFloat right = b.size.width - 9.0f;

    CGFloat settingsX = right - topButtonWidth;
    CGFloat refreshX = settingsX - topButtonWidth;
    CGFloat terminalX = refreshX - topButtonWidth;
    CGFloat plusX = terminalX - topButtonWidth;
    CGFloat clearLogsY = topInset + 44.0f;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, topInset + 6.0f, plusX - 20, 28)];
    _titleLabel.text = @"vless-core";
    _titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    _titleLabel.textColor = VCPrimaryTextColor();
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_titleLabel];

    CGFloat updateX = CGRectGetMinX(_titleLabel.frame) +
                      ceilf([_titleLabel.text sizeWithFont:_titleLabel.font].width) + 4.0f;
    _updateBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _updateBtn.frame = CGRectMake(updateX, topInset + 6.0f, 28.0f, 28.0f);
    _updateBtn.hidden = YES;
    [_updateBtn addTarget:self action:@selector(updateIndicatorPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_updateBtn];
    [self.view addSubview:_updateBtn];

    _plusBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plusBtn.frame = CGRectMake(plusX, topButtonY, topButtonWidth, topButtonHeight);
    _plusBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_plusBtn addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self.view addSubview:_plusBtn];

    _terminalBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _terminalBtn.frame = CGRectMake(terminalX, topButtonY, topButtonWidth, topButtonHeight);
    _terminalBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_terminalBtn addTarget:self action:@selector(terminalPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self.view addSubview:_terminalBtn];

    _clearLogsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _clearLogsBtn.frame = CGRectMake(settingsX + 3.0f, clearLogsY, 28.0f, 28.0f);
    _clearLogsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _clearLogsBtn.hidden = YES;
    [_clearLogsBtn addTarget:self action:@selector(clearLogsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self.view addSubview:_clearLogsBtn];

    _refreshBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _refreshBtn.frame = CGRectMake(refreshX, topButtonY, topButtonWidth, topButtonHeight);
    _refreshBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_refreshBtn addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self.view addSubview:_refreshBtn];

    _settingsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _settingsBtn.frame = CGRectMake(settingsX, topButtonY, topButtonWidth, topButtonHeight);
    _settingsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_settingsBtn addTarget:self action:@selector(settingsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self.view addSubview:_settingsBtn];

    CGFloat btnSize = 122.0f;
    _connectBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _connectBtn.frame = CGRectMake((b.size.width - btnSize) * 0.5f, topInset + 60.0f, btnSize, btnSize);
    _connectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20.0f];
    _connectBtn.layer.cornerRadius = btnSize * 0.5f;
    _connectBtn.layer.borderWidth = 2.0f;
    _connectBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.95f].CGColor;
    _connectBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_connectBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_connectBtn addTarget:self action:@selector(togglePressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:_connectBtn];
    [self.view addSubview:_connectBtn];

    _uptimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, topInset + 190.0f,
                                                            b.size.width - 32.0f, 20.0f)];
    _uptimeLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    _uptimeLabel.text = @"00:00:00";
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _uptimeLabel.textAlignment = NSTextAlignmentCenter;
    _uptimeLabel.backgroundColor = [UIColor clearColor];
    _uptimeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_uptimeLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, topInset + 216.0f,
                                                            b.size.width - 32.0f, 30.0f)];
    _statusLabel.font = [UIFont systemFontOfSize:12.5f];
    _statusLabel.numberOfLines = 2;
    _statusLabel.text = @"Ready";
    _statusOK = YES;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_statusLabel];

    CGFloat listH = b.size.height - listY;
    if (listH < 120.0f) listH = 120.0f;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, listY, b.size.width, listH) style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.opaque = YES;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.separatorColor = [UIColor clearColor];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    _tableView.tableFooterView = footer;
    if (collapsiblePhoneLayout) {
        CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
        _tableView.contentInset = UIEdgeInsetsMake(collapseDistance, 0.0f, 0.0f, 0.0f);
        _tableView.scrollIndicatorInsets = _tableView.contentInset;
        _tableView.contentOffset = CGPointMake(0.0f, -collapseDistance);
    }
    [self.view addSubview:_tableView];

    CGFloat logY = topInset + kVCMainContentStartY;
    CGFloat logH = b.size.height - logY;
    if (logH < 120.0f) logH = 120.0f;
    CGFloat logSelectorWidth = 188.0f;
    if (logSelectorWidth > b.size.width - 24.0f) logSelectorWidth = b.size.width - 24.0f;
    _logSelector = [[UIView alloc] initWithFrame:CGRectZero];
    _logSelector.frame = CGRectMake((b.size.width - logSelectorWidth) * 0.5f,
                                    logY + 2.0f,
                                    logSelectorWidth,
                                    28.0f);
    _logSelector.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                    UIViewAutoresizingFlexibleRightMargin;
    _logSelector.backgroundColor = [UIColor clearColor];
    _logSelector.hidden = YES;

    NSArray *logTitles = [NSArray arrayWithObjects:@"vpnctld", @"vless-core", nil];
    CGFloat logButtonWidth = logSelectorWidth * 0.5f;
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(logButtonWidth * i, 0.0f, logButtonWidth, 26.0f);
        button.tag = i;
        button.titleLabel.font = [UIFont systemFontOfSize:12.0f];
        [button setTitle:[logTitles objectAtIndex:i] forState:UIControlStateNormal];
        [button addTarget:self
                   action:@selector(logSourceChanged:)
         forControlEvents:UIControlEventTouchUpInside];
        _logSelectorButtons[i] = button;
        [_logSelector addSubview:button];
    }

    _logSelectionIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 26.0f, 32.0f, 2.0f)];
    _logSelectionIndicator.layer.cornerRadius = 1.0f;
    [_logSelector addSubview:_logSelectionIndicator];
    [self.view addSubview:_logSelector];

    _activeLogIndex = 0;
    _logFollowsTail[0] = YES;
    _logFollowsTail[1] = YES;
    [self updateLogSelectorAnimated:NO];
    CGRect logFrame = CGRectMake(0.0f, logY + 32.0f, b.size.width, logH - 32.0f);
    _logView = [[UITextView alloc] initWithFrame:logFrame];
    _logView.editable = NO;
    _logView.font = [UIFont systemFontOfSize:10.0f];
    _logView.backgroundColor = bg;
    _logView.textColor = VCPrimaryTextColor();
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    _logView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logView.hidden = YES;
    _logView.text = @"";
    _logView.delegate = self;
    [self.view addSubview:_logView];

    [self.view bringSubviewToFront:_connectBtn];
    [self.view bringSubviewToFront:_uptimeLabel];
    [self.view bringSubviewToFront:_statusLabel];
    [self updatePhoneConnectionLayout];

    [self updateConnectButton];
    [self applyTheme];
    [self refreshUpdateIndicatorFromCache];
    [self queryInitialStatus];
    VCRecordAppEvent(@"ui", @"Main screen initialized",
                     [NSString stringWithFormat:@"width=%.0f height=%.0f configs=%lu subscriptions=%lu ipad=%d",
                      b.size.width,
                      b.size.height,
                      (unsigned long)[_configs count],
                      (unsigned long)[_subscriptions count],
                      IsPadDevice() ? 1 : 0]);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshUpdateIndicatorFromCache];
    [self startLaunchAutoUpdateIfNeeded];
    if (!_didScheduleAutomaticUpdateCheck) {
        _didScheduleAutomaticUpdateCheck = YES;
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:1.5];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePhoneConnectionScrollInsets];
    [self updatePhoneConnectionLayout];
    [self updateStickyMainSectionHeader];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startAutomaticUpdateCheckIfNeeded)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(beginPendingReconnect)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushMainStateDefaults)
                                               object:nil];
    [self flushMainStateDefaults];
    _updateChecker.delegate = nil;
    [_updateChecker release];
    [_availableReleaseURL release];
    [_availableUpdateVersion release];
    [_pendingReconnectURI release];
    [_logTimer invalidate];
    [_logTimer release];
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    [_statusBaseText release];

    [_connectBtn release];
    [_plusBtn release];
    [_terminalBtn release];
    [_clearLogsBtn release];
    [_refreshBtn release];
    [_settingsBtn release];
    [_updateBtn release];
    [_statusLabel release];
    [_uptimeLabel release];
    [_titleLabel release];

    [_tableView release];
    [_logSelector release];
    [_logSelectionIndicator release];
    [_logView release];
    [_logTexts[0] release];
    [_logTexts[1] release];
    [_stickySectionHeaderView release];
    [_pendingImportDoneStatus release];
    [_pendingImportRefreshIndices release];
    [_pendingInsecureImportURLs release];
    if (_pendingPlainHTTPConfirmation) Block_release(_pendingPlainHTTPConfirmation);
    if (_pendingPlainHTTPCancellation) Block_release(_pendingPlainHTTPCancellation);
    [_subscriptionToReexpandAfterReorder release];

    [_configs release];
    [_subscriptions release];
    [_pingDisplayByURI release];
    [_standalonePingURIs release];
    [_subscriptionPingPendingByIdentifier release];
    [_subscriptionPingOperationsByIdentifier release];
    [_subscriptionPingPreviousDisplayByIdentifier release];
    [_subscriptionPingTokenByIdentifier release];
    [_pingQueue cancelAllOperations];
    [_pingQueue release];

    [super dealloc];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return _configurationsSectionExpanded ? [_configs count] : 0;
    }
    return _subscriptionsSectionExpanded ? [self subscriptionSectionRowCount] : 0;
}

- (BOOL)mainSectionHasItems:(NSInteger)section {
    if (section == 0) return [_configs count] > 0;
    if (section == 1) return [_subscriptions count] > 0;
    return NO;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (![self mainSectionHasItems:section]) return nil;
    return (section == 0) ? @"Configurations" : @"Subscriptions";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) {
        BOOL firstItem = (indexPath.row == 0);
        BOOL lastItem = (indexPath.row == (NSInteger)[_configs count] - 1);
        return 44.0f + (firstItem ? 4.0f : 0.0f) + (lastItem ? 8.0f : 0.0f);
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row
                       toSubIndex:&subIdx
                        itemIndex:&itemIdx
                         isHeader:&isHeader]) {
        return 44.0f;
    }
    if (isHeader) return 62.0f;

    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    BOOL firstItem = (itemIdx == 0);
    BOOL lastItem = (itemIdx == (NSInteger)[items count] - 1);
    return 44.0f + (firstItem ? 4.0f : 0.0f) + (lastItem ? 8.0f : 0.0f);
}

- (void)setMainReorderingSection:(NSInteger)section showStatus:(BOOL)showStatus {
    if (section < 0 || section > 1) section = -1;
    if (_reorderingSection == section) return;

    NSInteger previousSection = _reorderingSection;
    if (previousSection >= 0) {
        [_tableView setEditing:NO animated:NO];
    }

    if (previousSection == 1 && section != 1 && _subscriptionToReexpandAfterReorder) {
        NSUInteger index = [_subscriptions indexOfObjectIdenticalTo:_subscriptionToReexpandAfterReorder];
        _expandedSubscription = (index == NSNotFound) ? -1 : (NSInteger)index;
        [_subscriptionToReexpandAfterReorder release];
        _subscriptionToReexpandAfterReorder = nil;
    }

    _reorderingSection = section;
    if (section == 0) {
        _configurationsSectionExpanded = YES;
    } else if (section == 1) {
        _subscriptionsSectionExpanded = YES;
        [_subscriptionToReexpandAfterReorder release];
        _subscriptionToReexpandAfterReorder = nil;
        if (_expandedSubscription >= 0 && _expandedSubscription < (NSInteger)[_subscriptions count]) {
            _subscriptionToReexpandAfterReorder = [[_subscriptions objectAtIndex:_expandedSubscription] retain];
        }
        _expandedSubscription = -1;
    }

    [self saveMainState];
    [self reloadMainTableDataAfterExternalChange];
    if (_reorderingSection >= 0) {
        [_tableView setEditing:YES animated:YES];
        if (showStatus) {
            [self showStatus:(_reorderingSection == 0
                                  ? @"Drag configurations to change their order"
                                  : @"Drag subscriptions to change their order")
                         ok:YES];
        }
    } else if (showStatus && previousSection >= 0) {
        [self showStatus:(previousSection == 0
                              ? @"Configuration order saved"
                              : @"Subscription order saved")
                     ok:YES];
    }
}

- (void)mainSectionOrderPressed:(UIButton *)sender {
    NSInteger section = sender.tag - kVCMainSectionHeaderOrderButtonTagBase;
    if (section < 0 || section > 1) return;

    NSArray *items = (section == 0) ? (NSArray *)_configs : (NSArray *)_subscriptions;
    if ([items count] < 2) return;
    if (_reorderingSection == section) {
        VCRecordAppEvent(@"ui", @"List reordering finished", section == 0 ? @"section=configurations" : @"section=subscriptions");
        [self setMainReorderingSection:-1 showStatus:YES];
        return;
    }
    if (section == 1 && _launchAutoUpdateInProgress) {
        [self showStatus:@"Wait for the subscription update to finish" ok:YES];
        return;
    }

    [self setMainReorderingSection:section showStatus:YES];
    VCRecordAppEvent(@"ui", @"List reordering started", section == 0 ? @"section=configurations" : @"section=subscriptions");
}

- (void)mainSectionHeaderPressed:(UIButton *)sender {
    NSInteger section = sender.tag - kVCMainSectionHeaderButtonTagBase;
    if (section < 0 || section > 1) return;
    if (_mainSectionTransitionInProgress) {
        VCRecordAppEvent(@"layout", @"Section toggle ignored", @"reason=transition_in_progress");
        return;
    }
    if (_reorderingSection >= 0) {
        [self showStatus:@"Finish reordering first" ok:YES];
        return;
    }
    NSInteger oldRowCount = [_tableView numberOfRowsInSection:section];

    if (section == 0) {
        _configurationsSectionExpanded = !_configurationsSectionExpanded;
    } else {
        _subscriptionsSectionExpanded = !_subscriptionsSectionExpanded;
    }
    [self saveMainState];
    NSInteger newRowCount = [self tableView:_tableView numberOfRowsInSection:section];
    [self recordMainLayoutEvent:@"Section toggle started" section:section];

    NSUInteger transitionToken = ++_mainSectionTransitionToken;
    NSNumber *transitionNumber = [NSNumber numberWithUnsignedInteger:transitionToken];
    [self prepareMainTableStructuralTransition];
    [CATransaction begin];

    [self updateMainSectionHeaderButton:sender section:section animated:YES];

    UIButton *normalButton = (UIButton *)[_tableView viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
    if (normalButton != sender) {
        [self updateMainSectionHeaderButton:normalButton section:section animated:YES];
    }
    if (_stickySectionHeaderSection == section) {
        UIButton *stickyButton = (UIButton *)[_stickySectionHeaderView viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
        if (stickyButton != sender && stickyButton != normalButton) {
            [self updateMainSectionHeaderButton:stickyButton section:section animated:YES];
        }
    }

    [CATransaction setCompletionBlock:^{
        [self finishMainSectionTransition:transitionNumber];
        [self recordMainLayoutEvent:@"Section toggle finished" section:section];
    }];

    NSMutableArray *changedRows = [NSMutableArray array];
    NSInteger changedRowCount = (newRowCount > oldRowCount) ? newRowCount : oldRowCount;
    for (NSInteger row = 0; row < changedRowCount; row++) {
        [changedRows addObject:[NSIndexPath indexPathForRow:row inSection:section]];
    }

    @try {
        if (newRowCount > oldRowCount) {
            [_tableView insertRowsAtIndexPaths:changedRows withRowAnimation:UITableViewRowAnimationFade];
        } else if (oldRowCount > newRowCount) {
            [_tableView deleteRowsAtIndexPaths:changedRows withRowAnimation:UITableViewRowAnimationFade];
        }
    } @catch (NSException *exception) {
        (void)exception;
        VCRecordAppEvent(@"layout", @"Section animation recovered", @"reason=table_update_exception");
        [self reloadMainTableDataAfterExternalChange];
    }
    [CATransaction commit];
    [self performSelector:@selector(finishMainSectionTransition:)
               withObject:transitionNumber
               afterDelay:0.35];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self mainSectionHasItems:section] ? kVCMainSectionHeaderHeight : 0.01f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (![self mainSectionHasItems:section]) return 0.01f;
    return tableView.sectionFooterHeight;
}

- (UIView *)mainSectionHeaderViewForTable:(UITableView *)tableView section:(NSInteger)section {
    if (![self mainSectionHasItems:section]) return nil;

    CGFloat width = tableView.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0.0f,
                                                               0.0f,
                                                               width,
                                                               kVCMainSectionHeaderHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];

    BOOL expanded = (section == 0) ? _configurationsSectionExpanded : _subscriptionsSectionExpanded;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(10.0f, 5.0f, width - 20.0f, 36.0f);
    button.tag = kVCMainSectionHeaderButtonTagBase + section;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0f, 14.0f, 0.0f, 132.0f);
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
    [button setTitle:[self tableView:tableView titleForHeaderInSection:section] forState:UIControlStateNormal];
    [button setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
    [button setTitleColor:VCPrimaryTextColor() forState:UIControlStateHighlighted];
    [button setTitleShadowColor:(VCAppearanceIsDark() ? [UIColor clearColor]
                                                       : [UIColor colorWithWhite:1.0f alpha:0.85f])
                       forState:UIControlStateNormal];
    button.titleLabel.shadowOffset = VCAppearanceIsDark() ? CGSizeZero : CGSizeMake(0.0f, 1.0f);
    [button setBackgroundImage:SolidImageWithColor(VCCellBackgroundColor()) forState:UIControlStateNormal];
    [button setBackgroundImage:SolidImageWithColor(VCSelectedCellColor()) forState:UIControlStateHighlighted];
    button.layer.cornerRadius = 7.0f;
    button.layer.borderWidth = 1.0f;
    button.layer.borderColor = VCSeparatorColor().CGColor;
    button.layer.masksToBounds = YES;
    button.accessibilityLabel = (section == 0) ? @"Configurations" : @"Subscriptions";
    button.accessibilityValue = expanded ? @"Expanded" : @"Collapsed";
    button.accessibilityHint = expanded ? @"Double tap to collapse" : @"Double tap to expand";
    [button addTarget:self action:@selector(mainSectionHeaderPressed:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *countLabel = [[[UILabel alloc] initWithFrame:CGRectMake(button.bounds.size.width - 116.0f,
                                                                      7.0f,
                                                                      42.0f,
                                                                      22.0f)] autorelease];
    countLabel.tag = kVCMainSectionHeaderCountTagBase + section;
    countLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    countLabel.backgroundColor = VCAppearanceIsDark()
        ? [UIColor colorWithWhite:0.24f alpha:1.0f]
        : [UIColor colorWithWhite:0.90f alpha:1.0f];
    countLabel.textColor = VCSecondaryTextColor();
    countLabel.font = [UIFont boldSystemFontOfSize:12.0f];
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.adjustsFontSizeToFitWidth = YES;
    countLabel.minimumScaleFactor = 0.67f;
    countLabel.layer.cornerRadius = 11.0f;
    countLabel.layer.masksToBounds = YES;
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    [button addSubview:countLabel];

    UIImageView *chevron = [[[UIImageView alloc] initWithFrame:CGRectMake(button.bounds.size.width - 30.0f,
                                                                          10.0f,
                                                                          16.0f,
                                                                          16.0f)] autorelease];
    chevron.tag = kVCMainSectionHeaderChevronTagBase + section;
    chevron.image = TintImageWithColor(MakeIconImage(expanded ? VCIconTypeChevronDown
                                                              : VCIconTypeChevronRight,
                                                     16.0f,
                                                     NO),
                                        VCSecondaryTextColor());
    chevron.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                               UIViewAutoresizingFlexibleTopMargin |
                               UIViewAutoresizingFlexibleBottomMargin;
    [button addSubview:chevron];
    [header addSubview:button];

    UIButton *orderButton = [UIButton buttonWithType:UIButtonTypeCustom];
    orderButton.frame = CGRectMake(width - 74.0f, 11.0f, 24.0f, 24.0f);
    orderButton.tag = kVCMainSectionHeaderOrderButtonTagBase + section;
    orderButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    BOOL reordering = (_reorderingSection == section);
    VCIconType orderIconType = reordering ? VCIconTypeCheck : VCIconTypeReorder;
    [orderButton setImage:TintImageWithColor(MakeIconImage(orderIconType, 17.0f, reordering),
                                             reordering ? VCAccentColor() : VCSecondaryTextColor())
                  forState:UIControlStateNormal];
    [orderButton setImage:TintImageWithColor(MakeIconImage(orderIconType, 17.0f, reordering),
                                             VCPrimaryTextColor())
                  forState:UIControlStateHighlighted];
    orderButton.hidden = count < 2;
    if (reordering) {
        orderButton.accessibilityLabel = (section == 0) ? @"Finish reordering configurations" : @"Finish reordering subscriptions";
        orderButton.accessibilityHint = @"Saves the current order";
    } else {
        orderButton.accessibilityLabel = (section == 0) ? @"Reorder configurations" : @"Reorder subscriptions";
        orderButton.accessibilityHint = @"Shows drag handles in this list";
    }
    [orderButton addTarget:self action:@selector(mainSectionOrderPressed:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:orderButton];

    VCAppearanceApplyHeaderView(header);
    return header;
}

- (void)updateMainSectionHeaderButton:(UIButton *)button section:(NSInteger)section animated:(BOOL)animated {
    if (!button || section < 0 || section > 1) return;

    BOOL expanded = [self isMainSectionExpanded:section];
    button.accessibilityValue = expanded ? @"Expanded" : @"Collapsed";
    button.accessibilityHint = expanded ? @"Double tap to collapse" : @"Double tap to expand";

    UILabel *countLabel = (UILabel *)[button viewWithTag:(kVCMainSectionHeaderCountTagBase + section)];
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];

    UIImageView *chevron = (UIImageView *)[button viewWithTag:(kVCMainSectionHeaderChevronTagBase + section)];
    UIImage *image = TintImageWithColor(MakeIconImage(expanded ? VCIconTypeChevronDown
                                                               : VCIconTypeChevronRight,
                                                      16.0f,
                                                      NO),
                                         VCSecondaryTextColor());
    if (animated) {
        [UIView transitionWithView:chevron
                          duration:0.16
                           options:(UIViewAnimationOptionTransitionCrossDissolve |
                                    UIViewAnimationOptionBeginFromCurrentState)
                        animations:^{
                            chevron.image = image;
                        }
                        completion:nil];
    } else {
        chevron.image = image;
    }
}

- (void)updateMainSectionHeaderView:(UIView *)header section:(NSInteger)section animated:(BOOL)animated {
    if (!header || section < 0 || section > 1) return;

    UIButton *button = (UIButton *)[header viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
    [self updateMainSectionHeaderButton:button section:section animated:animated];

    UIButton *orderButton = (UIButton *)[header viewWithTag:(kVCMainSectionHeaderOrderButtonTagBase + section)];
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    BOOL reordering = (_reorderingSection == section);
    VCIconType orderIconType = reordering ? VCIconTypeCheck : VCIconTypeReorder;
    orderButton.hidden = count < 2;
    [orderButton setImage:TintImageWithColor(MakeIconImage(orderIconType, 17.0f, reordering),
                                             reordering ? VCAccentColor() : VCSecondaryTextColor())
                  forState:UIControlStateNormal];
    [orderButton setImage:TintImageWithColor(MakeIconImage(orderIconType, 17.0f, reordering),
                                             VCPrimaryTextColor())
                  forState:UIControlStateHighlighted];
    if (reordering) {
        orderButton.accessibilityLabel = (section == 0) ? @"Finish reordering configurations" : @"Finish reordering subscriptions";
        orderButton.accessibilityHint = @"Saves the current order";
    } else {
        orderButton.accessibilityLabel = (section == 0) ? @"Reorder configurations" : @"Reorder subscriptions";
        orderButton.accessibilityHint = @"Shows drag handles in this list";
    }
}

- (void)finishMainSectionTransition:(NSNumber *)transitionNumber {
    if ([transitionNumber unsignedIntegerValue] != _mainSectionTransitionToken) return;
    if (!_mainSectionTransitionInProgress) return;

    [self completeMainTableStructuralTransition];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (void)reloadMainTableDataAfterExternalChange {
    _mainSectionTransitionToken++;
    [self prepareMainTableStructuralTransition];
    [_tableView reloadData];
    [self updateMainEmptyState];
    [self completeMainTableStructuralTransition];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (void)refreshVisibleSubscriptionHeaderAccessories {
    if (!_tableView || !_subscriptionsSectionExpanded || _reorderingSection == 1) return;

    for (NSInteger subIdx = 0; subIdx < (NSInteger)[_subscriptions count]; subIdx++) {
        NSInteger row = [self rowForSubscriptionHeaderAtIndex:subIdx];
        if (row < 0) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;

        cell.accessoryView = [self accessorySubscriptionHeaderAtIndex:subIdx
                                                             expanded:(_expandedSubscription == subIdx)
                                                              loading:(_updatingSubscriptionIndex == subIdx)];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (![self mainSectionHasItems:section]) return nil;
    return [self mainSectionHeaderViewForTable:tableView section:section];
}

- (BOOL)isMainSectionExpanded:(NSInteger)section {
    if (![self mainSectionHasItems:section]) return NO;
    if (section == 0) return _configurationsSectionExpanded;
    if (section == 1) return _subscriptionsSectionExpanded;
    return NO;
}

- (void)removeStickyMainSectionHeader {
    [_stickySectionHeaderView removeFromSuperview];
    [_stickySectionHeaderView release];
    _stickySectionHeaderView = nil;
    _stickySectionHeaderSection = -1;
}

- (void)layoutStickyMainSectionHeader {
    if (!_stickySectionHeaderView || !_tableView) return;

    _stickySectionHeaderView.frame = CGRectMake(_tableView.frame.origin.x,
                                                 _tableView.frame.origin.y,
                                                 _tableView.frame.size.width,
                                                 kVCMainSectionHeaderHeight);
    [self.view bringSubviewToFront:_stickySectionHeaderView];
}

- (NSInteger)stickyMainSectionForCurrentOffset {
    if (!_tableView || _showingTerminal || _tableView.hidden) return -1;

    CGFloat top = _tableView.contentOffset.y;
    NSInteger stickySection = -1;
    for (NSInteger section = 0; section < 2; section++) {
        if (![self isMainSectionExpanded:section]) continue;
        CGRect headerRect = [_tableView rectForHeaderInSection:section];
        if (top > CGRectGetMinY(headerRect)) {
            stickySection = section;
        }
    }
    return stickySection;
}

- (void)updateStickyMainSectionHeader {
    if (_mainSectionTransitionInProgress) {
        [self layoutStickyMainSectionHeader];
        return;
    }

    NSInteger section = [self stickyMainSectionForCurrentOffset];
    if (section < 0) {
        [self removeStickyMainSectionHeader];
        return;
    }

    if (_stickySectionHeaderView && _stickySectionHeaderSection == section) {
        [self updateMainSectionHeaderView:_stickySectionHeaderView section:section animated:NO];
        [self layoutStickyMainSectionHeader];
        return;
    }

    [self removeStickyMainSectionHeader];
    _stickySectionHeaderView = [[self mainSectionHeaderViewForTable:_tableView section:section] retain];
    _stickySectionHeaderView.backgroundColor = VCBackgroundColor();
    _stickySectionHeaderView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _stickySectionHeaderSection = section;
    [self.view addSubview:_stickySectionHeaderView];
    [self layoutStickyMainSectionHeader];
}

- (void)refreshStickyMainSectionHeader {
    [self removeStickyMainSectionHeader];
    [self updateStickyMainSectionHeader];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection >= 0) {
        return indexPath.section == _reorderingSection;
    }
    if (indexPath.section == 0) {
        return YES;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        return NO;
    }
    if (!isHeader && subIdx >= 0 && subIdx < (NSInteger)[_subscriptions count] &&
        SubscriptionDictionaryIsHappEncrypted([_subscriptions objectAtIndex:subIdx])) {
        return NO;
    }
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if (_reorderingSection >= 0) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return _reorderingSection < 0;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection < 0 || indexPath.section != _reorderingSection) return NO;
    if (indexPath.section == 0) {
        return indexPath.row >= 0 && indexPath.row < (NSInteger)[_configs count];
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = NO;
    return [self mapSubscriptionRow:indexPath.row
                         toSubIndex:&subIdx
                          itemIndex:&itemIdx
                           isHeader:&isHeader] && isHeader;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    (void)tableView;
    NSInteger count = (_reorderingSection == 0) ? (NSInteger)[_configs count]
                                                : (NSInteger)[_subscriptions count];
    if (count <= 0) return sourceIndexPath;

    NSInteger row = proposedDestinationIndexPath.row;
    if (proposedDestinationIndexPath.section < _reorderingSection) row = 0;
    else if (proposedDestinationIndexPath.section > _reorderingSection) row = count - 1;
    if (row < 0) row = 0;
    if (row >= count) row = count - 1;
    return [NSIndexPath indexPathForRow:row inSection:_reorderingSection];
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView;
    if (_reorderingSection < 0 ||
        sourceIndexPath.section != _reorderingSection ||
        destinationIndexPath.section != _reorderingSection ||
        sourceIndexPath.row == destinationIndexPath.row) {
        return;
    }

    NSMutableArray *items = (_reorderingSection == 0) ? _configs : _subscriptions;
    if (sourceIndexPath.row < 0 || sourceIndexPath.row >= (NSInteger)[items count] ||
        destinationIndexPath.row < 0 || destinationIndexPath.row >= (NSInteger)[items count]) {
        return;
    }

    id selected = nil;
    if (_reorderingSection == 0 &&
        _selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        selected = [[_configs objectAtIndex:_selectedConfigIndex] retain];
    } else if (_reorderingSection == 1 &&
               _selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        selected = [[_subscriptions objectAtIndex:_selectedSubIndex] retain];
    }

    id moved = [[items objectAtIndex:sourceIndexPath.row] retain];
    [items removeObjectAtIndex:sourceIndexPath.row];
    [items insertObject:moved atIndex:destinationIndexPath.row];
    [moved release];

    if (selected) {
        NSUInteger newIndex = [items indexOfObjectIdenticalTo:selected];
        if (_reorderingSection == 0) {
            _selectedConfigIndex = (newIndex == NSNotFound) ? -1 : (NSInteger)newIndex;
        } else {
            _selectedSubIndex = (newIndex == NSNotFound) ? -1 : (NSInteger)newIndex;
        }
        [selected release];
    }

    [self normalizeSelection];
    [self saveData];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) return;

        [_configs removeObjectAtIndex:indexPath.row];
        VCRecordAppEvent(@"configuration", @"Configuration deleted",
                         [NSString stringWithFormat:@"remaining=%lu", (unsigned long)[_configs count]]);

        if (_selectedConfigIndex == indexPath.row) {
            if ([_configs count] > 0) {
                NSInteger fallback = indexPath.row;
                if (fallback >= (NSInteger)[_configs count]) fallback = (NSInteger)[_configs count] - 1;
                _selectedConfigIndex = fallback;
            } else {
                _selectedConfigIndex = -1;
            }
        } else if (_selectedConfigIndex > indexPath.row) {
            _selectedConfigIndex--;
        }

        [self normalizeSelection];
        [self saveData];
        [self reloadMainTableDataAfterExternalChange];
        [self showStatus:@"Configuration deleted" ok:YES];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        return;
    }

    if (isHeader) {
        if (![self deleteSubscriptionAtIndex:subIdx]) return;
        [self reloadMainTableDataAfterExternalChange];
        [self showStatus:@"Subscription deleted" ok:YES];
        return;
    }

    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return;
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    if (SubscriptionDictionaryIsHappEncrypted(sub)) return;
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return;
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) return;

    NSMutableArray *updatedItems = [NSMutableArray arrayWithArray:items];
    [updatedItems removeObjectAtIndex:itemIdx];
    VCRecordAppEvent(@"subscription", @"Subscription configuration deleted",
                     [NSString stringWithFormat:@"remaining_in_subscription=%lu",
                      (unsigned long)[updatedItems count]]);

    NSMutableDictionary *updatedSub = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updatedSub setObject:updatedItems forKey:@"items"];
    [_subscriptions replaceObjectAtIndex:subIdx withObject:updatedSub];

    if (_selectedSubIndex == subIdx) {
        if (_selectedSubItemIndex == itemIdx) {
            if ([updatedItems count] == 0) {
                _selectedSubItemIndex = -1;
            } else {
                NSInteger fallback = itemIdx;
                if (fallback >= (NSInteger)[updatedItems count]) fallback = (NSInteger)[updatedItems count] - 1;
                _selectedSubItemIndex = fallback;
            }
        } else if (_selectedSubItemIndex > itemIdx) {
            _selectedSubItemIndex--;
        }
    }

    [self normalizeSelection];
    [self saveData];
    [self reloadMainTableDataAfterExternalChange];
    [self showStatus:@"Subscription config deleted" ok:YES];
}

- (void)applyMarqueeDetailForMainCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (!cell || !indexPath) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) {
            [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
            return;
        }
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *uri = [cfg objectForKey:@"uri"];
        NSString *prefix = [self configPrefixTextFromURI:uri];
        NSString *tail = [self configEndpointTextFromURI:uri];
        [self applyDetailPrefix:prefix
                    prefixColor:[self configPrefixColorForURI:uri]
                    marqueeTail:tail
                         toCell:cell];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
        return;
    }

    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    if (isHeader) {
        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        NSString *prefix = [NSString stringWithFormat:@"%lu config%@",
                            (unsigned long)[items count],
                            ([items count] == 1 ? @"" : @"s")];
        NSString *tail = [self subscriptionDetailTailFromDictionary:sub];
        if ([tail length] > 0) {
            prefix = [prefix stringByAppendingString:@" •"];
        }
        [self applyDetailPrefix:prefix marqueeTail:tail toCell:cell];
        return;
    }

    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) {
        [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
        return;
    }

    NSString *uri = [items objectAtIndex:itemIdx];
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *tail = SubscriptionDictionaryIsHappEncrypted(sub)
        ? kHiddenLinkText
        : [self configEndpointTextFromURI:uri];
    [self applyDetailPrefix:prefix
                prefixColor:[self configPrefixColorForURI:uri]
                marqueeTail:tail
                     toCell:cell];
}

- (void)runQueuedMainMarqueeRelayout {
    _queuedMainMarqueeRelayout = NO;
    if (!_tableView || _showingTerminal) return;

    NSArray *visible = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *ip in visible) {
        UITableViewCell *visibleCell = [_tableView cellForRowAtIndexPath:ip];
        if (visibleCell) {
            [self applyMarqueeDetailForMainCell:visibleCell atIndexPath:ip];
        }
    }
}

- (void)scheduleMainMarqueeRelayout {
    if (_queuedMainMarqueeRelayout) return;
    _queuedMainMarqueeRelayout = YES;
    [self performSelector:@selector(runQueuedMainMarqueeRelayout) withObject:nil afterDelay:0.0];
}

- (void)refreshMainListCellAppearance:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (!cell || !indexPath) return;
    if ([cell isKindOfClass:[VCMainListCell class]]) {
        [(VCMainListCell *)cell refreshVisualAppearance];
        return;
    }

    BOOL selectedConfig = (indexPath.section == 0 && _selectedConfigIndex == indexPath.row);
    cell.backgroundColor = selectedConfig ? VCSelectedCellColor() : VCCellBackgroundColor();
    cell.contentView.backgroundColor = [UIColor clearColor];
}

- (void)refreshVisiblePingAccessoriesForURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0 || !_tableView) return;

    NSArray *visibleRows = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visibleRows) {
        NSInteger tag = -1;
        NSString *rowURI = nil;

        if (indexPath.section == 0) {
            if (indexPath.row >= 0 && indexPath.row < (NSInteger)[_configs count]) {
                NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
                rowURI = [cfg objectForKey:@"uri"];
                tag = 10000 + indexPath.row;
            }
        } else {
            NSInteger subIdx = -1;
            NSInteger itemIdx = -1;
            BOOL isHeader = YES;
            if ([self mapSubscriptionRow:indexPath.row
                              toSubIndex:&subIdx
                               itemIndex:&itemIdx
                                isHeader:&isHeader] && !isHeader) {
                NSArray *items = [self subscriptionItemsAtIndex:subIdx];
                if (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) {
                    rowURI = [items objectAtIndex:itemIdx];
                    tag = 20000 + (subIdx * 1000) + itemIdx;
                }
            }
        }

        if (tag < 0 || ![rowURI isEqualToString:uri]) continue;
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        cell.accessoryView = [self accessoryPingWithTag:tag uri:rowURI];
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
        [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    }
}

- (void)refreshVisibleSubscriptionPingAccessories {
    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSArray *visibleRows = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visibleRows) {
        if (indexPath.section != 1) continue;

        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if (![self mapSubscriptionRow:indexPath.row
                           toSubIndex:&subIdx
                            itemIndex:&itemIdx
                             isHeader:&isHeader] || isHeader) {
            continue;
        }

        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) continue;

        NSString *uri = [items objectAtIndex:itemIdx];
        NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        cell.accessoryView = [self accessoryPingWithTag:tag uri:uri];
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
        [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger mappedSubIdx = -1;
    NSInteger mappedItemIdx = -1;
    BOOL mappedIsHeader = YES;
    VCMainListCellKind visualKind = VCMainListCellKindConfigurationItem;
    BOOL firstItem = NO;
    BOOL lastItem = NO;
    BOOL expanded = NO;
    BOOL active = NO;
    NSString *cellID = @"VCItemCell";

    if (indexPath.section == 0) {
        firstItem = (indexPath.row == 0);
        lastItem = (indexPath.row == (NSInteger)[_configs count] - 1);
        active = (_selectedConfigIndex == indexPath.row);
        cellID = @"VCConfigurationItemCell";
    } else if (indexPath.section == 1 &&
        [self mapSubscriptionRow:indexPath.row
                      toSubIndex:&mappedSubIdx
                       itemIndex:&mappedItemIdx
                        isHeader:&mappedIsHeader]) {
        if (mappedIsHeader) {
            visualKind = VCMainListCellKindSubscriptionHeader;
            expanded = (_expandedSubscription == mappedSubIdx);
            active = (_selectedSubIndex == mappedSubIdx && _selectedSubItemIndex >= 0);
            cellID = @"VCSubscriptionHeaderCell";
        } else {
            visualKind = VCMainListCellKindSubscriptionItem;
            NSArray *mappedItems = [self subscriptionItemsAtIndex:mappedSubIdx];
            firstItem = (mappedItemIdx == 0);
            lastItem = (mappedItemIdx == (NSInteger)[mappedItems count] - 1);
            active = (_selectedSubIndex == mappedSubIdx && _selectedSubItemIndex == mappedItemIdx);
            cellID = @"VCSubscriptionItemCell";
        }
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[[VCMainListCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID] autorelease];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0f];
    }
    cell.clipsToBounds = YES;
    cell.contentView.clipsToBounds = YES;
    cell.indentationLevel = 0;
    cell.indentationWidth = 14.0f;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.showsReorderControl = (_reorderingSection == indexPath.section);
    cell.selectionStyle = (_reorderingSection >= 0) ? UITableViewCellSelectionStyleNone
                                                     : UITableViewCellSelectionStyleBlue;
    VCAppearanceApplyCell(cell);
    if ([cell isKindOfClass:[VCMainListCell class]]) {
        [(VCMainListCell *)cell configureVisualKind:visualKind
                                          expanded:expanded
                                         firstItem:firstItem
                                          lastItem:lastItem
                                             active:active];
    } else {
        [self refreshMainListCellAppearance:cell atIndexPath:indexPath];
    }

    if (indexPath.section == 0) {
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        NSString *shownConfigName = ([name length] > 0) ? name : [NSString stringWithFormat:@"Config %ld", (long)(indexPath.row + 1)];
        cell.textLabel.text = [self maskedLinkText:shownConfigName];
        if (_reorderingSection != 0) {
            NSString *uri = [cfg objectForKey:@"uri"];
            cell.accessoryView = [self accessoryPingWithTag:(10000 + indexPath.row) uri:uri];
        }
    } else {
        NSInteger subIdx = mappedSubIdx;
        NSInteger itemIdx = mappedItemIdx;
        BOOL isHeader = mappedIsHeader;
        if (subIdx >= 0) {
            NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
            NSString *name = [sub objectForKey:@"name"];
            NSString *url = [sub objectForKey:@"url"];
            NSArray *items = [self subscriptionItemsAtIndex:subIdx];

            if (isHeader) {
                NSString *shownName = ([name length] > 0) ? name : @"";
                NSString *host = [self hostFromURLString:url];
                if ([shownName length] == 0 || [shownName isEqualToString:host]) {
                    shownName = [self subscriptionNameFromURLString:url];
                }
                shownName = [self maskedLinkText:shownName];
                cell.textLabel.text = shownName;
                if (_reorderingSection != 1) {
                    BOOL loading = (_updatingSubscriptionIndex == subIdx);
                    cell.accessoryView = [self accessorySubscriptionHeaderAtIndex:subIdx
                                                                       expanded:(_expandedSubscription == subIdx)
                                                                        loading:loading];
                }
            } else {
                NSString *uri = [items objectAtIndex:itemIdx];
                cell.indentationLevel = 0;
                NSString *itemName = [self displayNameForSubscriptionURI:uri
                                                                    index:itemIdx
                                                             subscription:sub];
                cell.textLabel.text = [self maskedLinkText:itemName];
                NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
                cell.accessoryView = [self accessoryPingWithTag:tag uri:uri];
            }
        } else {
            cell.textLabel.text = @"(invalid row)";
        }
    }

    [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainMarqueeRelayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCAppearanceApplyCell(cell);
    [self refreshMainListCellAppearance:cell atIndexPath:indexPath];
    [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainMarqueeRelayout];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    if (![self mainSectionHasItems:section]) return;
    [self updateMainSectionHeaderView:view section:section animated:NO];
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
    [self updateStickyMainSectionHeader];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self stabilizeMainTableOffsetDuringStructuralTransition];
        [self updatePhoneConnectionLayout];
        [self updateStickyMainSectionHeader];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView != _tableView) return;
    _mainTableDragStartOffsetY = scrollView.contentOffset.y;
    _mainTableDragStartOffsetValid = YES;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView != _tableView || IsPadDevice() || _showingTerminal || !targetContentOffset) return;

    CGFloat referenceOffset = _mainTableDragStartOffsetValid
        ? _mainTableDragStartOffsetY
        : scrollView.contentOffset.y;
    CGFloat proposedOffset = targetContentOffset->y;
    CGFloat snappedOffset = [self phoneConnectionSnapOffsetForProposedOffset:proposedOffset
                                                               currentOffset:referenceOffset
                                                                    velocity:velocity.y];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    if (snappedOffset <= expandedOffset + 0.5f) {
        _phoneConnectionCompact = NO;
    } else if (snappedOffset >= -0.5f) {
        _phoneConnectionCompact = YES;
    }

    targetContentOffset->y = snappedOffset;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self snapPhoneConnectionLayoutIfNeededAnimated:YES];
        [self scheduleMainMarqueeRelayout];
        [self recordMainLayoutEvent:@"Main list scroll ended" section:-1];
    } else if (scrollView == _logView) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == _tableView) {
        if (!decelerate) {
            CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
            CGFloat expandedOffset = -collapseDistance;
            CGFloat currentOffset = scrollView.contentOffset.y;
            if (currentOffset > expandedOffset + 0.5f && currentOffset < -0.5f) {
                [self animatePhoneConnectionToOffset:(_phoneConnectionCompact ? 0.0f : expandedOffset)];
            } else {
                [self snapPhoneConnectionLayoutIfNeededAnimated:YES];
            }
            [self scheduleMainMarqueeRelayout];
            [self recordMainLayoutEvent:@"Main list drag ended" section:-1];
        }
        _mainTableDragStartOffsetValid = NO;
    } else if (scrollView == _logView && !decelerate) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView != _tableView) return;
    [self updatePhoneConnectionLayout];
    [self updateStickyMainSectionHeader];
    [self scheduleMainMarqueeRelayout];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection >= 0) {
        [_tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    if (_mainSectionTransitionInProgress) {
        [_tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    BOOL animateSubscriptionsSection = NO;
    BOOL selectionChanged = NO;
    NSInteger oldExpandedSubscription = -1;
    NSInteger oldExpandedHeaderRow = -1;
    NSInteger oldExpandedItemCount = 0;
    NSString *oldURI = nil;
    if (_connected) {
        NSString *u = [self uriForCurrentSelection];
        if ([u isKindOfClass:[NSString class]] && [u length] > 0) {
            oldURI = [u copy];
        }
    }

    if (indexPath.section == 0) {
        VCRecordAppEvent(@"ui", @"Configuration selected",
                         [NSString stringWithFormat:@"index=%ld total=%lu",
                          (long)indexPath.row, (unsigned long)[_configs count]]);
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        _selectedConfigIndex = indexPath.row;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        selectionChanged = YES;
        [self showStatus:[NSString stringWithFormat:@"Selected config: %@", name ? name : @"(unnamed)"] ok:YES];
    } else {
        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if ([self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
            if (isHeader) {
                VCRecordAppEvent(@"ui", @"Subscription expanded state changed",
                                 [NSString stringWithFormat:@"index=%ld expanded=%d configs=%lu",
                                  (long)subIdx,
                                  _expandedSubscription == subIdx ? 0 : 1,
                                  (unsigned long)[[self subscriptionItemsAtIndex:subIdx] count]]);
                animateSubscriptionsSection = YES;
                oldExpandedSubscription = _expandedSubscription;
                if (oldExpandedSubscription >= 0) {
                    oldExpandedHeaderRow = [self rowForSubscriptionHeaderAtIndex:oldExpandedSubscription];
                    oldExpandedItemCount = (NSInteger)[[self subscriptionItemsAtIndex:oldExpandedSubscription] count];
                }
                if (_expandedSubscription == subIdx) {
                    _expandedSubscription = -1;
                } else {
                    _expandedSubscription = subIdx;
                    if ([[self subscriptionItemsAtIndex:subIdx] count] == 0) {
                        [self refreshSubscriptionAtIndex:subIdx showStatus:NO];
                    }
                }
                NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
                NSString *name = [sub objectForKey:@"name"];
                [self showStatus:[NSString stringWithFormat:@"Subscription: %@", name ? name : @"(unnamed)"] ok:YES];
            } else {
                VCRecordAppEvent(@"ui", @"Subscription configuration selected",
                                 [NSString stringWithFormat:@"subscription_index=%ld item_index=%ld",
                                  (long)subIdx, (long)itemIdx]);
                NSArray *items = [self subscriptionItemsAtIndex:subIdx];
                NSString *uri = (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) ? [items objectAtIndex:itemIdx] : @"";
                _selectedConfigIndex = -1;
                _selectedSubIndex = subIdx;
                _selectedSubItemIndex = itemIdx;
                selectionChanged = YES;
                NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
                NSString *itemName = [self displayNameForSubscriptionURI:uri
                                                                    index:itemIdx
                                                             subscription:sub];
                [self showStatus:[NSString stringWithFormat:@"Selected: %@", itemName] ok:YES];
            }
        }
    }

    [_tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self normalizeSelection];
    if (selectionChanged || animateSubscriptionsSection) [self saveMainState];
    if (_connected && oldURI) {
        NSString *newURI = [self uriForCurrentSelection];
        [self reconnectToURIIfNeededFrom:oldURI to:newURI];
    }

    if (animateSubscriptionsSection) {
        NSInteger newExpandedSubscription = _expandedSubscription;
        NSInteger newExpandedHeaderRow = (newExpandedSubscription >= 0)
            ? [self rowForSubscriptionHeaderAtIndex:newExpandedSubscription]
            : -1;
        NSInteger newExpandedItemCount = (newExpandedSubscription >= 0)
            ? (NSInteger)[[self subscriptionItemsAtIndex:newExpandedSubscription] count]
            : 0;

        NSMutableArray *deletedRows = [NSMutableArray array];
        for (NSInteger item = 0; item < oldExpandedItemCount; item++) {
            [deletedRows addObject:[NSIndexPath indexPathForRow:(oldExpandedHeaderRow + 1 + item)
                                                       inSection:1]];
        }

        NSMutableArray *insertedRows = [NSMutableArray array];
        for (NSInteger item = 0; item < newExpandedItemCount; item++) {
            [insertedRows addObject:[NSIndexPath indexPathForRow:(newExpandedHeaderRow + 1 + item)
                                                        inSection:1]];
        }

        NSUInteger transitionToken = ++_mainSectionTransitionToken;
        [self prepareMainTableStructuralTransition];
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            if (transitionToken != _mainSectionTransitionToken) return;
            [self completeMainTableStructuralTransition];
            [self refreshVisibleSubscriptionHeaderAccessories];
            [self refreshStickyMainSectionHeader];
        }];

        [_tableView beginUpdates];
        if ([deletedRows count] > 0) {
            [_tableView deleteRowsAtIndexPaths:deletedRows withRowAnimation:UITableViewRowAnimationFade];
        }
        if ([insertedRows count] > 0) {
            [_tableView insertRowsAtIndexPaths:insertedRows withRowAnimation:UITableViewRowAnimationFade];
        }
        [_tableView endUpdates];
        [CATransaction commit];

        if ([deletedRows count] == 0 && [insertedRows count] == 0) {
            [self refreshVisibleSubscriptionHeaderAccessories];
        }
    } else {
        [_tableView reloadData];
    }
    [oldURI release];
}

#pragma mark - Import UI

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == VCActionSheetTagImport) {
        if (buttonIndex == 0) {
            VCRecordAppEvent(@"import", @"Clipboard import selected", nil);
            NSString *clip = [[UIPasteboard generalPasteboard] string];
            [self importTextEntry:clip];
        } else if (buttonIndex == 1) {
            VCRecordAppEvent(@"import", @"File import selected", nil);
            [self startFileBrowserImportFlow];
        } else if (buttonIndex == 2) {
            VCRecordAppEvent(@"import", @"QR import selected", nil);
            [self startQRImportFlow];
        } else if (buttonIndex == 3) {
            VCRecordAppEvent(@"import", @"Manual import selected", nil);
            UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Manual Import"
                                                          message:@"Paste a config or subscription link"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                                otherButtonTitles:@"Import", nil] autorelease];
            av.alertViewStyle = UIAlertViewStylePlainTextInput;
            av.tag = VCAlertTagImportManual;

            UITextField *tf = [av textFieldAtIndex:0];
            tf.placeholder = @"vless://..., or https://..., happ://add/...";
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.keyboardType = UIKeyboardTypeURL;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;

            [av show];
        } else {
            VCRecordAppEvent(@"import", @"Import menu canceled", nil);
        }
        return;
    }

}

- (void)qrScanVCDidCancel:(UIViewController *)vc {
    (void)vc;
    [self dismissViewControllerAnimated:YES completion:nil];
    [self showStatus:@"QR import canceled" ok:YES];
    VCRecordAppEvent(@"import", @"QR scan canceled", nil);
}

- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text {
    (void)vc;
    NSString *payload = [[self safeTrim:text] copy];
    VCRecordAppEvent(@"import", @"QR payload recognized", nil);
    NSString *karingError = nil;
    NSDictionary *karingDescriptor = VCKaringLANDownloadDescriptor(payload, &karingError);
    [self dismissViewControllerAnimated:YES completion:^{
        if (![payload isKindOfClass:[NSString class]] || [payload length] == 0) {
            [self showStatus:@"QR code does not contain import data" ok:NO];
            [payload release];
            return;
        }

        if ([karingDescriptor isKindOfClass:[NSDictionary class]]) {
            [self receiveKaringBackupWithDescriptor:karingDescriptor];
            [payload release];
            return;
        }
        if ([karingError length] > 0) {
            [self showStatus:karingError ok:NO];
            [payload release];
            return;
        }

        NSArray *links = [self extractImportLinksFromText:payload];
        if ([links isKindOfClass:[NSArray class]] && [links count] > 0) {
            NSString *subscriptionURL = nil;
            for (NSString *candidate in links) {
                if ([self isSubscriptionURL:candidate]) {
                    subscriptionURL = candidate;
                    break;
                }
            }

            if ([subscriptionURL isKindOfClass:[NSString class]] && [subscriptionURL length] > 0) {
                [self importSubscriptionURL:subscriptionURL];
                [payload release];
                return;
            }

            if ([links count] == 1) {
                NSString *single = [links objectAtIndex:0];
                [self importTextEntry:single];
                [payload release];
                return;
            }
        }

        [self importTextEntry:payload];
        [payload release];
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == VCAlertTagUpdateAvailable) {
        if (buttonIndex != alertView.cancelButtonIndex) {
            VCOpenGitHubLatestRelease(_availableReleaseURL);
        }
        return;
    }

    if (alertView.tag == VCAlertTagImportManual) {
        if (buttonIndex != 1) {
            VCRecordAppEvent(@"import", @"Manual import canceled", nil);
            return;
        }
        VCRecordAppEvent(@"import", @"Manual import submitted", nil);
        NSString *txt = [[alertView textFieldAtIndex:0] text];
        [self importTextEntry:txt];
        return;
    }

    if (alertView.tag == VCAlertTagPlainHTTPSubscription) {
        void (^confirmation)(void) = _pendingPlainHTTPConfirmation
            ? Block_copy(_pendingPlainHTTPConfirmation)
            : NULL;
        void (^cancellation)(void) = _pendingPlainHTTPCancellation
            ? Block_copy(_pendingPlainHTTPCancellation)
            : NULL;
        if (_pendingPlainHTTPConfirmation) {
            Block_release(_pendingPlainHTTPConfirmation);
            _pendingPlainHTTPConfirmation = NULL;
        }
        if (_pendingPlainHTTPCancellation) {
            Block_release(_pendingPlainHTTPCancellation);
            _pendingPlainHTTPCancellation = NULL;
        }

        if (buttonIndex != alertView.cancelButtonIndex && confirmation) {
            VCRecordAppEvent(@"import", @"Plain HTTP subscription approved", nil);
            confirmation();
        } else {
            VCRecordAppEvent(@"import", @"Plain HTTP subscription declined", nil);
            if (cancellation) cancellation();
            [self showStatus:@"HTTP subscription canceled" ok:YES];
        }
        if (confirmation) Block_release(confirmation);
        if (cancellation) Block_release(cancellation);
        return;
    }

    if (alertView.tag == VCAlertTagImportInsecureSubscription) {
        NSArray *urlStrings = [_pendingInsecureImportURLs retain];
        BOOL useHappHeaders = _pendingInsecureImportUsesHappHeaders;
        [_pendingInsecureImportURLs release];
        _pendingInsecureImportURLs = nil;
        _pendingInsecureImportUsesHappHeaders = NO;

        if (buttonIndex == 1) {
            VCRecordAppEvent(@"import", @"Insecure subscription fetch approved",
                             [NSString stringWithFormat:@"count=%lu", (unsigned long)[urlStrings count]]);
            if ([urlStrings count] == 1) {
                NSString *urlString = [urlStrings objectAtIndex:0];
                if (useHappHeaders && [self isHappAddLink:urlString]) {
                    urlString = [self targetFromHappAddLink:urlString];
                }
                [self importSubscriptionURL:urlString
                         allowInsecureFetch:YES
                             allowPlainHTTP:(!useHappHeaders && URLStringUsesPlainHTTP(urlString))
                                 happSource:useHappHeaders];
            } else if ([urlStrings count] > 1) {
                BOOL includesPlainHTTP = NO;
                for (NSString *urlString in urlStrings) {
                    if (![self isHappEncryptedLink:urlString] && ![self isHappAddLink:urlString] &&
                        URLStringUsesPlainHTTP(urlString)) {
                        includesPlainHTTP = YES;
                        break;
                    }
                }
                [self startBackgroundSubscriptionImportForURLs:urlStrings
                                            allowInsecureFetch:YES
                                                   startStatus:@"Importing insecure subscriptions..."
                                            importedPrefixPart:nil
                                   fallbackSubscriptionsByURL:nil
                                                allowPlainHTTP:includesPlainHTTP];
            }
        } else {
            VCRecordAppEvent(@"import", @"Insecure subscription fetch declined",
                             [NSString stringWithFormat:@"count=%lu", (unsigned long)[urlStrings count]]);
            [self showStatus:([urlStrings count] == 1 ? @"Subscription import canceled"
                                                      : @"Insecure subscriptions skipped")
                          ok:YES];
        }
        [urlStrings release];
        return;
    }
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
}
@property (nonatomic, retain) UIWindow *window;
@end

@implementation AppDelegate
@synthesize window = _window;

- (BOOL)openImportURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]] || ![url isFileURL]) return NO;
    UIViewController *root = _window.rootViewController;
    if (![root isKindOfClass:[MainVC class]]) return NO;
    VCRecordAppEvent(@"import", @"File import opened by another application", nil);
    [(MainVC *)root importFileAtURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;

    VCRecordAppEvent(@"lifecycle", @"Application launched", nil);
    ClearLogsViaDaemon();
    VCAppearanceApplyStatusBar();
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = VCBackgroundColor();
    MainVC *vc = [[[MainVC alloc] init] autorelease];
    _window.rootViewController = vc;
    [_window makeKeyAndVisible];

    NSURL *launchURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if ([launchURL isFileURL]) {
        [self performSelector:@selector(openImportURL:) withObject:launchURL afterDelay:0.15];
    }
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application became active", nil);
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application entered background", nil);
    [[VCAppEventRecorder sharedRecorder] flushNow];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    (void)application;
    return [self openImportURL:url];
}

- (BOOL)application:(UIApplication *)application
             openURL:(NSURL *)url
   sourceApplication:(NSString *)sourceApplication
          annotation:(id)annotation {
    (void)application;
    (void)sourceApplication;
    (void)annotation;
    return [self openImportURL:url];
}

- (BOOL)application:(UIApplication *)application
             openURL:(NSURL *)url
             options:(NSDictionary *)options {
    (void)application;
    (void)options;
    return [self openImportURL:url];
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application will terminate", nil);
    [[VCAppEventRecorder sharedRecorder] flushNow];
    ClearLogsViaDaemon();
}

- (void)dealloc {
    [_window release];
    [super dealloc];
}

@end

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int rc = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return rc;
}
