#import "app_support.h"

NSInteger const kVCSubscriptionDeleteAlertTag = 3101;
NSInteger const kVCSubscriptionRenameAlertTag = 3102;
NSInteger const kVCSettingsUpdateAlertTag = 3103;
NSInteger const kVCSettingsPingTypeActionSheetTag = 3104;
NSInteger const kVCSettingsTitleMarqueeTag = 7400;
NSInteger const kVCSettingsDetailMarqueeTag = 7401;
NSInteger const kVCMainDetailContainerTag = 7410;
NSInteger const kVCMainDetailPrefixTag = 7411;
NSInteger const kVCMainDetailTailTag = 7412;
NSInteger const kVCMainSectionHeaderButtonTagBase = 7420;
NSInteger const kVCMainSectionHeaderCountTagBase = 7430;
NSInteger const kVCSubscriptionHeaderChevronTag = 7460;
NSInteger const kVCSubscriptionInfoButtonTagBase = 30000;
NSInteger const kVCSubscriptionPingButtonTagBase = 40000;
NSInteger const kVCSubscriptionWebPageButtonTagBase = 50000;
NSInteger const kVCSubscriptionSupportButtonTagBase = 60000;
const char *kVCProxyPingHost = "www.gstatic.com";
const uint16_t kVCProxyPingPort = 80;
const char *kVCProxyPingRequest =
    "GET /generate_204 HTTP/1.1\r\n"
    "Host: www.gstatic.com\r\n"
    "User-Agent: vless-core-app-ping\r\n"
    "Connection: close\r\n\r\n";
CGFloat const kVCDetailLabelGap = 4.0f;
NSTimeInterval const kVCMarqueePauseSeconds = 1.0;
CGFloat const kVCMarqueePixelsPerSecond = 28.0f;
