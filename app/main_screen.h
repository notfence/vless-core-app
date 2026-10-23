#import "app_support.h"
#import "update_checker.h"
#import "connection_button.h"
#import "settings.h"
#import "qr_scanner.h"
#import "subscription_info.h"
#import "import_browser.h"

@interface MainVC : UIViewController {
    UIButton *_connectBtn;
    UIImageView *_connectGlowView;
    UIView *_compactConnectGlowView;
    UIView *_mainSwitchView;
    VCConnectionPowerView *_connectPowerIcon;
    UILabel *_connectButtonTitle;
    UILabel *_connectionStateLabel;
    UILabel *_selectionLabel;
    UIButton *_plusBtn;
    UIButton *_terminalBtn;
    UIButton *_clearLogsBtn;
    UIButton *_refreshBtn;
    UIButton *_settingsBtn;
    UIButton *_updateBtn;
    UILabel *_statusLabel;
    UILabel *_uptimeLabel;
    UILabel *_titleLabel;

    UITableView *_tableView;
    UIView *_logSelector;
    UIButton *_logSelectorButtons[2];
    UIView *_logSelectionIndicator;
    UITextView *_logView;
    NSTimer *_logTimer;
    NSTimer *_uptimeTimer;
    NSTimeInterval _connectedSince;
    NSString *_statusBaseText;
    NSString *_pendingImportDoneStatus;
    NSArray *_pendingImportRefreshIndices;
    NSArray *_pendingInsecureImportURLs;
    void (^_pendingPlainHTTPConfirmation)(void);
    void (^_pendingPlainHTTPCancellation)(void);
    NSDictionary *_subscriptionToReexpandAfterReorder;
    VCUpdateChecker *_updateChecker;
    NSString *_availableReleaseURL;
    NSString *_availableUpdateVersion;
    NSString *_pendingReconnectURI;

    NSMutableArray *_configs;
    NSMutableArray *_subscriptions;
    dispatch_queue_t _configurationQueue;
    BOOL _configurationLoading;
    BOOL _metadataPreparationRunning;
    BOOL _metadataPreparationPending;
    NSUInteger _metadataRevision;
    NSMutableDictionary *_pendingProfileMetadata;
    NSURL *_deferredImportURL;
    NSMutableDictionary *_pingDisplayByURI;
    NSString *_pingNetworkSignature;
    NSTimer *_pingNetworkTimer;
    NSUInteger _pingNetworkGeneration;
    NSMutableDictionary *_standalonePingCancellationsByURI;
    NSMutableDictionary *_subscriptionPingPendingByIdentifier;
    NSMutableDictionary *_subscriptionPingOperationsByIdentifier;
    NSMutableDictionary *_subscriptionPingPreviousDisplayByIdentifier;
    NSMutableDictionary *_subscriptionPingTokenByIdentifier;
    NSOperationQueue *_pingQueue;

    NSInteger _selectedConfigIndex;
    NSInteger _selectedSubIndex;
    NSInteger _selectedSubItemIndex;
    NSInteger _expandedSubscription;
    NSInteger _subscriptionRowsExpandedOverride;
    NSInteger _subscriptionHeaderExpandedOverride;
    NSInteger _compactSubscriptionTransitionTarget;
    NSInteger _compactSubscriptionTransitionAnchorIndex;
    CGFloat _compactSubscriptionTransitionAnchorViewportY;
    CGFloat _compactSubscriptionTransitionFinalContentHeight;
    NSInteger _updatingSubscriptionIndex;
    NSInteger _reorderingSection;
    NSInteger _activeLogIndex;
    NSUInteger _mainSectionTransitionToken;
    NSUInteger _nextSubscriptionPingToken;
    NSUInteger _connectionActionGeneration;
    NSString *_logTexts[2];
    CGPoint _logContentOffsets[2];
    CGFloat _mainTableDragStartOffsetY;
    CGFloat _mainTableOffsetBeforeTransition;
    BOOL _logContentOffsetsValid[2];
    BOOL _logFollowsTail[2];
    BOOL _mainTableDragStartOffsetValid;
    BOOL _mainTableTransitionSnapshotValid;
    BOOL _phoneConnectionCompact;
    BOOL _phoneConnectionCompactBeforeTransition;
    BOOL _subscriptionExpansionOverridesActive;
    BOOL _compactSubscriptionOffsetAnimationInProgress;

