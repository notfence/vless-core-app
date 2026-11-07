#import "main_screen.h"

@implementation MainVC (VCSubscriptionWork)

- (VCSubscriptionTask *)beginSubscriptionTask {
    return [self beginSubscriptionTaskWithKind:VCSubscriptionTaskProfiles];
}

- (VCSubscriptionTask *)beginSubscriptionTaskWithKind:(VCSubscriptionTaskKind)kind {
    if (_subscriptionTask || _configurationLoading || _configurationDraft || _launchAutoUpdateInProgress) {
        [self showStatus:@"Another import or update is already running" ok:NO]; return nil;
    }
    _subscriptionTask=[[VCSubscriptionTask alloc] initWithPreserveNames:_preserveCustomSubscriptionNames kind:kind observer:self selector:@selector(subscriptionTaskProgress:)];
    if (_photoQRQueue) { _photoQRTaskConfigs=[_configs count]; _photoQRTaskSubscriptions=[_subscriptions count]; }
    NSDictionary *metadata=nil;
    @synchronized(self) { metadata=[_pendingProfileMetadata autorelease]; _pendingProfileMetadata=nil; }
    [_subscriptionTask profileMetadataPrepared:metadata];
    _launchAutoUpdateInProgress=YES;
    [self setSubscriptionRefreshInProgress:YES];
    _refreshBtn.enabled=YES;
    [self updateTopButtonsIcons];
    [self subscriptionTaskProgress:_subscriptionTask];
    return _subscriptionTask;
}

- (void)finishSubscriptionTask:(VCSubscriptionTask *)task success:(BOOL)success {
    if (task != _subscriptionTask) return;
    NSDictionary *progress=[task consumeProgress];
    BOOL cancelled=task.isCancelled;
    if (_photoQRQueue) {
        if (success) {
            _photoQRAdded+=([_configs count]>=_photoQRTaskConfigs ? [_configs count]-_photoQRTaskConfigs : 0)+([_subscriptions count]>=_photoQRTaskSubscriptions ? [_subscriptions count]-_photoQRTaskSubscriptions : 0);
            _photoQRDuplicates+=[[progress objectForKey:@"duplicates"] unsignedIntegerValue];
            _photoQRRejected+=[[progress objectForKey:@"skipped"] unsignedIntegerValue];
        }
        if (cancelled) _photoQRCancelled=YES;
        [self performSelector:@selector(advancePhotoQRImport) withObject:nil afterDelay:0];
    }
    BOOL connect=success && !cancelled && _connectAfterSubscriptionTask == task && !_connected &&
        _selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count] &&
        [[[_subscriptions objectAtIndex:_selectedSubIndex] objectForKey:@"url"] isEqual:_connectAfterSubscriptionURL] &&
        [[self subscriptionItemsAtIndex:_selectedSubIndex] count] > 0;
    if (_connectAfterSubscriptionTask == task) {
        _connectAfterSubscriptionTask=nil; [_connectAfterSubscriptionURL release]; _connectAfterSubscriptionURL=nil;
    }
    if (cancelled) [self showStatus:task.cancellationReason ok:NO];
    else if (success && ([[progress objectForKey:@"accepted"] unsignedIntegerValue] || [[progress objectForKey:@"skipped"] unsignedIntegerValue] || [[progress objectForKey:@"duplicates"] unsignedIntegerValue])) {
        NSString *title=task.kind == VCSubscriptionTaskProfiles ? (_statusBaseText ?: @"Import finished") : @"Subscriptions updated";
        [self showStatus:[NSString stringWithFormat:@"%@: %@ valid profiles, %@ duplicates, %@ unsupported",title,[progress objectForKey:@"accepted"],[progress objectForKey:@"duplicates"],[progress objectForKey:@"skipped"]] ok:_statusOK];
    }
    [task finish]; [_subscriptionTask release]; _subscriptionTask=nil;
    _launchAutoUpdateInProgress=NO;
    if (_subscriptionRefreshInProgress) [self setSubscriptionRefreshInProgress:NO];
    else [self updateConnectButton];
    [self setUpdatingSubscriptionIndex:-1];
    _refreshBtn.enabled=!_configurationCommitInProgress;
    [self updateTopButtonsIcons];
    @synchronized(self) { [_pendingProfileMetadata release]; _pendingProfileMetadata=nil; }
    if (connect) [self performSelector:@selector(togglePressed) withObject:nil afterDelay:0];
}

