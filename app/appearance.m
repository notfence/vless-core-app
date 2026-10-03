#import "appearance.h"

void VCSetLabelMinimumScaleFactor(UILabel *label, CGFloat factor) {
    if ([label respondsToSelector:@selector(setMinimumScaleFactor:)]) {
        label.minimumScaleFactor = factor;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        label.minimumFontSize = label.font.pointSize * factor;
#pragma clang diagnostic pop
    }
}

CGFloat VCMainStatusBarInset(void) {
    if ([[UIDevice currentDevice].systemVersion integerValue] < 7 ||
        [UIApplication sharedApplication].statusBarHidden) {
        return 0.0f;
    }

    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    CGFloat inset = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame));
    return (inset > 0.0f && inset < 64.0f) ? inset : 0.0f;
}


UIColor *VCAppearanceAccentColorAtIndex(NSInteger index, BOOL dark) {
    switch (index) {
        case 1:
            return dark ? [UIColor colorWithRed:0.22f green:0.84f blue:0.74f alpha:1.0f]
                        : [UIColor colorWithRed:0.025f green:0.47f blue:0.42f alpha:1.0f];
        case 2:
            return dark ? [UIColor colorWithRed:0.36f green:0.84f blue:0.45f alpha:1.0f]
                        : [UIColor colorWithRed:0.08f green:0.50f blue:0.18f alpha:1.0f];
        case 3:
            return dark ? [UIColor colorWithRed:1.0f green:0.64f blue:0.24f alpha:1.0f]
                        : [UIColor colorWithRed:0.82f green:0.39f blue:0.03f alpha:1.0f];
        case 4:
            return dark ? [UIColor colorWithRed:1.0f green:0.38f blue:0.38f alpha:1.0f]
                        : [UIColor colorWithRed:0.78f green:0.12f blue:0.12f alpha:1.0f];
        case 5:
            return dark ? [UIColor colorWithRed:0.72f green:0.50f blue:1.0f alpha:1.0f]
                        : [UIColor colorWithRed:0.48f green:0.25f blue:0.74f alpha:1.0f];
        default:
            return dark ? [UIColor colorWithRed:0.28f green:0.62f blue:1.0f alpha:1.0f]
                        : [UIColor colorWithRed:0.10f green:0.44f blue:0.86f alpha:1.0f];
    }
}

UIColor *VCBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.065f alpha:1.0f]
                                : [UIColor colorWithWhite:0.97f alpha:1.0f];
}

UIColor *VCCellBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.13f alpha:1.0f]
                                : [UIColor whiteColor];
}

UIColor *VCPrimaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.92f alpha:1.0f]
                                : [UIColor colorWithWhite:0.08f alpha:1.0f];
}

UIColor *VCSecondaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.67f alpha:1.0f]
                                : [UIColor colorWithWhite:0.42f alpha:1.0f];
}

UIColor *VCSeparatorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                : [UIColor colorWithWhite:0.78f alpha:1.0f];
}

UIColor *VCSelectedCellColor(void) {
    UIColor *accent = VCAppearanceAccentColorAtIndex(VCAppearanceAccentIndex(), VCAppearanceIsDark());
    const CGFloat *components = CGColorGetComponents(accent.CGColor);
    CGFloat red = components[0];
    CGFloat green = components[1];
    CGFloat blue = components[2];
    if (VCAppearanceIsDark()) {
        return [UIColor colorWithRed:(0.06f + red * 0.24f)
                               green:(0.06f + green * 0.24f)
                                blue:(0.06f + blue * 0.24f)
                               alpha:1.0f];
    }
    return [UIColor colorWithRed:(0.80f + red * 0.20f)
                           green:(0.80f + green * 0.20f)
                            blue:(0.80f + blue * 0.20f)
                           alpha:1.0f];
}

UIColor *VCAccentColor(void) {
    return VCAppearanceAccentColorAtIndex(VCAppearanceAccentIndex(), VCAppearanceIsDark());
}

UIColor *VCDefaultAccentColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.28f green:0.62f blue:1.0f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.44f blue:0.86f alpha:1.0f];
}

UIColor *VCSuccessColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.32f green:0.82f blue:0.42f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.50f blue:0.15f alpha:1.0f];
}

UIColor *VCErrorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:1.0f green:0.38f blue:0.38f alpha:1.0f]
                                : [UIColor colorWithRed:0.78f green:0.12f blue:0.12f alpha:1.0f];
}

