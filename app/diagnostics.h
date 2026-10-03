#import "app_support.h"

@class VCAppEventRecorder, DiagnosticEventsVC, DebugVC;

@interface VCAppEventRecorder : NSObject {
    NSMutableArray *_events;
    NSMutableArray *_pendingEvents;
    dispatch_queue_t _writeQueue;
    BOOL _flushScheduled;
}
+ (VCAppEventRecorder *)sharedRecorder;
- (void)recordCategory:(NSString *)category action:(NSString *)action detail:(NSString *)detail;
- (NSArray *)eventsSnapshot;
- (void)flushNow;
- (void)clearEvents;
- (void)setAppActivityEnabled:(BOOL)enabled;
@end

@interface DiagnosticEventsVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    NSArray *_events;
}
- (id)initWithEvents:(NSArray *)events;
@end

@interface DebugVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentInteractionControllerDelegate> {
    UITableView *_tableView;
    NSDictionary *_daemonState;
    NSArray *_daemonEvents;
    NSArray *_appEvents;
    NSMutableArray *_localEvents;
    NSArray *_displayEvents;
    NSDictionary *_qualityState;
    NSString *_lastNetwork;
    NSTimer *_refreshTimer;
    UIDocumentInteractionController *_documentController;
    UISwitch *_appActivitySwitch;
    BOOL _refreshing;
    BOOL _checking;
    BOOL _reporting;
    NSUInteger _qualityGeneration;
}
@end