- (void)subscriptionTaskProgress:(VCSubscriptionTask *)task {
    if (!task || task != _subscriptionTask) return;
    NSDictionary *progress=[task consumeProgress];
    if ([[progress objectForKey:@"determinate"] boolValue]) {
        [_connectPowerIcon setProgress:[[progress objectForKey:@"fraction"] doubleValue]];
        _connectBtn.accessibilityValue=[NSString stringWithFormat:@"Processing profiles: %@/%@",[progress objectForKey:@"processed"],[progress objectForKey:@"total"]];
    } else {
        [_connectPowerIcon setLoading:YES];
        _connectBtn.accessibilityValue=[progress objectForKey:@"phase"];
    }
    _refreshBtn.enabled=[[progress objectForKey:@"stoppable"] boolValue];
}

- (void)cancelSubscriptionTask {
    if (_photoQRQueue && ![_subscriptionTask isCommitting]) _photoQRCancelled=YES;
    if ([_subscriptionTask cancelWithReason:nil]) {
        _refreshBtn.enabled=NO;
        [self subscriptionTaskProgress:_subscriptionTask];
    }
}

- (void)startTextImport:(NSString *)text filePath:(NSString *)path {
    [self startTextImports:text ? @[text] : nil filePath:path separateQR:NO];
}

