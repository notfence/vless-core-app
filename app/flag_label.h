#import <UIKit/UIKit.h>

@interface VCFlagLabel : UILabel {
    id _flagLayout;
}
@end

CGSize VCFlagTextSize(NSString *text, UIFont *font, CGSize constraint, NSLineBreakMode mode);

@interface VCFlagTableCell : UITableViewCell {
    UILabel *_flagTitleLabel;
    UILabel *_flagDetailLabel;
}
@end