    BOOL _connected;
    BOOL _connectedWithProtectedLogs;
    BOOL _connectionActionInProgress;
    BOOL _reconnectInProgress;
    BOOL _pendingReconnectProtectLogs;
    BOOL _daemonStatusCheckInFlight;
    BOOL _showingTerminal;
    BOOL _autoUpdateSubscriptions;
    BOOL _preserveCustomSubscriptionNames;
    BOOL _stealthModeEnabled;
    BOOL _darkThemeEnabled;
    BOOL _automaticUpdateChecksEnabled;
    BOOL _statusOK;
    BOOL _configurationsSectionExpanded;
    BOOL _subscriptionsSectionExpanded;
    BOOL _mainSectionTransitionInProgress;
    BOOL _mainTabTransitionInProgress;
    BOOL _didRunLaunchAutoUpdate;
    BOOL _subscriptionRefreshInProgress;
    BOOL _didScheduleAutomaticUpdateCheck;
    BOOL _launchAutoUpdateInProgress;
    BOOL _queuedMainDetailRelayout;
    BOOL _pendingInsecureImportUsesHappHeaders;
}
@end


@interface MainVC (VCMainState)
- (NSString *)safeTrim:(NSString *)s;
- (NSString *)decodedFragmentFromURI:(NSString *)uri;
- (NSString *)hostFromVLESSURI:(NSString *)uri;
- (NSString *)schemeFromURIString:(NSString *)uri;
- (BOOL)parseSOCKS5Host:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri;
- (NSString *)hostFromConfigURI:(NSString *)uri;
- (NSString *)displayNameForURI:(NSString *)uri index:(NSInteger)index;
- (NSString *)displayNameForSubscriptionURI:(NSString *)uri
                                      index:(NSInteger)index
                               subscription:(NSDictionary *)subscription;
- (NSString *)hostFromURLString:(NSString *)urlString;
- (NSString *)decodedURLComponent:(NSString *)component;
- (NSString *)strictDecodedConfigQueryComponent:(NSString *)component;
- (NSString *)canonicalConfigQueryKey:(NSString *)encodedKey;
- (NSString *)configURIQueryValidationReason:(NSString *)uri;
- (NSString *)queryValueForURLString:(NSString *)urlString key:(NSString *)key;
- (NSString *)transportTypeFromURI:(NSString *)uri;
- (NSString *)securityTypeFromURI:(NSString *)uri;
- (NSString *)realityFlowFromURI:(NSString *)uri;
- (NSString *)realityFingerprintFromURI:(NSString *)uri;
- (BOOL)isSupportedRealityFingerprint:(NSString *)fp;
- (NSString *)subscriptionNameFromURLString:(NSString *)urlString;
- (BOOL)isLikelyLinkText:(NSString *)text;
- (NSString *)maskedLinkText:(NSString *)text;
- (BOOL)isSubscriptionURL:(NSString *)s;
- (BOOL)isVLESSURI:(NSString *)s;
- (BOOL)isSOCKS5URI:(NSString *)s;
- (BOOL)isDirectConfigURI:(NSString *)s;
- (void)saveMainState;
- (void)flushMainStateDefaults;
- (void)saveData;
- (void)loadData;
- (void)completeConfigurationLoad:(NSDictionary *)loaded;
- (void)prepareProfileMetadata;
- (void)profileMetadataPrepared:(NSDictionary *)metadata;
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)subIdx;
- (NSInteger)subscriptionRowsExpandedIndex;
- (NSInteger)subscriptionHeaderExpandedIndex;
- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)subIdx;
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)subIdx;
- (NSInteger)subscriptionSectionRowCount;
- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)subIndex itemIndex:(NSInteger *)itemIndex isHeader:(BOOL *)isHeader;
- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)subIdx;
- (void)setUpdatingSubscriptionIndex:(NSInteger)subIdx;
- (void)normalizeSelection;
- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri;
- (NSString *)endpointFromConfigURI:(NSString *)uri;
- (NSString *)configSecondaryTextFromURI:(NSString *)uri;
- (NSString *)configPrefixTextFromURI:(NSString *)uri;
- (NSString *)configEndpointTextFromURI:(NSString *)uri;
- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri;
- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri;
- (UIColor *)configPrefixColorForURI:(NSString *)uri;
- (NSString *)unsupportedConfigStatusTextForURI:(NSString *)uri;
@end

