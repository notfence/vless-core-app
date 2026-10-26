#import "main_cells.h"

@implementation VCMainListCellBackgroundView

- (void)ensureHeaderCardView {
    if (_headerCardView) return;

    _headerCardView = [[UIView alloc] initWithFrame:CGRectInset(self.bounds, 6.0f, 4.0f)];
    _headerCardView.userInteractionEnabled = NO;
    _headerCardView.layer.cornerRadius = 9.0f;
    _headerCardView.layer.masksToBounds = YES;
    _headerCardView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_headerCardView];

    _headerStripeView = [[UIView alloc] initWithFrame:CGRectZero];
    _headerStripeView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [_headerCardView addSubview:_headerStripeView];

    UIBezierPath *divider = [UIBezierPath bezierPath];
    [divider moveToPoint:CGPointMake(0.5f, 0.0f)];
    [divider addLineToPoint:CGPointMake(0.5f, 24.5f)];
    [divider addQuadCurveToPoint:CGPointMake(5.5f, 29.5f)
                   controlPoint:CGPointMake(0.5f, 29.5f)];
    [divider addLineToPoint:CGPointMake(24.5f, 29.5f)];
    [divider addQuadCurveToPoint:CGPointMake(29.5f, 24.5f)
                   controlPoint:CGPointMake(29.5f, 29.5f)];
    _headerTabLayer = [[CAShapeLayer alloc] init];
    _headerTabLayer.path = divider.CGPath;
    _headerTabLayer.fillColor = [UIColor clearColor].CGColor;
    [_headerCardView.layer addSublayer:_headerTabLayer];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_headerTabLayer release];
    [_headerStripeView release];
    [_headerCardView release];
    [super dealloc];
}

