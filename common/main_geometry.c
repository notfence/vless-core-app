#include "main_geometry.h"
#include <math.h>

int VCPhoneLayoutStateMatches(const VCPhoneLayoutState *state, CGFloat width, CGFloat height, CGFloat topInset, CGFloat progress, int terminal) {
    return state && state->valid && state->width == width && state->height == height &&
        state->topInset == topInset && state->progress == progress && state->terminal == terminal;
}

const CGFloat kVCMainContentStartY = 266.0f;
const CGFloat kVCMainCompactContentStartY = 138.0f;
const CGFloat kVCMainSectionHeaderHeight = 48.0f;

CGFloat VCClampUnit(CGFloat value) {
    if (value < 0.0f) return 0.0f;
    if (value > 1.0f) return 1.0f;
    return value;
}

CGRect VCInterpolateRect(CGRect from, CGRect to, CGFloat progress) {
    CGFloat p = VCClampUnit(progress);
    return CGRectMake(from.origin.x + (to.origin.x - from.origin.x) * p,
                      from.origin.y + (to.origin.y - from.origin.y) * p,
                      from.size.width + (to.size.width - from.size.width) * p,
                      from.size.height + (to.size.height - from.size.height) * p);
}

VCMainGeometry VCPhoneGeometry(CGFloat width, CGFloat topInset, CGFloat progress) {
    VCMainGeometry g;
    g.button = VCInterpolateRect(CGRectMake((width - 112.0f) * 0.5f, topInset + 54.0f, 112.0f, 112.0f), CGRectMake(12.0f, topInset + 56.0f, 126.0f, 48.0f), progress);
    g.state = VCInterpolateRect(CGRectMake(16.0f, topInset + 174.0f, width - 32.0f, 19.0f), CGRectMake(150.0f, topInset + 50.0f, width - 162.0f, 17.0f), progress);
    g.selection = VCInterpolateRect(CGRectMake(16.0f, topInset + 194.0f, width - 32.0f, 18.0f), CGRectMake(150.0f, topInset + 67.0f, width - 162.0f, 17.0f), progress);
    g.uptime = VCInterpolateRect(CGRectMake(16.0f, topInset + 214.0f, width - 32.0f, 18.0f), CGRectMake(150.0f, topInset + 84.0f, width - 162.0f, 17.0f), progress);
    g.status = VCInterpolateRect(CGRectMake(16.0f, topInset + 237.0f, width - 32.0f, 30.0f), CGRectMake(16.0f, topInset + 113.0f, width - 32.0f, 28.0f), progress);
    g.switcher = VCInterpolateRect(CGRectMake(10.0f, topInset + kVCMainContentStartY, width - 20.0f, kVCMainSectionHeaderHeight), CGRectMake(10.0f, topInset + kVCMainCompactContentStartY, width - 20.0f, kVCMainSectionHeaderHeight), progress);
    g.power = VCInterpolateRect(CGRectMake(40.5f, 26.0f, 31.0f, 31.0f), CGRectMake(11.0f, 14.0f, 20.0f, 20.0f), progress);
    g.title = VCInterpolateRect(CGRectMake(10.0f, 61.0f, 92.0f, 24.0f), CGRectMake(35.0f, 0.0f, 86.0f, 48.0f), progress);
    g.table = CGRectMake(0, 0, 0, 0);
    return g;
}

VCMainGeometry VCPadGeometry(CGFloat width, CGFloat height, CGFloat topInset) {
    VCMainGeometry g = VCPhoneGeometry(width, topInset, 0);
    g.button.origin.x = floorf((width - 112.0f) * 0.5f);
    CGFloat summaryWidth = fmin(width - 32.0f, 360.0f);
    CGFloat summaryX = floorf((width - summaryWidth) * 0.5f);
    g.state = CGRectMake(summaryX, topInset + 174.0f, summaryWidth, 19.0f);
    g.selection = CGRectMake(summaryX, topInset + 194.0f, summaryWidth, 18.0f);
    g.uptime = CGRectMake(summaryX, topInset + 214.0f, summaryWidth, 18.0f);
    CGFloat listY = topInset + kVCMainContentStartY + kVCMainSectionHeaderHeight;
    g.table = CGRectMake(0.0f, listY, width, fmax(120.0f, height - listY));
    return g;
}

CGFloat VCSubscriptionDescriptionWidth(CGFloat cardWidth, int reordering) {
    CGFloat rightInset = reordering ? 50.0f : 14.0f;
    return fmax(80.0f, cardWidth - 14.0f - rightInset);
}

CGFloat VCSubscriptionMeasuredCardHeight(CGFloat descriptionHeight) {
    CGFloat height = 52.0f;
    if (descriptionHeight > 0.0f) height += descriptionHeight + 5.0f;
    return ceilf(height + 32.0f);
}

CGFloat VCMetadataScale(CGFloat textWidth, CGFloat contentWidth, CGFloat fixedWidth) {
    CGFloat availableTextWidth = fmax(1.0f, contentWidth - fixedWidth - 5.0f);
    return textWidth > availableTextWidth ? availableTextWidth / textWidth * 0.98f : 1.0f;
}

void VCSubscriptionActionFrames(CGFloat metadataRight, CGRect *ping, CGRect *info) {
    *ping = CGRectMake(metadataRight - 90.0f, 6.0f, 30.0f, 30.0f);
    *info = CGRectMake(metadataRight - 59.0f, 5.0f, 30.0f, 30.0f);
}
