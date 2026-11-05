#import <Foundation/Foundation.h>
#include "../common/main_geometry.h"
#include "check.h"
#include <math.h>
static const CGSize CGSizeZero={0,0};
enum { NSLineBreakByWordWrapping=0 };
static CGSize CGSizeMake(CGFloat w,CGFloat h) { return (CGSize){w,h}; }
@interface UIFont : NSObject {
    CGFloat _lineHeight,_glyphWidth;
}
@property CGFloat lineHeight,glyphWidth;
@end
@implementation UIFont
@synthesize lineHeight=_lineHeight,glyphWidth=_glyphWidth;
@end
@interface NSString (VCSettingsMeasure)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode;
@end
@implementation NSString (VCSettingsMeasure)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode {
    CHECK("settings-layout/word-wrap-measurement",mode==NSLineBreakByWordWrapping);
    CGFloat lines=self.length ? ceil(self.length*font.glyphWidth/MAX(1.0,size.width)) : 0;
    return CGSizeMake(MIN(size.width,self.length*font.glyphWidth),lines*font.lineHeight);
}
@end
#include "settings_row_type.inc"
VCSettingsRowLayout;
#include "settings_row_layout.inc"
static CGFloat bottom(CGRect r) { return r.origin.y+r.size.height; }
static CGFloat right(CGRect r) { return r.origin.x+r.size.width; }
static void inside(CGRect r,CGFloat width,CGFloat height) {
    CHECK("settings-layout/finite-frames",isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height));
    CHECK("settings-layout/nonnegative-frames",r.origin.x>=0 && r.origin.y>=0 && r.size.width>=0 && r.size.height>=0);
    CHECK("settings-layout/inside-row",right(r)<=width+0.01 && bottom(r)<=height+0.01);
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    UIFont *title=[[[UIFont alloc] init] autorelease],*detail=[[[UIFont alloc] init] autorelease];
    title.lineHeight=21; title.glyphWidth=8.5; detail.lineHeight=17; detail.glyphWidth=7;
    VCSettingsRowLayout shortRow=VCSettingsMeasureRow(300,49,15,CGSizeMake(20,20),@"Ping",title,@"Ping settings",detail);
    CHECK("settings-layout/short-row-keeps-native-height",!shortRow.expanded && shortRow.height==44);
    VCSettingsRowLayout longRow=VCSettingsMeasureRow(300,49,15,CGSizeMake(79,27),@"Auto-update subscriptions",title,@"Refresh subscriptions on app open",detail);
    CHECK("settings-layout/narrow-title-wraps",longRow.expanded && longRow.title.size.height>title.lineHeight && longRow.height>44);
    CHECK("settings-layout/description-uses-space-under-switch",longRow.detail.size.width>longRow.title.size.width && right(longRow.detail)>longRow.accessory.origin.x);
    CHECK("settings-layout/switch-native-size",longRow.accessory.size.width==79 && longRow.accessory.size.height==27);
    VCSettingsRowLayout wideRow=VCSettingsMeasureRow(700,49,15,CGSizeMake(79,27),@"Auto-update subscriptions",title,@"Refresh subscriptions on app open",detail);
    CHECK("settings-layout/wide-row-stays-compact",!wideRow.expanded && wideRow.height==44);
    NSString *titles[] = {@"Auto-update subscriptions",@"Preserve custom names",@"Stealth mode",@"Sort configs by ping",@"Routing",@"Ping",@"Xray version spoof",@"Use XMUX",@"Light",@"Dark",@"Accent Color",@"Automatic checks",@"Check for Updates",@"Debug and diagnostics",@"Prefer GitHub Legacy",@"About vless-core",@"Credits",@"FAQ",@"Project on GitHub"};
    CGFloat widths[]={0,1,96,240,280,300,320,360,480,680,900};
    CGSize controls[]={{0,0},{20,20},{24,24},{51,31},{79,27},{100,44}};
    for (unsigned w=0;w<sizeof(widths)/sizeof(widths[0]);w++) {
        for (unsigned c=0;c<sizeof(controls)/sizeof(controls[0]);c++) {
            for (unsigned t=0;t<sizeof(titles)/sizeof(titles[0]);t++) {
                NSString *description=t%2 ? @"Keep renamed subscriptions after updates" : @"Lowest latency first within each subscription";
                VCSettingsRowLayout row=VCSettingsMeasureRow(widths[w],49,15,controls[c],titles[t],title,description,detail);
                CHECK("settings-layout/finite-height",isfinite(row.height) && row.height>=44);
                inside(row.icon,widths[w],row.height); inside(row.title,widths[w],row.height);
                inside(row.detail,widths[w],row.height); inside(row.accessory,widths[w],row.height);
                if (row.title.size.width>0) {
                    CHECK("settings-layout/keeps-24pt-icon",row.icon.size.width==24 && row.icon.size.height==24);
                    if (controls[c].width>0) CHECK("settings-layout/title-before-control",right(row.title)+7.99<=row.accessory.origin.x);
                    if (row.expanded) {
                        CHECK("settings-layout/description-below-header",row.detail.origin.y>=MAX(bottom(row.title),MAX(bottom(row.icon),bottom(row.accessory)))+3.99);
                        CHECK("settings-layout/full-description-width",fabs(right(row.detail)-(widths[w]-15))<0.01);
                    }
                }
            }
        }
    }
    VCSettingsRowLayout empty=VCSettingsMeasureRow(300,49,15,CGSizeMake(0,0),@"",title,@"",detail);
    CHECK("settings-layout/empty-content-safe",empty.height==44);
    VCSettingsRowLayout invalid=VCSettingsMeasureRow(NAN,49,15,CGSizeMake(79,27),@"Settings",title,@"Details",detail);
    CHECK("settings-layout/transient-invalid-width",invalid.height==44 && invalid.title.size.width==0);
    CHECK("settings-layout/source-unchanged",[titles[0] isEqual:@"Auto-update subscriptions"] && title.lineHeight==21 && detail.lineHeight==17);
    [pool drain]; FINISH("adaptive settings layout"); return 0;
}