- (void)configureKind:(VCMainListCellKind)kind
             expanded:(BOOL)expanded
            firstItem:(BOOL)firstItem
             lastItem:(BOOL)lastItem
                active:(BOOL)active
        showsHeaderTab:(BOOL)showsHeaderTab
        selectedStyle:(BOOL)selectedStyle {
    _kind = kind;
    _expanded = expanded;
    _firstItem = firstItem;
    _lastItem = lastItem;
    _active = active;
    _selectedStyle = selectedStyle;
    _showsHeaderTab = showsHeaderTab;
    if (_kind == VCMainListCellKindSubscriptionHeader) {
        [self ensureHeaderCardView];
        _headerCardView.hidden = NO;
        _headerCardView.backgroundColor = (_selectedStyle || _active)
            ? VCSelectedCellColor() : VCCellBackgroundColor();
        UIColor *border = _active
            ? [VCAccentColor() colorWithAlphaComponent:0.82f]
            : (_expanded ? [VCAccentColor() colorWithAlphaComponent:0.38f]
                         : [VCSeparatorColor() colorWithAlphaComponent:0.82f]);
        _headerCardView.layer.borderColor = border.CGColor;
        _headerCardView.layer.borderWidth = _active ? 1.25f : 0.75f;
        _headerStripeView.backgroundColor = VCAccentColor();
        _headerTabLayer.hidden = !_showsHeaderTab;
        _headerTabLayer.strokeColor = border.CGColor;
        _headerTabLayer.lineWidth = _headerCardView.layer.borderWidth;
    } else if (_headerCardView) {
        _headerCardView.hidden = YES;
    }
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_headerCardView || _headerCardView.hidden) return;

    _headerCardView.frame = CGRectInset(self.bounds, 6.0f, 4.0f);
    _headerStripeView.frame = CGRectMake(0.0f, 0.0f, 4.0f, CGRectGetHeight(_headerCardView.bounds));
    _headerTabLayer.frame = CGRectMake(MAX(0.0f, CGRectGetWidth(_headerCardView.bounds) - 30.0f),
                                       0.0f, 30.0f, 30.0f);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGRect bounds = self.bounds;
    [VCBackgroundColor() setFill];
    UIRectFill(bounds);

    if (_kind == VCMainListCellKindSubscriptionHeader) return;

    BOOL nestedItem = (_kind == VCMainListCellKindSubscriptionItem);
    CGFloat panelLeft = nestedItem ? 22.0f : 6.0f;
    CGFloat topInset = _firstItem ? 4.0f : 0.0f;
    CGFloat bottomInset = _lastItem ? 8.0f : 0.0f;
    CGRect panel = CGRectMake(panelLeft,
                              topInset,
                              MAX(0.0f, CGRectGetWidth(bounds) - panelLeft - 6.0f),
                              MAX(0.0f, CGRectGetHeight(bounds) - topInset - bottomInset));
    if (CGRectGetWidth(panel) < 1.0f || CGRectGetHeight(panel) < 1.0f) return;

    UIRectCorner corners = 0;
    if (_firstItem) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (_lastItem) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    UIBezierPath *panelPath = corners
        ? [UIBezierPath bezierPathWithRoundedRect:panel
                                byRoundingCorners:corners
                                      cornerRadii:CGSizeMake(7.0f, 7.0f)]
        : [UIBezierPath bezierPathWithRect:panel];
    [((_selectedStyle || _active) ? VCSelectedCellColor() : VCCellBackgroundColor()) setFill];
    [panelPath fill];

    UIColor *panelBorder = _active
        ? [VCAccentColor() colorWithAlphaComponent:0.82f]
        : [VCSeparatorColor() colorWithAlphaComponent:0.72f];
    [panelBorder setStroke];
    panelPath.lineWidth = 0.75f;
    [panelPath stroke];

    if (!_lastItem) {
        if (_active) {
            [panelBorder setFill];
            UIRectFill(CGRectMake(CGRectGetMinX(panel),
                                  MAX(CGRectGetMinY(panel), CGRectGetMaxY(panel) - 0.75f),
                                  CGRectGetWidth(panel),
                                  0.75f));
        } else {
            [[VCSeparatorColor() colorWithAlphaComponent:0.52f] setFill];
            UIRectFill(CGRectMake(CGRectGetMinX(panel) + 14.0f,
                                  MAX(CGRectGetMinY(panel), CGRectGetMaxY(panel) - 0.5f),
                                  MAX(0.0f, CGRectGetWidth(panel) - 14.0f),
                                  0.5f));
        }
    }

    if (nestedItem) {
        CGFloat nodeX = 12.0f;
        CGFloat nodeY = CGRectGetMidY(panel);
        CGFloat lineTop = _firstItem ? CGRectGetMinY(panel) : 0.0f;
        CGFloat lineBottom = _lastItem ? nodeY : CGRectGetHeight(bounds);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetStrokeColorWithColor(context, [VCAccentColor() colorWithAlphaComponent:0.52f].CGColor);
        CGContextSetLineWidth(context, 1.5f);
        CGContextMoveToPoint(context, nodeX, lineTop);
        CGContextAddLineToPoint(context, nodeX, lineBottom);
        CGContextStrokePath(context);

        UIBezierPath *node = [UIBezierPath bezierPathWithArcCenter:CGPointMake(nodeX, nodeY)
                                                            radius:3.5f
                                                        startAngle:0.0f
                                                          endAngle:(CGFloat)(M_PI * 2.0f)
                                                         clockwise:YES];
        [VCBackgroundColor() setFill];
        [node fill];
        [VCAccentColor() setStroke];
        node.lineWidth = 1.5f;
        [node stroke];
    }
}

@end

static UIView *VCMainListCellReorderControlInView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass([subview class]) hasSuffix:@"ReorderControl"]) {
            return subview;
        }

        UIView *control = VCMainListCellReorderControlInView(subview);
        if (control) return control;
    }
    return nil;
}

@implementation VCMainListCell

@synthesize detailPrefix = _detailPrefix, detailTail = _detailTail, detailSupported = _detailSupported;

- (BOOL)hasDetailForURI:(NSString *)uri hidden:(BOOL)hidden stealth:(BOOL)stealth {
    return [uri isKindOfClass:[NSString class]] && _detailSourceURI && [_detailSourceURI isEqualToString:uri] && _detailHidden == hidden && _detailStealth == stealth;
}

- (void)rememberDetailURI:(NSString *)uri hidden:(BOOL)hidden stealth:(BOOL)stealth prefix:(NSString *)prefix tail:(NSString *)tail supported:(BOOL)supported {
    NSString *source = [uri isKindOfClass:[NSString class]] ? [uri copy] : nil;
    NSString *head = [prefix copy], *end = [tail copy];
    [_detailSourceURI release]; _detailSourceURI = source;
    [_detailPrefix release]; _detailPrefix = head;
    [_detailTail release]; _detailTail = end;
    _detailHidden = hidden; _detailStealth = stealth; _detailSupported = supported;
    [self invalidateDetailLayout];
}

