#import "app_support.h"
#import "flag_label.h"

@class VCMainListCellBackgroundView, VCMainListCell, VCDirectTouchHighlightButton, VCSubscriptionHeaderCell;

typedef NS_ENUM(NSInteger, VCMainListCellKind) {
    VCMainListCellKindSubscriptionHeader = 0,
    VCMainListCellKindSubscriptionItem = 1,
    VCMainListCellKindConfigurationItem = 2,
};

@interface VCMainListCellBackgroundView : UIView {
    VCMainListCellKind _kind;
    BOOL _expanded;
    BOOL _firstItem;
    BOOL _lastItem;
    BOOL _active;
    BOOL _selectedStyle;
    BOOL _showsHeaderTab;
    UIView *_headerCardView;
    UIView *_headerStripeView;
    CAShapeLayer *_headerTabLayer;
}
- (void)configureKind:(VCMainListCellKind)kind
             expanded:(BOOL)expanded
            firstItem:(BOOL)firstItem
             lastItem:(BOOL)lastItem
                active:(BOOL)active
        showsHeaderTab:(BOOL)showsHeaderTab
        selectedStyle:(BOOL)selectedStyle;
@end

@interface VCMainListCell : VCFlagTableCell {
    VCMainListCellKind _visualKind;
    BOOL _visualExpanded;
    BOOL _visualFirstItem;
    BOOL _visualLastItem;
    BOOL _visualActive;
    BOOL _visualShowsHeaderTab;
    VCMainListCellBackgroundView *_normalVisualBackground;
    VCMainListCellBackgroundView *_selectedVisualBackground;
}
- (void)configureVisualKind:(VCMainListCellKind)kind
                   expanded:(BOOL)expanded
                  firstItem:(BOOL)firstItem
                   lastItem:(BOOL)lastItem
                      active:(BOOL)active
             showsHeaderTab:(BOOL)showsHeaderTab;
- (void)refreshVisualAppearance;
- (BOOL)usesConfigurationItemLayout;
@end

@interface VCDirectTouchHighlightButton : UIButton
@end

@interface VCSubscriptionHeaderCell : VCMainListCell {
    UIView *_descriptionClipView;
    UILabel *_providerDescriptionLabel;
    UILabel *_lastUpdatedLabel;
    UIButton *_pingButton;
    UIButton *_infoButton;
    UIButton *_webPageButton;
    UIButton *_supportButton;
    UIImageView *_metadataIcons[3];
    UILabel *_metadataLabels[3];
    UILabel *_metadataSeparators[2];
    BOOL _showsDescription;
    BOOL _showsActions;
    BOOL _pingLoading, _headerImagesValid, _headerImagesDark, _headerPingImageLoading;
    NSInteger _headerImagesAccent;
}
- (void)refreshHeaderImages;
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
                      target:(id)target;
@end
