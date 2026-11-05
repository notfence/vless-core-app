#import "settings_icons.h"
#import "appearance.h"

static void VCSettingsDrawIcon(CGContextRef ctx, VCSettingsIconType icon) {
    switch (icon) {
        case VCSettingsIconAutoUpdate:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 20.0f, 8.0f);
            CGContextAddCurveToPoint(ctx, 18.91235f, 5.041569f, 16.276886f, 2.927923f, 13.152873f, 2.508593f);
            CGContextAddCurveToPoint(ctx, 10.02886f, 2.089262f, 6.929305f, 3.433107f, 5.1f, 6.0f);
            CGContextMoveToPoint(ctx, 4.0f, 16.0f);
            CGContextAddCurveToPoint(ctx, 5.08765f, 18.958431f, 7.723114f, 21.072077f, 10.847127f, 21.491407f);
            CGContextAddCurveToPoint(ctx, 13.97114f, 21.910738f, 17.070695f, 20.566893f, 18.9f, 18.0f);
            CGContextMoveToPoint(ctx, 20.0f, 4.0f);
            CGContextAddLineToPoint(ctx, 20.0f, 8.0f);
            CGContextAddLineToPoint(ctx, 17.0f, 8.0f);
            CGContextMoveToPoint(ctx, 4.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 4.0f, 16.0f);
            CGContextAddLineToPoint(ctx, 7.0f, 16.0f);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 9.5f, 9.0f);
            CGContextAddLineToPoint(ctx, 14.5f, 9.0f);
            CGContextMoveToPoint(ctx, 9.5f, 12.0f);
            CGContextAddLineToPoint(ctx, 14.5f, 12.0f);
            CGContextMoveToPoint(ctx, 9.5f, 15.0f);
            CGContextAddLineToPoint(ctx, 14.5f, 15.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconPreserveNames:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 3.0f, 4.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 4.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 13.0f);
            CGContextAddLineToPoint(ctx, 13.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 4.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(6.0f, 7.0f, 2.0f, 2.0f));
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconStealth:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 10.6f, 5.1f);
            CGContextAddCurveToPoint(ctx, 11.063748f, 5.033917f, 11.531567f, 5.000502f, 12.0f, 5.0f);
            CGContextAddCurveToPoint(ctx, 18.4f, 5.0f, 22.0f, 12.0f, 22.0f, 12.0f);
            CGContextAddCurveToPoint(ctx, 21.303308f, 13.258466f, 20.464487f, 14.432816f, 19.5f, 15.5f);
            CGContextMoveToPoint(ctx, 6.3f, 6.5f);
            CGContextAddCurveToPoint(ctx, 4.561278f, 8.07263f, 3.106648f, 9.933203f, 2.0f, 12.0f);
            CGContextAddCurveToPoint(ctx, 2.0f, 12.0f, 5.6f, 19.0f, 12.0f, 19.0f);
            CGContextAddCurveToPoint(ctx, 13.976517f, 18.979494f, 15.910992f, 18.426787f, 17.6f, 17.4f);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 9.9f, 9.9f);
            CGContextAddCurveToPoint(ctx, 9.004229f, 11.094361f, 9.123004f, 12.765644f, 10.17868f, 13.82132f);
            CGContextAddCurveToPoint(ctx, 11.234356f, 14.876996f, 12.905639f, 14.995771f, 14.1f, 14.1f);
            CGContextMoveToPoint(ctx, 3.0f, 3.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 21.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconSortPing:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 3.0f, 6.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 6.0f);
            CGContextMoveToPoint(ctx, 3.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 9.0f, 12.0f);
            CGContextMoveToPoint(ctx, 3.0f, 18.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 18.0f);
            CGContextMoveToPoint(ctx, 18.0f, 4.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 20.0f);
            CGContextMoveToPoint(ctx, 14.5f, 16.5f);
            CGContextAddLineToPoint(ctx, 18.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 21.5f, 16.5f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconRouting:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 7.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 11.5f, 12.0f);
            CGContextMoveToPoint(ctx, 11.5f, 5.0f);
            CGContextAddLineToPoint(ctx, 11.5f, 19.0f);
            CGContextMoveToPoint(ctx, 11.5f, 5.0f);
            CGContextAddLineToPoint(ctx, 16.5f, 5.0f);
            CGContextMoveToPoint(ctx, 11.5f, 19.0f);
            CGContextAddLineToPoint(ctx, 16.5f, 19.0f);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(2.0f, 9.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(16.5f, 2.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(16.5f, 16.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconPing:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 2.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 9.0f, 4.0f);
            CGContextAddLineToPoint(ctx, 14.5f, 20.0f);
            CGContextAddLineToPoint(ctx, 17.5f, 12.0f);
            CGContextAddLineToPoint(ctx, 22.0f, 12.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconXrayVersion:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 6.0f, 5.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 5.0f);
            CGContextAddCurveToPoint(ctx, 19.656854f, 5.0f, 21.0f, 6.343146f, 21.0f, 8.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 16.0f);
            CGContextAddCurveToPoint(ctx, 21.0f, 17.656854f, 19.656854f, 19.0f, 18.0f, 19.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 19.0f);
            CGContextAddCurveToPoint(ctx, 4.343146f, 19.0f, 3.0f, 17.656854f, 3.0f, 16.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 8.0f);
            CGContextAddCurveToPoint(ctx, 3.0f, 6.343146f, 4.343146f, 5.0f, 6.0f, 5.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 6.5f, 10.0f);
            CGContextAddLineToPoint(ctx, 9.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 11.5f, 10.0f);
            CGContextMoveToPoint(ctx, 14.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 16.0f, 9.0f);
            CGContextAddLineToPoint(ctx, 16.0f, 15.0f);
            CGContextMoveToPoint(ctx, 14.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 15.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconXmux:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 3.0f, 5.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 5.0f);
            CGContextAddCurveToPoint(ctx, 10.0f, 5.0f, 10.0f, 12.0f, 14.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 12.0f);
            CGContextMoveToPoint(ctx, 3.0f, 19.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 19.0f);
            CGContextAddCurveToPoint(ctx, 10.0f, 19.0f, 10.0f, 12.0f, 14.0f, 12.0f);
            CGContextMoveToPoint(ctx, 3.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 12.0f);
            CGContextMoveToPoint(ctx, 18.0f, 9.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 15.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconLight:
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(8.0f, 8.0f, 8.0f, 8.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 12.0f, 2.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 4.0f);
            CGContextMoveToPoint(ctx, 12.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 22.0f);
            CGContextMoveToPoint(ctx, 2.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 4.0f, 12.0f);
            CGContextMoveToPoint(ctx, 20.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 22.0f, 12.0f);
            CGContextMoveToPoint(ctx, 4.9f, 4.9f);
            CGContextAddLineToPoint(ctx, 6.3f, 6.3f);
            CGContextMoveToPoint(ctx, 17.7f, 17.7f);
            CGContextAddLineToPoint(ctx, 19.1f, 19.1f);
            CGContextMoveToPoint(ctx, 4.9f, 19.1f);
            CGContextAddLineToPoint(ctx, 6.3f, 17.7f);
            CGContextMoveToPoint(ctx, 17.7f, 6.3f);
            CGContextAddLineToPoint(ctx, 19.1f, 4.9f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconDark:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 20.8f, 13.4f);
            CGContextAddCurveToPoint(ctx, 20.077716f, 17.892174f, 16.083576f, 21.116247f, 11.540129f, 20.874576f);
            CGContextAddCurveToPoint(ctx, 6.996681f, 20.632906f, 3.367094f, 17.003319f, 3.125424f, 12.459871f);
            CGContextAddCurveToPoint(ctx, 2.883753f, 7.916424f, 6.107826f, 3.922284f, 10.6f, 3.2f);
            CGContextAddCurveToPoint(ctx, 7.783348f, 6.016652f, 7.783348f, 10.583348f, 10.6f, 13.4f);
            CGContextAddCurveToPoint(ctx, 13.416652f, 16.216652f, 17.983348f, 16.216652f, 20.8f, 13.4f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconAccent:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 12.0f, 3.0f);
            CGContextAddCurveToPoint(ctx, 7.029437f, 3.0f, 3.0f, 7.029437f, 3.0f, 12.0f);
            CGContextAddCurveToPoint(ctx, 3.0f, 16.970563f, 7.029437f, 21.0f, 12.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 13.0f, 21.0f);
            CGContextAddCurveToPoint(ctx, 14.013183f, 20.985942f, 14.917675f, 20.361699f, 15.290216f, 19.419388f);
            CGContextAddCurveToPoint(ctx, 15.662758f, 18.477077f, 15.429659f, 17.403089f, 14.7f, 16.7f);
            CGContextAddCurveToPoint(ctx, 14.235003f, 16.270835f, 14.089335f, 15.596026f, 14.335889f, 15.013261f);
            CGContextAddCurveToPoint(ctx, 14.582443f, 14.430496f, 15.168186f, 14.06513f, 15.8f, 14.1f);
            CGContextAddLineToPoint(ctx, 17.5f, 14.1f);
            CGContextAddCurveToPoint(ctx, 19.432997f, 14.1f, 21.0f, 12.532997f, 21.0f, 10.6f);
            CGContextAddCurveToPoint(ctx, 20.304713f, 6.182557f, 16.471495f, 2.945617f, 12.0f, 3.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 7.0f, 11.5f);
            CGContextAddLineToPoint(ctx, 7.01f, 11.5f);
            CGContextMoveToPoint(ctx, 9.0f, 7.5f);
            CGContextAddLineToPoint(ctx, 9.01f, 7.5f);
            CGContextMoveToPoint(ctx, 13.5f, 6.8f);
            CGContextAddLineToPoint(ctx, 13.51f, 6.8f);
            CGContextMoveToPoint(ctx, 17.0f, 9.0f);
            CGContextAddLineToPoint(ctx, 17.01f, 9.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconAutomaticChecks:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 21.0f, 11.5f);
            CGContextAddCurveToPoint(ctx, 20.727563f, 6.603812f, 16.585583f, 2.826865f, 11.685095f, 3.006019f);
            CGContextAddCurveToPoint(ctx, 6.784606f, 3.185173f, 2.929472f, 7.254481f, 3.015278f, 12.157492f);
            CGContextAddCurveToPoint(ctx, 3.101084f, 17.060503f, 7.096244f, 20.992426f, 12.0f, 21.0f);
            CGContextMoveToPoint(ctx, 12.0f, 6.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 12.0f);
            CGContextAddLineToPoint(ctx, 15.0f, 14.0f);
            CGContextMoveToPoint(ctx, 15.0f, 19.0f);
            CGContextAddLineToPoint(ctx, 17.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 22.0f, 16.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconCheckUpdates:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 12.0f, 3.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 15.0f);
            CGContextMoveToPoint(ctx, 7.0f, 10.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 17.0f, 10.0f);
            CGContextMoveToPoint(ctx, 4.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 4.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 20.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 20.0f, 15.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconDebug:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 12.0f, 8.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 8.0f);
            CGContextAddCurveToPoint(ctx, 14.761424f, 8.0f, 17.0f, 10.238576f, 17.0f, 13.0f);
            CGContextAddLineToPoint(ctx, 17.0f, 15.0f);
            CGContextAddCurveToPoint(ctx, 17.0f, 17.761424f, 14.761424f, 20.0f, 12.0f, 20.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 20.0f);
            CGContextAddCurveToPoint(ctx, 9.238576f, 20.0f, 7.0f, 17.761424f, 7.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 7.0f, 13.0f);
            CGContextAddCurveToPoint(ctx, 7.0f, 10.238576f, 9.238576f, 8.0f, 12.0f, 8.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 9.0f, 8.0f);
            CGContextAddLineToPoint(ctx, 9.0f, 7.0f);
            CGContextAddCurveToPoint(ctx, 9.0f, 5.343146f, 10.343146f, 4.0f, 12.0f, 4.0f);
            CGContextAddCurveToPoint(ctx, 13.656854f, 4.0f, 15.0f, 5.343146f, 15.0f, 7.0f);
            CGContextAddLineToPoint(ctx, 15.0f, 8.0f);
            CGContextMoveToPoint(ctx, 8.0f, 3.0f);
            CGContextAddLineToPoint(ctx, 10.0f, 5.0f);
            CGContextMoveToPoint(ctx, 14.0f, 5.0f);
            CGContextAddLineToPoint(ctx, 16.0f, 3.0f);
            CGContextMoveToPoint(ctx, 7.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 11.0f);
            CGContextMoveToPoint(ctx, 7.0f, 16.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 16.0f);
            CGContextMoveToPoint(ctx, 7.7f, 19.0f);
            CGContextAddLineToPoint(ctx, 4.7f, 21.0f);
            CGContextMoveToPoint(ctx, 17.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 11.0f);
            CGContextMoveToPoint(ctx, 17.0f, 16.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 16.0f);
            CGContextMoveToPoint(ctx, 16.3f, 19.0f);
            CGContextAddLineToPoint(ctx, 19.3f, 21.0f);
            CGContextMoveToPoint(ctx, 12.0f, 10.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 20.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconGitHubLegacy:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 6.0f, 3.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 3.0f);
            CGContextAddCurveToPoint(ctx, 19.656854f, 3.0f, 21.0f, 4.343146f, 21.0f, 6.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 18.0f);
            CGContextAddCurveToPoint(ctx, 21.0f, 19.656854f, 19.656854f, 21.0f, 18.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 21.0f);
            CGContextAddCurveToPoint(ctx, 4.343146f, 21.0f, 3.0f, 19.656854f, 3.0f, 18.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 6.0f);
            CGContextAddCurveToPoint(ctx, 3.0f, 4.343146f, 4.343146f, 3.0f, 6.0f, 3.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 7.5f, 9.0f);
            CGContextAddLineToPoint(ctx, 7.5f, 15.0f);
            CGContextMoveToPoint(ctx, 7.5f, 13.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 13.0f);
            CGContextAddCurveToPoint(ctx, 14.5f, 13.0f, 16.5f, 12.0f, 16.5f, 10.0f);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(6.0f, 6.0f, 3.0f, 3.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(6.0f, 15.0f, 3.0f, 3.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(15.0f, 7.0f, 3.0f, 3.0f));
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconAbout:
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(3.0f, 3.0f, 18.0f, 18.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 12.0f, 7.0f);
            CGContextAddLineToPoint(ctx, 12.01f, 7.0f);
            CGContextMoveToPoint(ctx, 10.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 11.0f);
            CGContextAddLineToPoint(ctx, 12.0f, 17.0f);
            CGContextMoveToPoint(ctx, 10.0f, 17.0f);
            CGContextAddLineToPoint(ctx, 14.0f, 17.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconCredits:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 20.4f, 5.6f);
            CGContextAddCurveToPoint(ctx, 19.461167f, 4.653437f, 18.183188f, 4.121008f, 16.85f, 4.121008f);
            CGContextAddCurveToPoint(ctx, 15.516812f, 4.121008f, 14.238833f, 4.653437f, 13.3f, 5.6f);
            CGContextAddLineToPoint(ctx, 12.0f, 6.9f);
            CGContextAddLineToPoint(ctx, 10.7f, 5.6f);
            CGContextAddCurveToPoint(ctx, 8.739389f, 3.639389f, 5.560611f, 3.639389f, 3.6f, 5.6f);
            CGContextAddCurveToPoint(ctx, 1.639389f, 7.560611f, 1.639389f, 10.739389f, 3.6f, 12.7f);
            CGContextAddLineToPoint(ctx, 12.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 20.4f, 12.7f);
            CGContextAddCurveToPoint(ctx, 21.346563f, 11.761167f, 21.878992f, 10.483188f, 21.878992f, 9.15f);
            CGContextAddCurveToPoint(ctx, 21.878992f, 7.816812f, 21.346563f, 6.538833f, 20.4f, 5.6f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconFAQ:
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 7.0f, 18.0f);
            CGContextAddLineToPoint(ctx, 18.0f, 18.0f);
            CGContextAddCurveToPoint(ctx, 19.656854f, 18.0f, 21.0f, 16.656854f, 21.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 21.0f, 6.0f);
            CGContextAddCurveToPoint(ctx, 21.0f, 4.343146f, 19.656854f, 3.0f, 18.0f, 3.0f);
            CGContextAddLineToPoint(ctx, 6.0f, 3.0f);
            CGContextAddCurveToPoint(ctx, 4.343146f, 3.0f, 3.0f, 4.343146f, 3.0f, 6.0f);
            CGContextAddLineToPoint(ctx, 3.0f, 21.0f);
            CGContextAddLineToPoint(ctx, 7.0f, 18.0f);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 9.5f, 8.0f);
            CGContextAddCurveToPoint(ctx, 9.503334f, 6.78041f, 10.386185f, 5.741212f, 11.589202f, 5.540814f);
            CGContextAddCurveToPoint(ctx, 12.79222f, 5.340416f, 13.964268f, 6.03731f, 14.362769f, 7.189962f);
            CGContextAddCurveToPoint(ctx, 14.76127f, 8.342614f, 14.269909f, 9.61459f, 13.2f, 10.2f);
            CGContextAddCurveToPoint(ctx, 12.4f, 10.7f, 12.0f, 11.0f, 12.0f, 12.0f);
            CGContextMoveToPoint(ctx, 12.0f, 15.0f);
            CGContextAddLineToPoint(ctx, 12.01f, 15.0f);
            CGContextStrokePath(ctx);
            break;
        case VCSettingsIconGitHub:
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(3.5f, 2.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(3.5f, 16.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(15.5f, 4.5f, 5.0f, 5.0f));
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 6.0f, 7.5f);
            CGContextAddLineToPoint(ctx, 6.0f, 16.5f);
            CGContextMoveToPoint(ctx, 6.0f, 14.0f);
            CGContextAddLineToPoint(ctx, 11.0f, 14.0f);
            CGContextAddCurveToPoint(ctx, 15.0f, 14.0f, 18.0f, 12.0f, 18.0f, 9.5f);
            CGContextStrokePath(ctx);
            break;
        default:
            break;
    }
}

VCSettingsIconType VCSettingsIconForRow(NSInteger section, NSInteger row) {
    static const NSInteger counts[] = {4, 4, 3, 2, 1, 1, 4};
    static const VCSettingsIconType icons[][4] = {
        {VCSettingsIconAutoUpdate, VCSettingsIconPreserveNames, VCSettingsIconStealth, VCSettingsIconSortPing},
        {VCSettingsIconRouting, VCSettingsIconPing, VCSettingsIconXrayVersion, VCSettingsIconXmux},
        {VCSettingsIconLight, VCSettingsIconDark, VCSettingsIconAccent},
        {VCSettingsIconAutomaticChecks, VCSettingsIconCheckUpdates},
        {VCSettingsIconDebug},
        {VCSettingsIconGitHubLegacy},
        {VCSettingsIconAbout, VCSettingsIconCredits, VCSettingsIconFAQ, VCSettingsIconGitHub}
    };
    if (section < 0 || section >= 7 || row < 0 || row >= counts[section]) return VCSettingsIconNone;
    return icons[section][row];
}

UIImage *VCSettingsIconImage(VCSettingsIconType icon) {
    if (icon < 0 || icon >= VCSettingsIconCount) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24.0f, 24.0f), NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }
    CGContextSetStrokeColorWithColor(ctx, VCAccentColor().CGColor);
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    VCSettingsDrawIcon(ctx, icon);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