- (BOOL)hasDetailLayoutForFrame:(CGRect)frame font:(UIFont *)font prefix:(NSString *)prefix tail:(NSString *)tail {
    return _detailLayoutValid && CGRectEqualToRect(frame, _detailLayoutFrame) && [_detailLayoutFont isEqual:font] &&
        [_detailLayoutPrefix isEqualToString:prefix] && [_detailLayoutTail isEqualToString:tail];
}

- (void)rememberDetailLayoutForFrame:(CGRect)frame font:(UIFont *)font prefix:(NSString *)prefix tail:(NSString *)tail {
    UIFont *base = [font retain];
    NSString *head = [prefix copy], *end = [tail copy];
    [_detailLayoutFont release]; _detailLayoutFont = base;
    [_detailLayoutPrefix release]; _detailLayoutPrefix = head;
    [_detailLayoutTail release]; _detailLayoutTail = end;
    _detailLayoutFrame = frame; _detailLayoutValid = YES;
}

- (void)invalidateDetailLayout {
    _detailLayoutValid = NO;
    [_detailLayoutFont release]; _detailLayoutFont = nil;
    [_detailLayoutPrefix release]; _detailLayoutPrefix = nil;
    [_detailLayoutTail release]; _detailLayoutTail = nil;
}

- (void)resetDetailState {
    [_detailSourceURI release]; _detailSourceURI = nil;
    [_detailPrefix release]; _detailPrefix = nil;
    [_detailTail release]; _detailTail = nil;
    [self invalidateDetailLayout];
}

- (void)prepareForReuse {
    [self resetDetailState];
    [super prepareForReuse];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    _normalVisualBackground = [[VCMainListCellBackgroundView alloc] initWithFrame:self.bounds];
    _selectedVisualBackground = [[VCMainListCellBackgroundView alloc] initWithFrame:self.bounds];
    self.backgroundView = _normalVisualBackground;
    self.selectedBackgroundView = _selectedVisualBackground;

    return self;
}

- (void)dealloc {
    [self resetDetailState];
    [_normalVisualBackground release];
    [_selectedVisualBackground release];
    [super dealloc];
}

- (void)configureVisualKind:(VCMainListCellKind)kind
                   expanded:(BOOL)expanded
                  firstItem:(BOOL)firstItem
                   lastItem:(BOOL)lastItem
                      active:(BOOL)active
             showsHeaderTab:(BOOL)showsHeaderTab {
    if (_visualKind != kind || _visualFirstItem != firstItem || _visualLastItem != lastItem)
        [self invalidateDetailLayout];
    _visualKind = kind;
    _visualExpanded = expanded;
    _visualFirstItem = firstItem;
    _visualLastItem = lastItem;
    _visualActive = active;
    _visualShowsHeaderTab = showsHeaderTab;
    [self refreshVisualAppearance];
    [self setNeedsLayout];
}

- (void)refreshVisualAppearance {
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.backgroundView = _normalVisualBackground;
    self.selectedBackgroundView = _selectedVisualBackground;

    [_normalVisualBackground configureKind:_visualKind
                                  expanded:_visualExpanded
                                 firstItem:_visualFirstItem
                                  lastItem:_visualLastItem
                                     active:_visualActive
                             showsHeaderTab:_visualShowsHeaderTab
                             selectedStyle:NO];
    [_selectedVisualBackground configureKind:_visualKind
                                    expanded:_visualExpanded
                                   firstItem:_visualFirstItem
                                    lastItem:_visualLastItem
                                       active:_visualActive
                               showsHeaderTab:_visualShowsHeaderTab
                               selectedStyle:YES];

    self.textLabel.textColor = VCPrimaryTextColor();
    self.textLabel.highlightedTextColor = VCPrimaryTextColor();
    self.detailTextLabel.textColor = VCSecondaryTextColor();
    self.detailTextLabel.highlightedTextColor = VCSecondaryTextColor();

    if (_visualKind == VCMainListCellKindSubscriptionHeader) {
        self.textLabel.font = [UIFont boldSystemFontOfSize:15.5f];
    } else {
        self.textLabel.font = [UIFont boldSystemFontOfSize:15.5f];
    }
}

