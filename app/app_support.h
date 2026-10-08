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
#import "../common/app_constants.h"
#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
#import "../common/secure_store.h"
#import "../common/connection_logic.h"
#include "../common/main_geometry.h"
#import "../common/list_logic.h"

extern char **environ;

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
    VCIconTypeGlobe = 12,
    VCIconTypeSupport = 13,
    VCIconTypeDocument = 14,
    VCIconTypeStorage = 15,
    VCIconTypeCalendar = 16,
};

extern NSInteger const kVCSubscriptionDeleteAlertTag;
extern NSInteger const kVCSubscriptionRenameAlertTag;
extern NSInteger const kVCSettingsUpdateAlertTag;
extern NSInteger const kVCSettingsPingTypeActionSheetTag;
extern NSInteger const kVCSettingsTitleMarqueeTag;
extern NSInteger const kVCSettingsDetailMarqueeTag;
extern NSInteger const kVCMainDetailContainerTag;
extern NSInteger const kVCMainDetailPrefixTag;
extern NSInteger const kVCMainDetailTailTag;
extern NSInteger const kVCMainSectionHeaderButtonTagBase;
extern NSInteger const kVCMainSectionHeaderCountTagBase;
extern NSInteger const kVCSubscriptionHeaderChevronTag;
extern NSInteger const kVCSubscriptionInfoButtonTagBase;
extern NSInteger const kVCSubscriptionPingButtonTagBase;
extern NSInteger const kVCSubscriptionWebPageButtonTagBase;
extern NSInteger const kVCSubscriptionSupportButtonTagBase;
extern const char *kVCProxyPingHost;
extern const uint16_t kVCProxyPingPort;
extern const char *kVCProxyPingRequest;
extern CGFloat const kVCDetailLabelGap;
extern NSTimeInterval const kVCMarqueePauseSeconds;
extern CGFloat const kVCMarqueePixelsPerSecond;

BOOL VCSaveProtectedConfigurationData(NSArray *configs, NSArray *subscriptions);

NSDictionary *VCLoadProtectedConfigurationData(BOOL *fileExistsOut);

NSString *SendCommand(NSString *cmdLine);

NSString *ConnectCommandForURI(NSString *uri, BOOL protectLogs);

NSString *RoutingPolicyText(void);

int ConnectLatencyMs(const char *host, uint16_t port, int timeout_ms, int *latency_ms,
                            VCPingCancellation *cancellation);

int ConnectLatencyBestOfNMs(const char *host, uint16_t port, int timeout_ms, int attempts, int *latency_ms,
                                   VCPingCancellation *cancellation);

int write_all(int fd, const void *buf, size_t len);

int connect_loopback_port(uint16_t port, int timeout_ms, VCPingCancellation *cancellation);

int socks5_connect_domain(int fd, const char *host, uint16_t port);

int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms);

int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms,
                                 VCPingCancellation *cancellation);

int ProxyGetViaTempCoreMs(const char *uri, const char *xray_version,
                                 int timeout_ms, int attempts, int *latency_ms,
                                 VCPingCancellation *cancellation);
NSString *VCPingNetworkSignature(void);

int ICMPLatencyBestOfNMs(const char *host,
                                int timeout_ms,
                                int attempts,
                                int *latency_ms,
                                VCPingCancellation *cancellation);

NSString *DetectCoreBinaryVersion(void);

NSDictionary *DetectCurlDependencyVersions(void);

NSString *ReadTextFileBestEffort(NSString *path);

NSString *DetectOpenSSLPatchStatus(void);

NSString *DetectRedsocksVersion(void);

NSString *AppDisplayName(void);

NSString *AppShortVersion(void);

NSString *AppUserAgent(void);

NSString *DeviceModelName(void);

NSString *AppBuildVersion(void);

NSString *AppVersionSummary(void);

NSString *AppBuildMetadataSummary(void);

NSString *SubscriptionHWID(void);