@interface MainVC (VCMainConnection)
- (NSString *)sanitizeDaemonText:(NSString *)text;
- (NSString *)formatDuration:(NSTimeInterval)seconds;
- (void)refreshStatusText;
- (void)refreshUptimeText;
- (void)startUptimeTimerWithDaemonResponse:(NSString *)response;
- (void)stopUptimeTimer;
- (void)uptimeTick:(NSTimer *)timer;
- (void)reconcileConnectionStateWithDaemon;
- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification;
- (void)showStatus:(NSString *)text ok:(BOOL)ok;
- (BOOL)isXHTTPTransportURI:(NSString *)uri;
- (NSString *)xhttpPinKeyFromURI:(NSString *)uri;
- (NSString *)xhttpTOFUPinMismatchStatusForURI:(NSString *)uri;
- (NSInteger)socksPortFromDaemonStatusText:(NSString *)statusText;
- (NSInteger)currentDaemonSocksPort;
- (void)xhttpConnectHealthCheckWorker:(NSDictionary *)payload;
- (void)xhttpConnectHealthCheckResultOnMain:(NSDictionary *)payload;
- (void)scheduleXHTTPConnectHealthCheckForURI:(NSString *)uri;
- (void)setSubscriptionRefreshInProgress:(BOOL)inProgress;
- (BOOL)isConnectionActionInProgress;
- (NSString *)uriForCurrentSelection;
- (BOOL)selectedSubscriptionIsHappEncrypted;
- (void)reconnectToURIIfNeededFrom:(NSString *)oldURI to:(NSString *)newURI;
- (void)beginPendingReconnect;
- (void)togglePressed;
- (void)queryInitialStatus;
@end

@interface MainVC (VCMainPing)
- (void)refreshPingNetworkState;
- (void)pingNetworkTick:(NSTimer *)timer;
- (void)pingWorker:(NSDictionary *)payload;
- (void)pingResultOnMain:(NSDictionary *)payload;
- (NSOperation *)enqueuePingForURI:(NSString *)uri
                              type:(VCPingType)pingType
                          priority:(NSOperationQueuePriority)priority
                   batchIdentifier:(NSString *)batchIdentifier
                        batchToken:(NSNumber *)batchToken;
- (void)startPingForURI:(NSString *)uri type:(VCPingType)pingType;
- (void)pingButtonPressed:(UIButton *)sender;
- (void)startSubscriptionPingAtIndex:(NSInteger)subIdx;
- (BOOL)isURIInActiveSubscriptionPing:(NSString *)uri;
- (void)stopSubscriptionPingAtIndex:(NSInteger)subIdx;
- (void)subscriptionPingButtonPressed:(UIButton *)sender;
- (void)stopAllPings;
@end