- (BOOL)usesConfigurationItemLayout {
    return _visualKind == VCMainListCellKindSubscriptionItem ||
           _visualKind == VCMainListCellKindConfigurationItem;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsReorderControl) {
        UIView *reorderControl = VCMainListCellReorderControlInView(self);
        if (reorderControl && reorderControl.superview) {
            CGRect cellBounds = [self convertRect:self.bounds toView:reorderControl.superview];
            CGRect reorderFrame = reorderControl.frame;
            reorderFrame.origin.x = CGRectGetMaxX(cellBounds) - CGRectGetWidth(reorderFrame);
            reorderFrame.origin.y = floorf(CGRectGetMidY(cellBounds) -
                                            CGRectGetHeight(reorderFrame) * 0.5f);
            reorderControl.frame = reorderFrame;
        }
    }

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (self.accessoryView && !self.accessoryView.hidden) {
        CGRect accessoryFrame = self.accessoryView.frame;
        accessoryFrame.origin.x = floorf(CGRectGetWidth(self.bounds) -
                                         CGRectGetWidth(accessoryFrame) -
                                         (_visualKind == VCMainListCellKindSubscriptionHeader ? 6.0f : 14.0f));
        accessoryFrame.origin.y = floorf((CGRectGetHeight(self.bounds) -
                                          CGRectGetHeight(accessoryFrame)) * 0.5f);
        self.accessoryView.frame = accessoryFrame;
    }

    if (_visualKind == VCMainListCellKindSubscriptionHeader) {
        CGFloat left = 14.0f;
        CGFloat rightPadding = 8.0f;
        CGFloat titleRight = width - rightPadding;
        if (self.accessoryView && !self.accessoryView.hidden) {
            titleRight = MIN(titleRight, CGRectGetMinX(self.accessoryView.frame) - 6.0f);
        }
        if (_visualShowsHeaderTab) {
            titleRight = MIN(titleRight, CGRectGetWidth(self.bounds) - 110.0f);
        }
        self.textLabel.frame = CGRectMake(left, 9.0f, MAX(0.0f, titleRight - left), 21.0f);
        self.detailTextLabel.frame = CGRectMake(left, 34.0f, MAX(0.0f, width - left - rightPadding), 16.0f);
    } else if ([self usesConfigurationItemLayout]) {
        CGFloat left = (_visualKind == VCMainListCellKindSubscriptionItem) ? 22.0f : 7.0f;
        CGFloat rightPadding = 8.0f;
        CGFloat topInset = _visualFirstItem ? 4.0f : 0.0f;
        self.textLabel.frame = CGRectMake(left, topInset + 4.0f,
                                          MAX(0.0f, width - left - rightPadding), 22.0f);
        self.detailTextLabel.frame = CGRectMake(left, topInset + 26.0f,
                                                MAX(0.0f, width - left - rightPadding), 14.0f);

        if (self.accessoryView && !self.accessoryView.hidden) {
            CGFloat height = CGRectGetHeight(self.bounds);
            CGFloat bottomInset = _visualLastItem ? 8.0f : 0.0f;
            CGFloat panelMidY = topInset + (height - topInset - bottomInset) * 0.5f;
            CGRect accessoryFrame = self.accessoryView.frame;
            accessoryFrame.origin.y = floorf(panelMidY - CGRectGetHeight(accessoryFrame) * 0.5f);
            self.accessoryView.frame = accessoryFrame;
        }
    }

    _normalVisualBackground.frame = self.bounds;
    _selectedVisualBackground.frame = self.bounds;
}

@end

static CGFloat VCSubscriptionDescriptionHeight(NSString *description, CGFloat width) {
    if ([description length] == 0) return 0.0f;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize size = [description sizeWithFont:[UIFont systemFontOfSize:12.0f]
                          constrainedToSize:CGSizeMake(MAX(1.0f, width), CGFLOAT_MAX)
                              lineBreakMode:NSLineBreakByWordWrapping];
#pragma clang diagnostic pop
    return ceilf(size.height);
}

CGFloat VCSubscriptionCardHeight(NSString *description,
                                        CGFloat cardWidth,
                                        BOOL reordering) {
    return VCSubscriptionMeasuredCardHeight(VCSubscriptionDescriptionHeight(description, VCSubscriptionDescriptionWidth(cardWidth, reordering)));
}

@implementation VCDirectTouchHighlightButton

- (void)setHighlighted:(BOOL)highlighted {
    if (highlighted && !self.tracking) return;
    [super setHighlighted:highlighted];
}

@end