NSData *FetchURLViaVlessCoreCurl(NSString *urlString,
                                       BOOL allowInsecureFetch,
                                       BOOL allowPlainHTTP,
                                       BOOL useHappHeaders,
                                       BOOL sendSubscriptionHWID,
                                       NSString *userAgent,
                                       NSString **errOut,
                                       NSString **headersOut,
                                       int *exitCodeOut);

void VCCacheSuccessfulUpdateResult(NSDictionary *result);

BOOL VCAutomaticUpdateCheckIsFresh(void);

void VCShowUpdateAvailableAlert(NSDictionary *result,
                                       id<UIAlertViewDelegate> delegate,
                                       NSInteger tag);

NSString *ClearLogsViaDaemon(void);

NSString *ReadDaemonLog(NSInteger index, NSUInteger maxBytes);

NSString *ReadLogAtIndex(NSInteger index);

UIFont *VCLogRegularFont(void);

NSAttributedString *VCFormattedLogText(NSString *text) NS_AVAILABLE_IOS(6_0);

void VCRecordDaemonAuthorizationFailure(NSString *response);

void VCRecordAppEvent(NSString *category, NSString *action, NSString *detail);

void VCSetLabelMinimumScaleFactor(UILabel *label, CGFloat factor);

CGFloat VCMainStatusBarInset(void);

VCStoragePaths VCMainStoragePaths(void);

UIColor *VCAppearanceAccentColorAtIndex(NSInteger index, BOOL dark);

UIColor *VCBackgroundColor(void);

UIColor *VCCellBackgroundColor(void);

UIColor *VCPrimaryTextColor(void);

UIColor *VCSecondaryTextColor(void);

UIColor *VCSeparatorColor(void);

UIColor *VCSelectedCellColor(void);

UIColor *VCAccentColor(void);

UIColor *VCDefaultAccentColor(void);

UIColor *VCSuccessColor(void);

UIColor *VCErrorColor(void);

BOOL IsPadDevice(void);

BOOL VCPreferGitHubLegacy(void);

void VCOpenGitHubProject(void);

void VCOpenGitHubLatestRelease(NSString *fallbackURLString);

UIInterfaceOrientation CurrentInterfaceOrientation(void);

VCPingType VCSelectedPingType(void);

NSString *VCPingTypeName(VCPingType type);

NSString *VCSelectedPingTypeText(void);

NSString *VCSelectedXrayVersion(void);

BOOL VCXrayVersionSpoofEnabled(void);

NSString *VCActiveXrayVersion(void);

NSString *VCSelectedXrayVersionText(void);

UIImage *LoadBundledIconScaled(NSString *baseName, CGFloat size);

UIImage *SolidImageWithColor(UIColor *color);

UIImage *TintImageWithColor(UIImage *image, UIColor *color);

UIImage *LoadBundledIconTinted(NSString *baseName, CGFloat size, UIColor *color);

void VCAppearanceApplyTable(UITableView *tableView);

void VCAppearanceApplyCell(UITableViewCell *cell);

void VCAppearanceApplyHeaderView(UIView *view);

void VCAppearanceRefreshVisibleTableHeaders(UITableView *tableView);

void VCAppearanceScheduleVisibleTableHeadersRefresh(UITableView *tableView);

void VCAppearanceApplyNavigationBar(UINavigationBar *navigationBar);

UIStatusBarStyle VCAppearancePreferredStatusBarStyle(void);

void VCAppearanceApplyStatusBar(void);

UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active);

UIView *VCCreateDisclosureAccessoryView(void);

UIImage *VCAppearanceAccentSwatchImage(UIColor *color);

UIImage *VCMakeConnectionGlow(UIColor *color);

CGFloat VCSubscriptionCardHeight(NSString *description,
                                        CGFloat cardWidth,
                                        BOOL reordering);

void VCApplyTouchFeedbackToButton(UIButton *button, id target);