BOOL IsPadDevice(void) {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    }

    NSString *model = [[UIDevice currentDevice] model];
    if (model && [model rangeOfString:@"iPad" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return NO;
}

BOOL VCPreferGitHubLegacy(void) {
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

void VCOpenGitHubProject(void) {
    VCOpenURLWithFallback(kGitHubLegacyProjectURL, kProjectURL);
}

void VCOpenGitHubLatestRelease(NSString *fallbackURLString) {
    NSString *fallback = [fallbackURLString length] > 0 ? fallbackURLString : kUpdateReleasesURL;
    VCOpenURLWithFallback(kGitHubLegacyLatestReleaseURL, fallback);
}

UIInterfaceOrientation CurrentInterfaceOrientation(void) {
    UIInterfaceOrientation o = [[UIApplication sharedApplication] statusBarOrientation];
    if (o == UIInterfaceOrientationLandscapeLeft ||
        o == UIInterfaceOrientationLandscapeRight ||
        o == UIInterfaceOrientationPortraitUpsideDown ||
        o == UIInterfaceOrientationPortrait) {
        return o;
    }
    return UIInterfaceOrientationPortrait;
}

VCPingType VCSelectedPingType(void) {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsPingTypeKey];
    if (value < VCPingTypeProxyGET || value > VCPingTypeICMP) {
        return VCPingTypeProxyGET;
    }
    return (VCPingType)value;
}

NSString *VCPingTypeName(VCPingType type) {
    if (type == VCPingTypeTCP) return @"TCP";
    if (type == VCPingTypeICMP) return @"ICMP";
    return @"Proxy GET";
}

NSString *VCSelectedPingTypeText(void) {
    return [NSString stringWithFormat:@"Selected: %@", VCPingTypeName(VCSelectedPingType())];
}

NSString *VCSelectedXrayVersion(void) {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsXrayVersionKey];
    return VCXrayVersionIsValid(value) ? value : kDefaultXrayVersion;
}

BOOL VCXrayVersionSpoofEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsXrayVersionSpoofEnabledKey];
}

NSString *VCActiveXrayVersion(void) {
    return VCXrayVersionSpoofEnabled() ? VCSelectedXrayVersion() : nil;
}

NSString *VCSelectedXrayVersionText(void) {
    if (!VCXrayVersionSpoofEnabled()) return @"Disabled";
    return [NSString stringWithFormat:@"Enabled: %@", VCSelectedXrayVersion()];
}

