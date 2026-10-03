#import "import_browser.h"

@implementation VCImportBrowserVC

- (id)initWithRootPath:(NSString *)rootPath
         directoryPath:(NSString *)directoryPath
              delegate:(id<VCImportBrowserDelegate>)delegate {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _browserDelegate = delegate;
        _rootPath = [[rootPath stringByStandardizingPath] copy];
        _directoryPath = [[directoryPath stringByStandardizingPath] copy];
    }
    return self;
}

- (BOOL)pathIsInsideImportDirectory:(NSString *)path {
    return VCImportPathIsInsideRoot(_rootPath, path);
}

- (void)reloadEntries {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directoryPath error:nil];
    NSMutableArray *directories = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];

    for (id object in names) {
        if (![object isKindOfClass:[NSString class]]) continue;
        NSString *name = (NSString *)object;
        if ([name length] == 0 || [name hasPrefix:@"."]) continue;

        NSString *path = [_directoryPath stringByAppendingPathComponent:name];
        if (![self pathIsInsideImportDirectory:path]) continue;

        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) continue;
        NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                               name, @"name",
                               path, @"path",
                               [NSNumber numberWithBool:isDirectory], @"is_directory",
                               nil];
        [(isDirectory ? directories : files) addObject:entry];
    }

    NSComparator comparator = ^NSComparisonResult(id left, id right) {
        return [[left objectForKey:@"name"] localizedCaseInsensitiveCompare:[right objectForKey:@"name"]];
    };
    [directories sortUsingComparator:comparator];
    [files sortUsingComparator:comparator];

    NSMutableArray *all = [NSMutableArray arrayWithArray:directories];
    [all addObjectsFromArray:files];
    [_entries release];
    _entries = [all copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [_directoryPath isEqualToString:_rootPath]
        ? @"Import Files"
        : [_directoryPath lastPathComponent];
    self.view.backgroundColor = VCBackgroundColor();
    self.tableView.backgroundColor = VCBackgroundColor();
    self.tableView.separatorColor = VCSeparatorColor();

    if ([_directoryPath isEqualToString:_rootPath]) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(cancelPressed)] autorelease];

        UILabel *hint = [[[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.view.bounds.size.width, 62.0f)] autorelease];
        hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        hint.backgroundColor = VCBackgroundColor();
        hint.textColor = VCSecondaryTextColor();
        hint.font = [UIFont systemFontOfSize:13.0f];
        hint.textAlignment = NSTextAlignmentCenter;
        hint.numberOfLines = 2;
        hint.text = @"Copy configuration or backup files to\n/var/mobile/vless-core-import";
        self.tableView.tableHeaderView = hint;
    }

    [self reloadEntries];
}

- (void)cancelPressed {
    if ([_browserDelegate respondsToSelector:@selector(importBrowserDidCancel:)]) {
        [_browserDelegate importBrowserDidCancel:self];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return MAX((NSInteger)[_entries count], 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"ImportFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    }

    cell.backgroundColor = VCCellBackgroundColor();
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if ([_entries count] == 0) {
        cell.textLabel.text = @"No files found";
        cell.detailTextLabel.text = @"Copy a file to the import directory, then reopen this screen.";
        cell.textLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
    BOOL isDirectory = [[entry objectForKey:@"is_directory"] boolValue];
    cell.textLabel.text = [entry objectForKey:@"name"];
    cell.detailTextLabel.text = isDirectory ? @"Folder" : @"Tap to import";
    cell.accessoryType = isDirectory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_entries count]) return;

    NSDictionary *entry = [_entries objectAtIndex:indexPath.row];
    NSString *path = [entry objectForKey:@"path"];
    if ([[entry objectForKey:@"is_directory"] boolValue]) {
        VCImportBrowserVC *child = [[[VCImportBrowserVC alloc] initWithRootPath:_rootPath
                                                                  directoryPath:path
                                                                       delegate:_browserDelegate] autorelease];
        [self.navigationController pushViewController:child animated:YES];
    } else if ([_browserDelegate respondsToSelector:@selector(importBrowser:didSelectFileAtPath:)]) {
        [_browserDelegate importBrowser:self didSelectFileAtPath:path];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    _browserDelegate = nil;
    [_rootPath release];
    [_directoryPath release];
    [_entries release];
    [super dealloc];
}

@end