- (void)startTextImports:(NSArray *)texts filePath:(NSString *)path separateQR:(BOOL)separate {
    VCSubscriptionTask *task=[self beginSubscriptionTask];
    if (!task) return;
    NSArray *baseConfigs=[_configs copy],*baseSubscriptions=[_subscriptions copy];
    NSUInteger revision=_configurationRevision;
    NSArray *inputs=[[NSArray alloc] initWithArray:texts ?: @[] copyItems:YES];
    NSString *input=[inputs count] ? [inputs objectAtIndex:0] : nil,*filePath=[path copy];
    [task setPhase:@"Reading import data"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        VCSubscriptionTask *previous=[VCSetCurrentSubscriptionTask(task) retain];
        @try {
            NSString *failure=nil,*decoded=input;
            NSArray *karingEntries=nil,*links=nil;
            NSDictionary *report=nil;
            NSData *data=separate ? nil : filePath ? VCReadSubscriptionFile(filePath,&failure) : [input dataUsingEncoding:NSUTF8StringEncoding];
            if ([data length] > kVCMaximumSubscriptionBytes) failure=@"Import data exceeds 32 MiB";
            if (separate) {
                report=[VCProfiles() textImportReportFromTexts:inputs]; links=[report objectForKey:@"uris"];
                failure=[report objectForKey:@"error"];
            } else if (!failure && VCKaringBackupDataLooksLikeZip(data)) karingEntries=VCKaringSubscriptionsFromBackupData(data,&failure);
            else if (!failure) {
                if (!decoded) decoded=[self decodeImportTextData:data];
                decoded=[self safeTrim:decoded];
                if (![decoded length]) failure=@"Import data is empty or has unsupported encoding";
                else {
                    report=[VCProfiles() textImportReportFromText:decoded];
                    links=[report objectForKey:@"uris"];
                }
                if ([report objectForKey:@"error"]) failure=[report objectForKey:@"error"];
            }
            NSMutableArray *draft=[NSMutableArray arrayWithArray:baseConfigs],*urls=[NSMutableArray array],*issues=[NSMutableArray array];
            NSMutableSet *seen=[NSMutableSet set],*seenURLs=[NSMutableSet set];
            for (NSDictionary *config in baseConfigs) if ([config objectForKey:@"uri"]) [seen addObject:[config objectForKey:@"uri"]];
            for (NSDictionary *sub in baseSubscriptions) if ([sub objectForKey:@"url"]) [seenURLs addObject:[sub objectForKey:@"url"]];
            NSUInteger skipped=[[report objectForKey:@"skipped"] unsignedIntegerValue],accepted=0,processed=0;
            if ([report objectForKey:@"issues"]) [issues addObjectsFromArray:[report objectForKey:@"issues"]];
            [task profileMetadataPrepared:[report objectForKey:@"metadata"]];
            [task setPhase:@"Processing"];
            for (NSString *link in links) {
                if (failure || task.isCancelled) break;
                NSAutoreleasePool *entryPool=[[NSAutoreleasePool alloc] init];
                NSString *uri=link,*queued=link,*reason=nil;
                BOOL happ=[self isHappEncryptedLink:link] || [self isHappAddLink:link];
                if ([self isHappEncryptedLink:link]) uri=[self decryptedHappLink:link errorText:&reason];
                else if ([self isHappAddLink:link]) uri=[self targetFromHappAddLink:link];
                if ([self isDirectConfigURI:uri]) {
                    NSDictionary *metadata=[[report objectForKey:@"metadata"] objectForKey:uri] ?: [VCProfiles() metadataForURI:uri];
                    reason=[metadata objectForKey:@"reason"];
                    if (!reason && ![seen containsObject:uri]) {
                        NSString *name=[metadata objectForKey:@"title"] ?: [NSString stringWithFormat:@"Config %lu (%@)",(unsigned long)[draft count]+1,[metadata objectForKey:@"host"] ?: @"server"];
                        [draft addObject:@{@"name":name,@"uri":uri}]; [seen addObject:uri]; accepted++;
                        [task profileMetadataPrepared:@{uri:metadata}];
                    } else if (!reason) [task recordDuplicate];
                } else if ([self isSubscriptionURL:uri] || VCIncyIsCryptLink(uri)) {
                    if (!happ) queued=uri;
                    if (![seenURLs containsObject:uri]) { [urls addObject:queued]; [seenURLs addObject:uri]; }
                    else [task recordDuplicate];
                } else reason=@"Invalid or unsupported import link";
                if (reason) { skipped++; if ([issues count] < 16) [issues addObject:@"Invalid or unsupported profile settings"]; }
                [task processed:++processed total:[links count]];
                [entryPool drain];
            }
            if (!report) [task addAccepted:accepted skipped:skipped];
            else [task addAccepted:0 skipped:skipped-[[report objectForKey:@"skipped"] unsignedIntegerValue]];
            NSDictionary *warnings=@{@"skipped":@(skipped),@"issues":issues};
            dispatch_async(dispatch_get_main_queue(), ^{
                if (task != _subscriptionTask || task.isCancelled || revision != _configurationRevision || failure) {
                    if (_photoQRQueue && !task.isCancelled) _photoQRFailures++;
                    if (failure) [self showStatus:failure ok:NO];
                    else if (!task.isCancelled) [self showStatus:@"Import skipped: configurations changed" ok:NO];
                    [self finishSubscriptionTask:task success:NO]; return;
                }
                if (karingEntries) {
                    NSDictionary *metadata=[[task takePreparedMetadata] retain];
                    [self finishSubscriptionTask:task success:NO];
                    [self profileMetadataPrepared:metadata]; [metadata release];
                    [self importKaringSubscriptionEntries:karingEntries]; return;
                }
                void (^finish)(BOOL)=^(BOOL saved) {
                    if (!saved && _photoQRQueue && !task.isCancelled) _photoQRFailures++;
                    if (saved && accepted) {
                        _configurationsSectionExpanded=YES; _subscriptionsSectionExpanded=NO;
                        _selectedConfigIndex=[_configs count]-1; _selectedSubIndex=_selectedSubItemIndex=-1;
                        [self normalizeSelection]; [self saveMainState]; [_tableView reloadData];
                    }
                    if (saved) {
                        if (accepted || ![urls count]) [self showStatus:accepted ? [NSString stringWithFormat:@"Imported %lu configurations",(unsigned long)accepted] : @"No new supported configurations" ok:accepted > 0];
                        [self showProfileImportWarnings:@[warnings]];
                    }
                    [self finishSubscriptionTask:task success:saved];
                    if (saved && [urls count]) [self startBackgroundSubscriptionImportForURLs:urls allowInsecureFetch:NO];
                };
                if (accepted) [self commitConfigurations:draft subscriptions:_subscriptions completion:finish];
                else finish(YES);
            });
        } @finally {
            VCSetCurrentSubscriptionTask(previous); [previous release];
            [baseConfigs release]; [baseSubscriptions release]; [inputs release]; [filePath release]; [pool drain];
        }
    });
}

@end