UIImage *LoadBundledIconScaled(NSString *baseName, CGFloat size) {
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

UIImage *SolidImageWithColor(UIColor *color) {
    CGRect rect = CGRectMake(0, 0, 4, 4);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillRect(ctx, rect);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

UIImage *TintImageWithColor(UIImage *image, UIColor *color) {
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

UIImage *LoadBundledIconTinted(NSString *baseName, CGFloat size, UIColor *color) {
    UIImage *image = LoadBundledIconScaled(baseName, size);
    return image ? TintImageWithColor(image, color) : nil;
}

void VCAppearanceApplyHeaderView(UIView *view);

void VCAppearanceApplyTable(UITableView *tableView) {
    if (!tableView) return;

    tableView.backgroundColor = VCBackgroundColor();
    tableView.separatorColor = VCSeparatorColor();
    tableView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                     : UIScrollViewIndicatorStyleDefault;
    UIView *background = [[[UIView alloc] initWithFrame:tableView.bounds] autorelease];
    background.backgroundColor = VCBackgroundColor();
    tableView.backgroundView = background;
}

void VCAppearanceApplyCell(UITableViewCell *cell) {
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

void VCAppearanceApplyHeaderView(UIView *view) {
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

void VCAppearanceRefreshVisibleTableHeaders(UITableView *tableView) {
    if (!tableView || ![tableView respondsToSelector:@selector(headerViewForSection:)]) return;

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

void VCAppearanceScheduleVisibleTableHeadersRefresh(UITableView *tableView) {
    if (!tableView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        VCAppearanceRefreshVisibleTableHeaders(tableView);
    });
}

void VCAppearanceApplyNavigationBar(UINavigationBar *navigationBar) {
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

UIStatusBarStyle VCAppearancePreferredStatusBarStyle(void) {
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 13) {
        return [[UIApplication sharedApplication] statusBarStyle];
    }
    return VCAppearanceIsDark() ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

void VCAppearanceApplyStatusBar(void) {
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

UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active) {
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
    } else if (type == VCIconTypeGlobe) {
        CGRect globeRect = CGRectMake(size * 0.16f,
                                      size * 0.16f,
                                      size * 0.68f,
                                      size * 0.68f);
        CGContextStrokeEllipseInRect(ctx, globeRect);
        CGContextStrokeEllipseInRect(ctx, CGRectInset(globeRect, size * 0.22f, 0.0f));
        CGContextMoveToPoint(ctx, size * 0.19f, size * 0.39f);
        CGContextAddLineToPoint(ctx, size * 0.81f, size * 0.39f);
        CGContextMoveToPoint(ctx, size * 0.19f, size * 0.61f);
        CGContextAddLineToPoint(ctx, size * 0.81f, size * 0.61f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeSupport) {
        CGRect bubbleRect = CGRectMake(size * 0.14f,
                                       size * 0.17f,
                                       size * 0.72f,
                                       size * 0.55f);
        UIBezierPath *bubble = [UIBezierPath bezierPathWithRoundedRect:bubbleRect
                                                          cornerRadius:size * 0.12f];
        bubble.lineWidth = 2.0f;
        [bubble stroke];
        CGContextMoveToPoint(ctx, size * 0.35f, size * 0.70f);
        CGContextAddLineToPoint(ctx, size * 0.27f, size * 0.84f);
        CGContextAddLineToPoint(ctx, size * 0.49f, size * 0.72f);
        CGContextStrokePath(ctx);
        CGFloat dotRadius = MAX(1.0f, size * 0.035f);
        CGFloat dotY = size * 0.45f;
        for (int i = 0; i < 3; i++) {
            CGFloat dotX = size * (0.36f + 0.14f * i);
            CGContextFillEllipseInRect(ctx,
                                       CGRectMake(dotX - dotRadius,
                                                  dotY - dotRadius,
                                                  dotRadius * 2.0f,
                                                  dotRadius * 2.0f));
        }
    } else if (type == VCIconTypeDocument) {
        CGContextSetLineWidth(ctx, 1.25f);
        CGContextMoveToPoint(ctx, size * 0.22f, size * 0.12f);
        CGContextAddLineToPoint(ctx, size * 0.61f, size * 0.12f);
        CGContextAddLineToPoint(ctx, size * 0.80f, size * 0.31f);
        CGContextAddLineToPoint(ctx, size * 0.80f, size * 0.88f);
        CGContextAddLineToPoint(ctx, size * 0.22f, size * 0.88f);
        CGContextClosePath(ctx);
        CGContextMoveToPoint(ctx, size * 0.61f, size * 0.12f);
        CGContextAddLineToPoint(ctx, size * 0.61f, size * 0.31f);
        CGContextAddLineToPoint(ctx, size * 0.80f, size * 0.31f);
        CGContextMoveToPoint(ctx, size * 0.34f, size * 0.52f);
        CGContextAddLineToPoint(ctx, size * 0.68f, size * 0.52f);
        CGContextMoveToPoint(ctx, size * 0.34f, size * 0.67f);
        CGContextAddLineToPoint(ctx, size * 0.68f, size * 0.67f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeStorage) {
        CGContextSetLineWidth(ctx, 1.25f);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(size * 0.18f, size * 0.13f,
                                                     size * 0.64f, size * 0.22f));
        CGContextMoveToPoint(ctx, size * 0.18f, size * 0.24f);
        CGContextAddLineToPoint(ctx, size * 0.18f, size * 0.76f);
        CGContextMoveToPoint(ctx, size * 0.82f, size * 0.24f);
        CGContextAddLineToPoint(ctx, size * 0.82f, size * 0.76f);
        CGContextAddCurveToPoint(ctx, size * 0.82f, size * 0.91f,
                                 size * 0.18f, size * 0.91f,
                                 size * 0.18f, size * 0.76f);
        CGContextMoveToPoint(ctx, size * 0.18f, size * 0.49f);
        CGContextAddCurveToPoint(ctx, size * 0.34f, size * 0.67f,
                                 size * 0.66f, size * 0.67f,
                                 size * 0.82f, size * 0.49f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeCalendar) {
        CGContextSetLineWidth(ctx, 1.25f);
        CGContextStrokeRect(ctx, CGRectMake(size * 0.18f, size * 0.25f,
                                            size * 0.64f, size * 0.61f));
        CGContextMoveToPoint(ctx, size * 0.18f, size * 0.43f);
        CGContextAddLineToPoint(ctx, size * 0.82f, size * 0.43f);
        CGContextMoveToPoint(ctx, size * 0.34f, size * 0.14f);
        CGContextAddLineToPoint(ctx, size * 0.34f, size * 0.34f);
        CGContextMoveToPoint(ctx, size * 0.66f, size * 0.14f);
        CGContextAddLineToPoint(ctx, size * 0.66f, size * 0.34f);
        CGContextStrokePath(ctx);
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

UIView *VCCreateDisclosureAccessoryView(void) {
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 20.0f, 20.0f)] autorelease];
    UIImageView *imageView = [[[UIImageView alloc] initWithFrame:CGRectMake(2.0f, 2.0f, 16.0f, 16.0f)] autorelease];
    imageView.image = TintImageWithColor(MakeIconImage(VCIconTypeChevronRight, 16.0f, NO),
                                         VCSecondaryTextColor());
    [view addSubview:imageView];
    return view;
}

UIImage *VCAppearanceAccentSwatchImage(UIColor *color) {
    CGSize size = CGSizeMake(24.0f, 24.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGRect swatchRect = CGRectMake(3.0f, 3.0f, 18.0f, 18.0f);
    UIBezierPath *swatch = [UIBezierPath bezierPathWithRoundedRect:swatchRect cornerRadius:5.0f];
    [color setFill];
    [swatch fill];
    [[VCSeparatorColor() colorWithAlphaComponent:0.85f] setStroke];
    swatch.lineWidth = 1.0f;
    [swatch stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

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
