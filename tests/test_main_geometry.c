#include "../common/main_geometry.h"
#include "check.h"
#include <math.h>
static int near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.0001; }
int main(void) {
    const CGFloat widths[] = {320, 375, 414, 768, 1024};
    for (unsigned w = 0; w < sizeof(widths) / sizeof(widths[0]); w++) {
        CGFloat width = widths[w];
        for (unsigned i = 0; i <= 100; i++) {
            CGFloat p = i / 100.0;
            VCMainGeometry g = VCPhoneGeometry(width, 20, p);
            CHECK("layout/button-inside-screen", g.button.origin.x >= 0 && g.button.origin.x + g.button.size.width <= width);
            CHECK("layout/icon-inside-button", g.power.origin.x >= 0 && g.power.origin.x + g.power.size.width <= g.button.size.width && g.power.origin.y + g.power.size.height <= g.button.size.height);
            CHECK("layout/title-inside-button", g.title.origin.x >= 0 && g.title.origin.x + g.title.size.width <= g.button.size.width);
            CHECK("layout/full-width-switcher", near(g.switcher.size.width, width - 20) && near(g.switcher.size.height, 48));
            CHECK("layout/positive-summary-width", g.state.size.width > 0 && g.selection.size.width > 0 && g.uptime.size.width > 0);
        }
        VCMainGeometry normal = VCPhoneGeometry(width, 20, 0), compact = VCPhoneGeometry(width, 20, 1);
        CHECK("layout/normal-button-unchanged", near(normal.button.size.width, 112) && near(normal.button.origin.y, 74));
        CHECK("layout/compact-button-unchanged", near(compact.button.size.width, 126) && near(compact.button.size.height, 48) && near(compact.state.origin.x, 150));
        CHECK("layout/compact-icon-title-gap", compact.power.origin.x + compact.power.size.width <= compact.title.origin.x);
        CHECK("layout/normal-icon-title-gap", normal.power.origin.y + normal.power.size.height <= normal.title.origin.y);
        CGRect ping, info; VCSubscriptionActionFrames(width - 14, &ping, &info);
        CHECK("layout/subscription-action-size", near(ping.size.width, 30) && near(info.size.width, 30));
        CHECK("layout/subscription-actions-do-not-overlap", ping.origin.x + ping.size.width <= info.origin.x);
        CHECK("layout/subscription-actions-inside", ping.origin.x >= 0 && info.origin.x + info.size.width <= width - 14);
    }
    for (unsigned orientation = 0; orientation < 2; orientation++) {
        CGFloat width = orientation ? 1024 : 768, height = orientation ? 768 : 1024;
        VCMainGeometry pad = VCPadGeometry(width, height, 20);
        CHECK("layout/ipad-button-centered", near(pad.button.origin.x + pad.button.size.width / 2, width / 2));
        CHECK("layout/ipad-summary-centered", near(pad.state.origin.x + pad.state.size.width / 2, width / 2));
        CHECK("layout/ipad-summary-visible", pad.state.size.height > 0 && pad.selection.size.height > 0 && pad.uptime.size.height > 0);
        CHECK("layout/ipad-table-fills-bottom", near(pad.table.origin.y + pad.table.size.height, height));
    }
    CHECK("layout/collapsed-card-height", near(VCSubscriptionMeasuredCardHeight(0), 84));
    CHECK("layout/expanded-description-height", near(VCSubscriptionMeasuredCardHeight(40), 129));
    CHECK("layout/reorder-description-width", near(VCSubscriptionDescriptionWidth(320, 1), 256));
    CHECK("layout/metadata-fits-without-ellipsis", VCMetadataScale(500, 292, 77) * 500 + 77 < 292);
    CHECK("layout/short-metadata-not-enlarged", near(VCMetadataScale(30, 292, 77), 1));
    CHECK("layout/interpolation-clamped", near(VCPhoneGeometry(320, 0, -1).button.size.width, 112) && near(VCPhoneGeometry(320, 0, 2).button.size.width, 126));
    FINISH("main geometry"); return 0;
}
