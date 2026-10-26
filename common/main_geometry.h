#ifndef VC_MAIN_GEOMETRY_H
#define VC_MAIN_GEOMETRY_H
#if defined(__APPLE__)
#include <CoreGraphics/CoreGraphics.h>
#else
typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return (CGRect){{x, y}, {w, h}}; }
#endif
typedef struct {
    CGRect button, state, selection, uptime, status, switcher, table, power, title;
} VCMainGeometry;
#define VC_PHONE_LAYOUT_STATE 1
typedef struct {
    CGFloat width, height, topInset, progress;
    int terminal, valid;
} VCPhoneLayoutState;
int VCPhoneLayoutStateMatches(const VCPhoneLayoutState *state, CGFloat width, CGFloat height, CGFloat topInset, CGFloat progress, int terminal);
extern const CGFloat kVCMainContentStartY;
extern const CGFloat kVCMainCompactContentStartY;
extern const CGFloat kVCMainSectionHeaderHeight;
CGFloat VCClampUnit(CGFloat value);
CGRect VCInterpolateRect(CGRect from, CGRect to, CGFloat progress);
VCMainGeometry VCPhoneGeometry(CGFloat width, CGFloat topInset, CGFloat progress);
VCMainGeometry VCPadGeometry(CGFloat width, CGFloat height, CGFloat topInset);
CGFloat VCSubscriptionDescriptionWidth(CGFloat cardWidth, int reordering);
CGFloat VCSubscriptionMeasuredCardHeight(CGFloat descriptionHeight);
CGFloat VCMetadataScale(CGFloat textWidth, CGFloat contentWidth, CGFloat fixedWidth);
void VCSubscriptionActionFrames(CGFloat metadataRight, CGRect *ping, CGRect *info);
#endif