void VCApplyTouchFeedbackToButton(UIButton *button, id target) {
    if (!button) return;

    button.showsTouchWhenHighlighted = YES;
    button.adjustsImageWhenHighlighted = YES;
    button.layer.masksToBounds = NO;

    UIControlEvents releaseEvents = UIControlEventTouchUpInside |
        UIControlEventTouchUpOutside | UIControlEventTouchCancel;
    [button removeTarget:nil action:@selector(buttonTouchDown:)
        forControlEvents:UIControlEventTouchDown];
    [button removeTarget:nil action:@selector(buttonTouchUp:)
        forControlEvents:releaseEvents];
    if (!target) return;

    [button addTarget:target action:@selector(buttonTouchDown:)
        forControlEvents:UIControlEventTouchDown];
    [button addTarget:target action:@selector(buttonTouchUp:)
        forControlEvents:releaseEvents];
}

@implementation VCSubscriptionHeaderCell

- (void)updateDescriptionText:(NSString *)text {
    NSString *value = [text length] ? text : @"";
    if ([_providerDescriptionLabel.text isEqualToString:value]) return;
    _descriptionMeasureValid = NO;
    _providerDescriptionLabel.text = value;
}

- (CGFloat)descriptionHeightForWidth:(CGFloat)width {
    if (!_showsDescription || ![_providerDescriptionLabel.text length]) return 0.0f;
    if (!_descriptionMeasureValid || width != _descriptionMeasuredWidth) {
        _descriptionMeasuredHeight = VCSubscriptionDescriptionHeight(_providerDescriptionLabel.text, width);
        _descriptionMeasuredWidth = width;
        _descriptionMeasureValid = YES;
    }
    return _descriptionMeasuredHeight;
}

- (NSDictionary *)headerPresentationForInputs:(NSArray *)inputs {
    return [_headerPresentationInputs isEqual:inputs] ? _headerPresentation : nil;
}

- (void)rememberHeaderPresentation:(NSDictionary *)presentation inputs:(NSArray *)inputs {
    NSArray *keys = [inputs copy];
    NSDictionary *values = [presentation copy];
    [_headerPresentationInputs release]; _headerPresentationInputs = keys;
    [_headerPresentation release]; _headerPresentation = values;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [_headerPresentationInputs release]; _headerPresentationInputs = nil;
    [_headerPresentation release]; _headerPresentation = nil;
    _descriptionMeasureValid = NO;
    _providerDescriptionLabel.text = nil;
    _lastUpdatedLabel.text = nil;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.detailTextLabel.hidden = YES;

    _descriptionClipView = [[UIView alloc] initWithFrame:CGRectZero];
    _descriptionClipView.backgroundColor = [UIColor clearColor];
    _descriptionClipView.clipsToBounds = YES;
    _descriptionClipView.userInteractionEnabled = NO;
    [self addSubview:_descriptionClipView];

    _providerDescriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _providerDescriptionLabel.backgroundColor = [UIColor clearColor];
    _providerDescriptionLabel.font = [UIFont systemFontOfSize:12.0f];
    _providerDescriptionLabel.numberOfLines = 0;
    _providerDescriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _providerDescriptionLabel.textAlignment = NSTextAlignmentCenter;
    [_descriptionClipView addSubview:_providerDescriptionLabel];

    _lastUpdatedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _lastUpdatedLabel.backgroundColor = [UIColor clearColor];
    _lastUpdatedLabel.font = [UIFont systemFontOfSize:10.0f];
    _lastUpdatedLabel.numberOfLines = 1;
    _lastUpdatedLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_lastUpdatedLabel];

    _pingButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _pingButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    _pingButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _pingButton.showsTouchWhenHighlighted = NO;
    _pingButton.adjustsImageWhenHighlighted = NO;
    [self addSubview:_pingButton];

    _infoButton = [[VCDirectTouchHighlightButton alloc] initWithFrame:CGRectZero];
    _infoButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    _infoButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _infoButton.imageEdgeInsets = UIEdgeInsetsMake(2.0f, 0.0f, -2.0f, 0.0f);
    [self addSubview:_infoButton];

    for (NSUInteger i = 0; i < 3; i++) {
        _metadataIcons[i] = [[UIImageView alloc] initWithFrame:CGRectZero];
        _metadataIcons[i].isAccessibilityElement = NO;
        [self addSubview:_metadataIcons[i]];

        _metadataLabels[i] = [[UILabel alloc] initWithFrame:CGRectZero];
        _metadataLabels[i].backgroundColor = [UIColor clearColor];
        _metadataLabels[i].numberOfLines = 1;
        _metadataLabels[i].lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_metadataLabels[i]];
    }
    for (NSUInteger i = 0; i < 2; i++) {
        _metadataSeparators[i] = [[UILabel alloc] initWithFrame:CGRectZero];
        _metadataSeparators[i].backgroundColor = [UIColor clearColor];
        _metadataSeparators[i].text = @"•";
        _metadataSeparators[i].textAlignment = NSTextAlignmentCenter;
        _metadataSeparators[i].font = [UIFont systemFontOfSize:10.0f];
        [self addSubview:_metadataSeparators[i]];
    }

    _webPageButton = [[VCDirectTouchHighlightButton alloc] initWithFrame:CGRectZero];
    _webPageButton.accessibilityLabel = @"Web Page";
    _webPageButton.accessibilityHint = @"Opens the subscription provider's web page";
    [self addSubview:_webPageButton];

    _supportButton = [[VCDirectTouchHighlightButton alloc] initWithFrame:CGRectZero];
    _supportButton.accessibilityLabel = @"Support";
    _supportButton.accessibilityHint = @"Opens the subscription provider's support page";
    [self addSubview:_supportButton];

    return self;
}

