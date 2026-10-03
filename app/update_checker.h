#import "app_support.h"

@class VCUpdateChecker;

@protocol VCUpdateCheckerDelegate <NSObject>
- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result;
@end

@interface VCUpdateChecker : NSObject {
    id<VCUpdateCheckerDelegate> _delegate;
    BOOL _started;
}
@property (nonatomic, assign) id<VCUpdateCheckerDelegate> delegate;
- (id)initWithDelegate:(id<VCUpdateCheckerDelegate>)delegate;
- (void)start;
@end
