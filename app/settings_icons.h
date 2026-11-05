#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, VCSettingsIconType) {
    VCSettingsIconNone = -1,
    VCSettingsIconAutoUpdate = 0,
    VCSettingsIconPreserveNames = 1,
    VCSettingsIconStealth = 2,
    VCSettingsIconSortPing = 3,
    VCSettingsIconRouting = 4,
    VCSettingsIconPing = 5,
    VCSettingsIconXrayVersion = 6,
    VCSettingsIconXmux = 7,
    VCSettingsIconLight = 8,
    VCSettingsIconDark = 9,
    VCSettingsIconAccent = 10,
    VCSettingsIconAutomaticChecks = 11,
    VCSettingsIconCheckUpdates = 12,
    VCSettingsIconDebug = 13,
    VCSettingsIconGitHubLegacy = 14,
    VCSettingsIconAbout = 15,
    VCSettingsIconCredits = 16,
    VCSettingsIconFAQ = 17,
    VCSettingsIconGitHub = 18,
    VCSettingsIconCount = 19,
};

VCSettingsIconType VCSettingsIconForRow(NSInteger section, NSInteger row);
UIImage *VCSettingsIconImage(VCSettingsIconType icon);