@interface MainVC (VCMainSubscriptions) <SubscriptionInfoVCDelegate, VCSubscriptionUpdateOptions>
- (NSString *)decodedSubscriptionTitleValue:(NSString *)rawValue;
- (NSString *)subscriptionTitleFromMetadataText:(NSString *)text;
- (NSString *)subscriptionTitleFromData:(NSData *)data;
- (NSString *)subscriptionTitleFromHTTPHeaders:(NSDictionary *)headers;
- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromMetadataText:(NSString *)text;
- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromHTTPHeaders:(NSDictionary *)headers;
- (NSNumber *)subscriptionUnsignedNumberFromString:(NSString *)text;
- (NSDictionary *)subscriptionUserInfoFromHeaderValue:(NSString *)headerValue;
- (NSDictionary *)subscriptionUserInfoFromMetadataText:(NSString *)text;
- (NSDictionary *)subscriptionUserInfoFromData:(NSData *)data;
- (NSDictionary *)subscriptionUserInfoFromHTTPHeaders:(NSDictionary *)headers;
- (NSDictionary *)subscriptionMetadataFromMetadataText:(NSString *)text;
- (NSDictionary *)subscriptionMetadataFromData:(NSData *)data;
- (NSDictionary *)subscriptionMetadataFromHTTPHeaders:(NSDictionary *)headers;
- (NSString *)formattedSubscriptionBytes:(unsigned long long)bytes;
- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub;
- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub;
- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut insecureRetryAvailable:(BOOL *)insecureRetryAvailableOut;
- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut;
- (BOOL)subscriptionNeedsPlainHTTPApproval:(NSDictionary *)sub;
- (BOOL)approvePlainHTTPForSubscriptionAtIndex:(NSInteger)index;
- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus;
- (BOOL)subscriptionsMatchSnapshotForLaunchAutoUpdate:(NSArray *)snapshot;
- (void)startBackgroundSubscriptionRefreshWithStatus:(NSString *)startStatus;
- (void)startLaunchAutoUpdateIfNeeded;
- (void)refreshAllSubscriptions:(BOOL)showStatus;
- (void)openSubscriptionProviderURLAtIndex:(NSInteger)index
                               metadataKey:(NSString *)metadataKey
                                 eventName:(NSString *)eventName;
- (void)subscriptionWebPageButtonPressed:(UIButton *)sender;
- (void)subscriptionSupportButtonPressed:(UIButton *)sender;
- (void)subscriptionInfoButtonPressed:(UIButton *)sender;
- (void)refreshPresentedSubscriptionInfoIfNeeded;
- (void)subscriptionInfoVCRequestedRefresh:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
- (void)subscriptionInfoVC:(SubscriptionInfoVC *)vc requestedRenameTo:(NSString *)name atIndex:(NSInteger)index;
- (BOOL)deleteSubscriptionAtIndex:(NSInteger)subIdx;
- (void)subscriptionInfoVCRequestedDelete:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
@end

@interface MainVC (VCMainImport) <UIActionSheetDelegate, UIAlertViewDelegate, QRScanVCDelegate, VCImportBrowserDelegate>
- (void)showProfileImportWarnings:(NSArray *)reports;
- (NSArray *)extractConfigURIsFromText:(NSString *)text;
- (NSArray *)extractImportLinksFromText:(NSString *)text;
- (NSString *)happJSONStringValue:(id)value;
- (NSDictionary *)happJSONDictionaryValue:(id)value;
- (NSArray *)happJSONArrayValue:(id)value;
- (NSString *)percentEncodedHappURIValue:(NSString *)value;
- (NSString *)happJSONStringFromDictionary:(NSDictionary *)dictionary;
- (void)addHappURIQueryValue:(NSString *)value key:(NSString *)key toParts:(NSMutableArray *)parts;
- (NSString *)vlessURIFromHappJSONConfig:(NSDictionary *)config;
- (NSArray *)extractConfigURIsFromHappJSONData:(NSData *)data;
- (NSArray *)parseSubscriptionData:(NSData *)data;
- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri;
- (NSArray *)sanitizeSubscriptionURIs:(NSArray *)uris;
- (NSInteger)existingConfigIndexForURI:(NSString *)uri;
- (NSInteger)existingSubscriptionIndexForURL:(NSString *)urlString;
- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                 allowPlainHTTP:(BOOL)allowPlainHTTP
                                     happSource:(BOOL)happSource;
- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                     happSource:(BOOL)happSource;
- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch;
- (void)selectSubscriptionAtIndex:(NSInteger)subIndex;
- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation;
- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation
                                        cancellation:(void (^)(void))cancellation;
- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings
                                    fromBatchImport:(BOOL)fromBatchImport
                                         happSource:(BOOL)happSource;
- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings fromBatchImport:(BOOL)fromBatchImport;
- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString;
- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString happSource:(BOOL)happSource;
- (void)commitUpdatedSubscription:(NSDictionary *)updated existingIndex:(NSInteger)existingIndex;
- (NSString *)subscriptionImportCountText:(NSUInteger)count;
- (NSString *)shortSubscriptionFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText defaultReason:(NSString *)defaultReason;
- (NSString *)shortImportFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText;
- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText;
- (void)showSubscriptionFailureAlertWithTitle:(NSString *)title failureTexts:(NSArray *)failureTexts;
- (void)showSubscriptionImportFailures:(NSArray *)failureTexts;
- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts;
- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart;
- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL;
- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL
                                  allowPlainHTTP:(BOOL)allowPlainHTTP;
- (void)importDirectURI:(NSString *)uri;
- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
               allowPlainHTTP:(BOOL)allowPlainHTTP
                   happSource:(BOOL)happSource;
- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
                   happSource:(BOOL)happSource;
- (void)importSubscriptionURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch;
- (void)importSubscriptionURL:(NSString *)urlString;
- (BOOL)isHappEncryptedLink:(NSString *)text;
- (BOOL)isHappAddLink:(NSString *)text;
- (NSString *)targetFromHappAddLink:(NSString *)link;
- (NSString *)decryptedHappLink:(NSString *)link errorText:(NSString **)errorTextOut;
- (void)importHappEncryptedLink:(NSString *)link;
- (void)importHappAddLink:(NSString *)link;
- (void)importTextEntry:(NSString *)rawText;
- (void)importKaringSubscriptionEntries:(NSArray *)entries;
- (void)importKaringBackupData:(NSData *)data;
- (void)receiveKaringBackupWithDescriptor:(NSDictionary *)descriptor;
- (NSString *)decodeImportTextData:(NSData *)data;
- (void)importTextFileAtPath:(NSString *)rawPath;
- (void)importFileAtURL:(NSURL *)url;
- (void)startFileBrowserImportFlow;
- (void)importBrowserDidCancel:(UIViewController *)browser;
- (void)importBrowser:(UIViewController *)browser didSelectFileAtPath:(NSString *)path;
- (void)startQRImportFlow;
- (void)plusPressed;
- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex;
- (void)qrScanVCDidCancel:(UIViewController *)vc;
- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text;
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
@end

@interface MainVC (VCMainLayout)
- (void)recordMainLayoutEvent:(NSString *)action;
- (UIStatusBarStyle)preferredStatusBarStyle;
- (UIView *)mainDetailContainerForCell:(UITableViewCell *)cell createIfNeeded:(BOOL)createIfNeeded;
- (UILabel *)mainDetailPrefixLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded;
- (UILabel *)mainDetailTailLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded;
- (CGRect)mainDetailContentFrameForCell:(UITableViewCell *)cell;
- (void)clearDetailTextForCell:(UITableViewCell *)cell;
- (UIFont *)mainDetailFont:(UIFont *)font
             fittingPrefix:(NSString *)prefix
                      tail:(NSString *)tail
                     width:(CGFloat)width;
- (void)applyDetailPrefix:(NSString *)prefix
              prefixColor:(UIColor *)prefixColor
                     tail:(NSString *)tail
                   toCell:(UITableViewCell *)cell;
- (void)applyDetailPrefix:(NSString *)prefix tail:(NSString *)tail toCell:(UITableViewCell *)cell;
- (void)updateConnectionSummary;
- (void)updateConnectButton;
- (void)applyTopButtonFeedbackToButton:(UIButton *)btn;
- (void)buttonTouchDown:(UIButton *)sender;
- (void)buttonTouchUp:(UIButton *)sender;
- (void)updateTopButtonsIcons;
- (UIView *)accessoryChevronExpanded:(BOOL)expanded;
- (UIView *)subscriptionHeaderAccessoryExpanded:(BOOL)expanded loading:(BOOL)loading;
- (UIView *)accessoryPingWithTag:(NSInteger)tag uri:(NSString *)uri;
- (void)updatePhoneConnectionScrollInsets;
- (void)updatePhoneConnectionLayout;
- (void)updatePadConnectionLayout;
- (CGFloat)maximumMainTableContentOffsetY;
- (CGFloat)phoneConnectionSnapOffsetForProposedOffset:(CGFloat)proposedOffset
                                         currentOffset:(CGFloat)currentOffset
                                              velocity:(CGFloat)velocity;