- (void)dealloc {
    [_headerPresentationInputs release];
    [_headerPresentation release];
    [_descriptionClipView release];
    [_providerDescriptionLabel release];
    [_lastUpdatedLabel release];
    [_pingButton release];
    [_infoButton release];
    [_webPageButton release];
    [_supportButton release];
    for (NSUInteger i = 0; i < 3; i++) {
        [_metadataIcons[i] release];
        [_metadataLabels[i] release];
    }
    for (NSUInteger i = 0; i < 2; i++) {
        [_metadataSeparators[i] release];
    }
    [super dealloc];
}

- (void)configureDescription:(NSString *)description
                 configCount:(NSString *)configCount
                     traffic:(NSString *)traffic
                      expiry:(NSString *)expiry
                 lastUpdated:(NSString *)lastUpdated
             showDescription:(BOOL)showDescription
                 pingLoading:(BOOL)pingLoading
                     canPing:(BOOL)canPing
                showActions:(BOOL)showActions
                  hasWebPage:(BOOL)hasWebPage
                  hasSupport:(BOOL)hasSupport
                       index:(NSInteger)index
                      target:(id)target {
    _showsDescription = showDescription && [description length] > 0;
    _showsActions = showActions;
    [self updateDescriptionText:description];
    _lastUpdatedLabel.text = [lastUpdated length] > 0 ? lastUpdated : @"Updated: Never";
    _metadataLabels[0].text = configCount ? configCount : @"0";
    _metadataLabels[1].text = traffic ? traffic : @"";
    _metadataLabels[2].text = expiry ? expiry : @"";
    _metadataLabels[0].accessibilityLabel = [NSString stringWithFormat:@"%@ configurations", _metadataLabels[0].text];
    _metadataLabels[1].accessibilityLabel = [NSString stringWithFormat:@"Traffic: %@", _metadataLabels[1].text];
    _metadataLabels[2].accessibilityLabel = [NSString stringWithFormat:@"Expiry: %@", _metadataLabels[2].text];

    [_pingButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [_infoButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    _pingButton.hidden = !_showsActions;
    _infoButton.hidden = !_showsActions;
    _pingButton.enabled = pingLoading || canPing;
    _pingButton.tag = kVCSubscriptionPingButtonTagBase + index;
    _infoButton.tag = kVCSubscriptionInfoButtonTagBase + index;
    VCApplyTouchFeedbackToButton(_infoButton, _showsActions ? target : nil);
    if (_showsActions) {
        [_pingButton addTarget:target action:@selector(subscriptionPingButtonPressed:)
              forControlEvents:UIControlEventTouchUpInside];
        [_infoButton addTarget:target action:@selector(subscriptionInfoButtonPressed:)
              forControlEvents:UIControlEventTouchUpInside];
    }
    _pingButton.accessibilityLabel = pingLoading ? @"Stop subscription ping" : @"Ping all subscription configurations";
    _pingButton.accessibilityHint = pingLoading ? @"Stops the remaining latency tests"
        : [NSString stringWithFormat:@"Runs %@ latency tests", VCPingTypeName(VCSelectedPingType())];
    _infoButton.accessibilityLabel = @"Subscription information";
    _infoButton.accessibilityHint = @"Opens subscription details and actions";
    _pingLoading = pingLoading;
    [self refreshHeaderImages];

    [_webPageButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [_supportButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    _webPageButton.hidden = !hasWebPage;
    _supportButton.hidden = !hasSupport;
    if (hasWebPage) {
        _webPageButton.tag = kVCSubscriptionWebPageButtonTagBase + index;
        [_webPageButton addTarget:target
                           action:@selector(subscriptionWebPageButtonPressed:)
                 forControlEvents:UIControlEventTouchUpInside];
    }
    if (hasSupport) {
        _supportButton.tag = kVCSubscriptionSupportButtonTagBase + index;
        [_supportButton addTarget:target
                           action:@selector(subscriptionSupportButtonPressed:)
                 forControlEvents:UIControlEventTouchUpInside];
    }

    [self setNeedsLayout];
}

- (void)refreshVisualAppearance {
    [super refreshVisualAppearance];
    _providerDescriptionLabel.textColor = VCPrimaryTextColor();
    _lastUpdatedLabel.textColor = VCSecondaryTextColor();
    for (NSUInteger i = 0; i < 3; i++) {
        _metadataLabels[i].textColor = VCSecondaryTextColor();
    }
    for (NSUInteger i = 0; i < 2; i++) {
        _metadataSeparators[i].textColor = VCSecondaryTextColor();
    }

    [self refreshHeaderImages];
}

- (void)refreshHeaderImages {
    BOOL dark = VCAppearanceIsDark();
    NSInteger accent = VCAppearanceAccentIndex();
    BOOL changed = !_headerImagesValid || _headerImagesDark != dark || _headerImagesAccent != accent;
    if (!changed && _headerPingImageLoading == _pingLoading) return;
    if (changed) {
        VCIconType iconTypes[] = {VCIconTypeDocument, VCIconTypeStorage, VCIconTypeCalendar};
        for (NSUInteger i = 0; i < 3; i++) _metadataIcons[i].image = MakeIconImage(iconTypes[i], 13.0f, YES);
        [_infoButton setImage:LoadBundledIconTinted(@"info", 21.0f, VCSecondaryTextColor())
                    forState:UIControlStateNormal];
        [_webPageButton setImage:MakeIconImage(VCIconTypeGlobe, 17.0f, YES)
                    forState:UIControlStateNormal];
        [_webPageButton setImage:MakeIconImage(VCIconTypeGlobe, 17.0f, NO)
                    forState:UIControlStateHighlighted];
        [_supportButton setImage:MakeIconImage(VCIconTypeSupport, 17.0f, YES)
                    forState:UIControlStateNormal];
        [_supportButton setImage:MakeIconImage(VCIconTypeSupport, 17.0f, NO)
                    forState:UIControlStateHighlighted];
    }
    UIImage *pingIcon = _pingLoading ? MakeIconImage(VCIconTypeStop, 20.0f, NO)
        : LoadBundledIconTinted(@"icon-ping", 20.0f, VCPrimaryTextColor());
    [_pingButton setImage:(pingIcon ? pingIcon : MakeIconImage(VCIconTypeWifi, 18.0f, NO))
                forState:UIControlStateNormal];
    _headerImagesValid = _metadataIcons[0].image && _metadataIcons[1].image && _metadataIcons[2].image &&
        [_infoButton imageForState:UIControlStateNormal] && [_pingButton imageForState:UIControlStateNormal] &&
        [_webPageButton imageForState:UIControlStateNormal] && [_webPageButton imageForState:UIControlStateHighlighted] &&
        [_supportButton imageForState:UIControlStateNormal] && [_supportButton imageForState:UIControlStateHighlighted];
    _headerImagesDark = dark;
    _headerImagesAccent = accent;
    _headerPingImageLoading = _pingLoading;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.accessoryView && !self.accessoryView.hidden) {
        CGRect accessoryFrame = self.accessoryView.frame;
        accessoryFrame.origin.y = 4.0f;
        self.accessoryView.frame = accessoryFrame;
    }

    CGFloat left = 14.0f;
    BOOL reordering = self.showsReorderControl;
    CGFloat contentWidth = VCSubscriptionDescriptionWidth(CGRectGetWidth(self.bounds), reordering);
    CGFloat fixedWidth = 0.0f;
    CGFloat textWidth = 0.0f;
    NSUInteger visibleCount = 0;
    UIFont *baseFont = [UIFont systemFontOfSize:11.0f];
    for (NSUInteger i = 0; i < 3; i++) {
        if ([_metadataLabels[i].text length] == 0) continue;
        fixedWidth += 13.0f + 4.0f;
        if (visibleCount > 0) fixedWidth += 13.0f;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        textWidth += [_metadataLabels[i].text sizeWithFont:baseFont].width;
#pragma clang diagnostic pop
        visibleCount++;
    }
    CGFloat scale = VCMetadataScale(textWidth, contentWidth, fixedWidth);
    UIFont *metadataFont = (scale < 1.0f) ? [UIFont systemFontOfSize:MAX(1.0f, 11.0f * scale)]
                                            : baseFont;
    CGFloat metadataX = left;
    NSUInteger shown = 0;
    for (NSUInteger i = 0; i < 3; i++) {
        BOOL visible = [_metadataLabels[i].text length] > 0;
        _metadataIcons[i].hidden = !visible;
        _metadataLabels[i].hidden = !visible;
        if (!visible) {
            _metadataIcons[i].frame = CGRectZero;
            _metadataLabels[i].frame = CGRectZero;
            continue;
        }
        if (shown > 0) {
            UILabel *separator = _metadataSeparators[shown - 1];
            separator.hidden = NO;
            separator.frame = CGRectMake(metadataX + 4.0f, 34.0f, 5.0f, 16.0f);
            metadataX += 13.0f;
        }
        _metadataIcons[i].frame = CGRectMake(metadataX, 35.0f, 13.0f, 13.0f);
        metadataX += 17.0f;
        _metadataLabels[i].font = metadataFont;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGFloat labelWidth = ceilf([_metadataLabels[i].text sizeWithFont:metadataFont].width);
#pragma clang diagnostic pop
        _metadataLabels[i].frame = CGRectMake(metadataX, 34.0f, labelWidth, 16.0f);
        metadataX += labelWidth;
        shown++;
    }
    for (NSUInteger i = shown > 0 ? shown - 1 : 0; i < 2; i++) {
        _metadataSeparators[i].hidden = YES;
        _metadataSeparators[i].frame = CGRectZero;
    }
    CGFloat y = 52.0f;
    CGFloat descriptionHeight = [self descriptionHeightForWidth:contentWidth];
    CGFloat revealHeight = (_showsDescription && descriptionHeight > 0.0f)
        ? descriptionHeight + 5.0f : 0.0f;
    _descriptionClipView.frame = CGRectMake(left, y, contentWidth, revealHeight);
    _providerDescriptionLabel.frame = CGRectMake(0.0f, 0.0f, contentWidth, descriptionHeight);
    y += revealHeight;

    CGFloat metadataRight = left + contentWidth;
    if (_showsActions) {
        CGRect pingFrame, infoFrame;
        VCSubscriptionActionFrames(metadataRight, &pingFrame, &infoFrame);
        _pingButton.frame = pingFrame;
        _infoButton.frame = infoFrame;
    } else {
        _pingButton.frame = CGRectZero;
        _infoButton.frame = CGRectZero;
    }

    BOOL hasWebPage = !_webPageButton.hidden;
    BOOL hasSupport = !_supportButton.hidden;
    CGFloat buttonsWidth = 0.0f;
    if (hasWebPage) buttonsWidth += 26.0f;
    if (hasSupport) buttonsWidth += 26.0f;
    if (hasWebPage && hasSupport) buttonsWidth += 3.0f;
    CGFloat buttonX = metadataRight - buttonsWidth;
    if (hasWebPage) {
        _webPageButton.frame = CGRectMake(buttonX, y, 26.0f, 24.0f);
        buttonX += 29.0f;
    } else {
        _webPageButton.frame = CGRectZero;
    }
    if (hasSupport) {
        _supportButton.frame = CGRectMake(buttonX, y, 26.0f, 24.0f);
    } else {
        _supportButton.frame = CGRectZero;
    }

    CGFloat lastUpdatedRight = metadataRight - buttonsWidth;
    _lastUpdatedLabel.frame = CGRectMake(left,
                                         y + 5.0f,
                                         MAX(0.0f, lastUpdatedRight - left -
                                             (buttonsWidth > 0.0f ? 4.0f : 0.0f)),
                                         14.0f);
}

@end
