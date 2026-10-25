#import <Foundation/Foundation.h>
#include "check.h"

typedef NSString UIImage;
typedef enum { VCIconTypeWifi, VCIconTypeStop, VCIconTypeDocument, VCIconTypeStorage,
               VCIconTypeCalendar, VCIconTypeGlobe, VCIconTypeSupport } VCIconType;
enum { UIControlStateNormal, UIControlStateHighlighted };
static BOOL dark;
static NSInteger accent;
static unsigned renders, failAt;
static BOOL VCAppearanceIsDark(void) { return dark; }
static NSInteger VCAppearanceAccentIndex(void) { return accent; }
static NSString *VCPrimaryTextColor(void) { return dark ? @"primary-dark" : @"primary-light"; }
static NSString *VCSecondaryTextColor(void) { return dark ? @"secondary-dark" : @"secondary-light"; }
static UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active) {
    if (++renders == failAt) return nil;
    return [NSString stringWithFormat:@"%d/%.0f/%d/%d/%ld", type, (double)size, active, dark, (long)accent];
}
static UIImage *LoadBundledIconTinted(NSString *name, CGFloat size, NSString *color) {
    if (++renders == failAt) return nil;
    return [NSString stringWithFormat:@"%@/%.0f/%@", name, (double)size, color];
}
@interface VCImageSlot : NSObject {
    UIImage *_image;
}
@property(retain) UIImage *image;
@end
@implementation VCImageSlot
@synthesize image = _image;
- (void)dealloc { [_image release]; [super dealloc]; }
@end

@interface VCImageButton : NSObject {
    NSMutableDictionary *_images;
}
- (void)setImage:(UIImage *)image forState:(NSUInteger)state;
- (UIImage *)imageForState:(NSUInteger)state;
@end
@implementation VCImageButton
- (id)init { if ((self = [super init])) _images = [[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc { [_images release]; [super dealloc]; }
- (void)setImage:(UIImage *)image forState:(NSUInteger)state {
    NSNumber *key = [NSNumber numberWithUnsignedInteger:state];
    if (image) [_images setObject:image forKey:key]; else [_images removeObjectForKey:key];
}
- (UIImage *)imageForState:(NSUInteger)state {
    return [_images objectForKey:[NSNumber numberWithUnsignedInteger:state]];
}
@end

@interface VCSubscriptionHeaderCell : NSObject {
@public
    VCImageSlot *_metadataIcons[3];
    VCImageButton *_infoButton, *_pingButton, *_webPageButton, *_supportButton;
    BOOL _pingLoading, _headerImagesValid, _headerImagesDark, _headerPingImageLoading;
    NSInteger _headerImagesAccent;
}
- (void)refreshHeaderImages;
@end
@implementation VCSubscriptionHeaderCell
- (id)init {
    if ((self = [super init])) {
        for (unsigned i = 0; i < 3; i++) _metadataIcons[i] = [[VCImageSlot alloc] init];
        _infoButton = [[VCImageButton alloc] init]; _pingButton = [[VCImageButton alloc] init];
        _webPageButton = [[VCImageButton alloc] init]; _supportButton = [[VCImageButton alloc] init];
    }
    return self;
}
- (void)dealloc {
    for (unsigned i = 0; i < 3; i++) [_metadataIcons[i] release];
    [_infoButton release]; [_pingButton release]; [_webPageButton release]; [_supportButton release];
    [super dealloc];
}
#include "main_header_images.inc"
@end

static void checkImages(VCSubscriptionHeaderCell *cell) {
    VCIconType types[] = {VCIconTypeDocument, VCIconTypeStorage, VCIconTypeCalendar};
    for (unsigned i = 0; i < 3; i++)
        CHECK("images/metadata-color-and-size", [cell->_metadataIcons[i].image isEqual:MakeIconImage(types[i], 13, YES)]);
    CHECK("images/info-color-and-size", [[cell->_infoButton imageForState:UIControlStateNormal]
        isEqual:LoadBundledIconTinted(@"info", 21, VCSecondaryTextColor())]);
    CHECK("images/ping-state-and-color", [[cell->_pingButton imageForState:UIControlStateNormal]
        isEqual:(cell->_pingLoading ? MakeIconImage(VCIconTypeStop, 20, NO)
            : LoadBundledIconTinted(@"icon-ping", 20, VCPrimaryTextColor()))]);
    for (unsigned state = 0; state < 2; state++) {
        CHECK("images/web-colors", [[cell->_webPageButton imageForState:state]
            isEqual:MakeIconImage(VCIconTypeGlobe, 17, state == UIControlStateNormal)]);
        CHECK("images/support-colors", [[cell->_supportButton imageForState:state]
            isEqual:MakeIconImage(VCIconTypeSupport, 17, state == UIControlStateNormal)]);
    }
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VCSubscriptionHeaderCell *cell = [[VCSubscriptionHeaderCell alloc] init];
    CHECK("images/reuse-implemented", [cell respondsToSelector:@selector(refreshHeaderImages)]);
    [cell refreshHeaderImages];
    CHECK("images/initial-nine-images", renders == 9 && cell->_headerImagesValid);
    checkImages(cell);
    unsigned before = renders;
    for (unsigned i = 0; i < 1000; i++) [cell refreshHeaderImages];
    CHECK("images/unchanged-cell-no-rasterization", renders == before);
    for (unsigned theme = 0; theme < 2; theme++) {
        dark = !dark;
        before = renders; [cell refreshHeaderImages];
        CHECK("images/theme-rebuilds-nine", renders == before + 9);
        checkImages(cell);
        for (accent = 1; accent <= 5; accent++) {
            before = renders; [cell refreshHeaderImages];
            CHECK("images/accent-rebuilds-nine", renders == before + 9);
            checkImages(cell);
            before = renders; [cell refreshHeaderImages];
            CHECK("images/theme-and-accent-repeat-reuses", renders == before);
            for (unsigned ping = 0; ping < 2; ping++) {
                cell->_pingLoading = !cell->_pingLoading;
                before = renders; [cell refreshHeaderImages];
                CHECK("images/ping-only-rebuilds-one", renders == before + 1);
                checkImages(cell);
            }
        }
    }
    cell->_headerImagesValid = NO;
    failAt = renders + 1;
    [cell refreshHeaderImages];
    CHECK("images/failed-render-not-cached-as-complete", !cell->_headerImagesValid);
    failAt = 0; [cell refreshHeaderImages];
    CHECK("images/failed-render-retried", cell->_headerImagesValid);
    checkImages(cell);
    cell->_pingLoading = NO; cell->_headerImagesValid = NO;
    failAt = renders + 9; [cell refreshHeaderImages];
    CHECK("images/ping-resource-fallback", [[cell->_pingButton imageForState:UIControlStateNormal]
        isEqual:MakeIconImage(VCIconTypeWifi, 18, NO)]);
    failAt = 0;
    VCSubscriptionHeaderCell *other = [[VCSubscriptionHeaderCell alloc] init];
    before = renders; [other refreshHeaderImages];
    CHECK("images/new-cell-independent", renders == before + 9 && other->_headerImagesValid);
    [other release]; [cell release]; [pool drain];
    FINISH("main image invalidation"); return 0;
}