- (void)animatePhoneConnectionToOffset:(CGFloat)targetOffset;
- (void)snapPhoneConnectionLayoutIfNeededAnimated:(BOOL)animated;
- (void)prepareMainTableStructuralTransition;
- (void)stabilizeMainTableOffsetDuringStructuralTransition;
- (void)restoreMainTableAfterStructuralTransitionCompact:(BOOL)compact
                                          preservedOffset:(CGFloat)preservedOffset;
- (void)completeMainTableStructuralTransition;
- (void)retargetCompactSubscriptionTransitionAnchor;
- (void)animateCompactSubscriptionOffsetToFinalPosition;
- (void)recoverCompactSubscriptionTransition:(NSNumber *)transitionNumber;
- (void)finishCompactSubscriptionTransition:(NSNumber *)transitionNumber;
- (void)startCompactSubscriptionTransitionFromHeaderRow:(NSInteger)oldHeaderRow
                                            oldItemCount:(NSInteger)oldItemCount
                                            newItemCount:(NSInteger)newItemCount
                                              anchorIndex:(NSInteger)anchorIndex
                                          anchorViewportY:(CGFloat)anchorViewportY;
- (void)updateMainEmptyState;
- (void)applyTheme;
- (void)setMainReorderingSection:(NSInteger)section showStatus:(BOOL)showStatus;
- (void)mainTabLongPressed:(UILongPressGestureRecognizer *)gesture;
- (void)mainTabPressed:(UIButton *)sender;
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
- (UIView *)createMainSwitcherWithWidth:(CGFloat)width;
- (void)updateMainTabButton:(UIButton *)button section:(NSInteger)section;
- (void)updateMainSwitcherView:(UIView *)header;
- (void)reloadMainTableDataAfterExternalChange;
- (void)configureSubscriptionHeaderCell:(UITableViewCell *)cell atIndex:(NSInteger)index;
- (void)refreshVisibleSubscriptionHeaderAccessories;
- (void)refreshVisibleSubscriptionHeaderExpansionAppearanceAnimated:(BOOL)animated;
- (BOOL)isMainTabSelected:(NSInteger)section;
- (void)refreshMainSwitcher;
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView;
@end

@interface MainVC (VCMainSettings) <SettingsVCDelegate, VCUpdateCheckerDelegate>
- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled;
- (void)settingsVCDidChangeAccentColor:(SettingsVC *)vc;
- (void)refreshPressed;
- (void)settingsPressed;
- (void)refreshUpdateIndicatorFromCache;
- (void)updateIndicatorPressed;
- (void)startAutomaticUpdateCheckIfNeeded;
- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result;
@end

@interface MainVC (VCMainTerminal) <UITextViewDelegate>
- (void)terminalPressed;
- (CGFloat)maximumLogOffsetY;
- (void)rememberActiveLogPosition;
- (void)displayLogText:(NSString *)text
               atIndex:(NSInteger)index
                offset:(CGPoint)savedOffset
            followTail:(BOOL)followTail;
- (void)updateLogSelectorAnimated:(BOOL)animated;
- (void)logSourceChanged:(UIButton *)sender;
- (void)refreshLogs;
- (void)forceRefreshLogs;
- (void)clearLogsPressed;
- (void)refreshLogsTick:(NSTimer *)timer;
@end

@interface MainVC (VCMainTable) <UITableViewDataSource, UITableViewDelegate>
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath;
- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath;
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)applyDetailForMainCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
- (void)runQueuedMainDetailRelayout;
- (void)scheduleMainDetailRelayout;
- (void)refreshMainListCellAppearance:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
- (void)refreshVisiblePingAccessoriesForURI:(NSString *)uri;
- (void)refreshVisibleSubscriptionPingAccessories;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end
