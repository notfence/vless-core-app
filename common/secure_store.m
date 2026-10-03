#import "secure_store.h"
#import "foundation_logic.h"
#import "app_constants.h"
#include <openssl/crypto.h>
#include <stdint.h>
#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

VCConfigurationDataSelection VCInitialConfigurationData(NSDictionary *protectedData, BOOL secureFileExists, id legacyConfigs, id legacySubscriptions, BOOL writable) {
    NSArray *cfg = [protectedData objectForKey:@"configs"];
    NSArray *subs = [protectedData objectForKey:@"subscriptions"];
    if (![protectedData isKindOfClass:[NSDictionary class]]) {
        cfg = [legacyConfigs isKindOfClass:[NSArray class]] ? legacyConfigs : nil;
        subs = [legacySubscriptions isKindOfClass:[NSArray class]] ? legacySubscriptions : nil;
        if (secureFileExists && cfg == nil && subs == nil) writable = NO;
    }
    VCConfigurationDataSelection selection = {cfg, subs, writable};
    return selection;
}

BOOL VCWriteAllToFileDescriptor(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = (const uint8_t *)bytes;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        cursor += (size_t)written;
        length -= (size_t)written;
    }
    return YES;
}

BOOL VCEnsureSecureStoreDirectoryAtPaths(const VCStoragePaths *paths) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0700]
                                                             forKey:NSFilePosixPermissions];
    if (![manager createDirectoryAtPath:paths->directory
            withIntermediateDirectories:YES
                             attributes:attributes
                                  error:nil]) {
        return NO;
    }

    struct stat st;
    const char *path = [paths->directory fileSystemRepresentation];
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != geteuid()) return NO;
    return chmod(path, 0700) == 0;
}

NSData *VCReadSecureStoreFileAtPaths(BOOL *existsOut, const VCStoragePaths *paths) {
    if (existsOut) *existsOut = NO;
    const char *path = [paths->file fileSystemRepresentation];
    struct stat before;
    if (lstat(path, &before) != 0) return nil;
    if (existsOut) *existsOut = YES;
    if (!S_ISREG(before.st_mode) || S_ISLNK(before.st_mode) || before.st_uid != geteuid() || before.st_nlink != 1 ||
        before.st_size < 0 || (uint64_t)before.st_size > kVCSecureStoreMaximumBytes) {
        return nil;
    }

    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return nil;
    struct stat after;
    if (fstat(fd, &after) != 0 || !S_ISREG(after.st_mode) || after.st_uid != geteuid() || after.st_nlink != 1 ||
        after.st_dev != before.st_dev || after.st_ino != before.st_ino || after.st_size != before.st_size) {
        close(fd);
        return nil;
    }
    if ((after.st_mode & 0077) != 0 && fchmod(fd, 0600) != 0) {
        close(fd);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)after.st_size];
    uint8_t *output = (uint8_t *)[data mutableBytes];
    size_t remaining = (size_t)after.st_size;
    while (remaining > 0) {
        ssize_t count = read(fd, output, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            close(fd);
            return nil;
        }
        output += (size_t)count;
        remaining -= (size_t)count;
    }
    close(fd);
    return data;
}

BOOL VCWriteSecureStoreFileAtPaths(NSData *data, const VCStoragePaths *paths) {
    if (![data isKindOfClass:[NSData class]] || [data length] == 0 || [data length] > kVCSecureStoreMaximumBytes ||
        !VCEnsureSecureStoreDirectoryAtPaths(paths)) {
        return NO;
    }

    char temporary[PATH_MAX];
    int length = snprintf(temporary, sizeof(temporary), "%s/configs.dat.tmp.XXXXXX",
                          [paths->directory fileSystemRepresentation]);
    if (length <= 0 || (size_t)length >= sizeof(temporary)) return NO;
    int fd = mkstemp(temporary);
    if (fd < 0) return NO;

    BOOL ok = fchmod(fd, 0600) == 0 && VCWriteAllToFileDescriptor(fd, [data bytes], [data length]) && fsync(fd) == 0;
    if (close(fd) != 0) ok = NO;
    NSString *temporaryPath = [NSString stringWithUTF8String:temporary];
    if (ok) ok = temporaryPath != nil;
    if (ok) ok = paths->protectFile(temporaryPath);
    if (ok) ok = rename(temporary, [paths->file fileSystemRepresentation]) == 0;
    if (!ok) {
        unlink(temporary);
        return NO;
    }
    int directoryFD = open([paths->directory fileSystemRepresentation], O_RDONLY | O_NOFOLLOW);
    if (directoryFD >= 0) {
        (void)fsync(directoryFD);
        close(directoryFD);
    }
    return YES;
}

BOOL VCLoadSecureStoreKeyAtPaths(unsigned char key[32], BOOL createIfMissing, const VCStoragePaths *paths) {
    NSString *response = paths->sendCommand(createIfMissing ? @"STORE_KEY\tCREATE\n" : @"STORE_KEY\tGET\n");
    if (![response hasPrefix:@"OK "]) return NO;
    NSString *hex = [response substringFromIndex:3];
    hex = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hex length] != kVCSecureStoreKeyLength * 2) return NO;
    for (NSUInteger i = 0; i < kVCSecureStoreKeyLength; i++) {
        unichar high = [hex characterAtIndex:i * 2];
        unichar low = [hex characterAtIndex:i * 2 + 1];
        if (!VCIsASCIIHexDigit(high) || !VCIsASCIIHexDigit(low)) return NO;
        int highValue = high >= '0' && high <= '9' ? (int)(high - '0') : (int)((high | 0x20) - 'a' + 10);
        int lowValue = low >= '0' && low <= '9' ? (int)(low - '0') : (int)((low | 0x20) - 'a' + 10);
        key[i] = (unsigned char)((highValue << 4) | lowValue);
    }
    return YES;
}

BOOL VCSaveProtectedConfigurationDataAtPaths(NSArray *configs, NSArray *subscriptions, const VCStoragePaths *paths) {
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             configs ? configs : [NSArray array], @"configs",
                             subscriptions ? subscriptions : [NSArray array], @"subscriptions",
                             nil];
    NSString *serializationError = nil;
    NSData *plaintext = [NSPropertyListSerialization dataFromPropertyList:payload
                                                                    format:NSPropertyListBinaryFormat_v1_0
                                                          errorDescription:&serializationError];
    [serializationError release];
    if (!plaintext) return NO;

    unsigned char key[32];
    if (!VCLoadSecureStoreKeyAtPaths(key, YES, paths)) return NO;
    NSData *encrypted = VCEncryptSecureStorePayload(plaintext, key);
    OPENSSL_cleanse(key, sizeof(key));
    return encrypted != nil && VCWriteSecureStoreFileAtPaths(encrypted, paths);
}

NSDictionary *VCLoadProtectedConfigurationDataAtPaths(BOOL *fileExistsOut, const VCStoragePaths *paths) {
    NSData *encrypted = VCReadSecureStoreFileAtPaths(fileExistsOut, paths);
    if (!encrypted) return nil;
    unsigned char key[32];
    if (!VCLoadSecureStoreKeyAtPaths(key, NO, paths)) return nil;
    NSData *plaintext = VCDecryptSecureStorePayload(encrypted, key);
    OPENSSL_cleanse(key, sizeof(key));
    if (!plaintext) return nil;

    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    NSString *serializationError = nil;
    id payload = [NSPropertyListSerialization propertyListFromData:plaintext
                                                   mutabilityOption:NSPropertyListImmutable
                                                             format:&format
                                                   errorDescription:&serializationError];
    [serializationError release];
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *configs = [payload objectForKey:@"configs"];
    NSArray *subscriptions = [payload objectForKey:@"subscriptions"];
    if (![configs isKindOfClass:[NSArray class]] || ![subscriptions isKindOfClass:[NSArray class]]) return nil;
    return payload;
}

BOOL VCOpenDiagnosticEventDatabaseAtPaths(sqlite3 **databaseOut, const VCStoragePaths *paths) {
    if (!databaseOut || !VCEnsureSecureStoreDirectoryAtPaths(paths)) return NO;
    *databaseOut = NULL;
    struct stat existing;
    const char *path = [paths->database fileSystemRepresentation];
    if (lstat(path, &existing) == 0 &&
        (!S_ISREG(existing.st_mode) || S_ISLNK(existing.st_mode) ||
         existing.st_uid != geteuid() || existing.st_nlink != 1)) return NO;
    int rc = sqlite3_open_v2([paths->database fileSystemRepresentation],
                             databaseOut,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                             NULL);
    if (rc != SQLITE_OK || !*databaseOut) {
        if (*databaseOut) sqlite3_close(*databaseOut);
        *databaseOut = NULL;
        return NO;
    }
    sqlite3_busy_timeout(*databaseOut, 1000);
    const char *setup =
        "PRAGMA journal_mode=DELETE;"
        "PRAGMA synchronous=NORMAL;"
        "PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS events ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "timestamp INTEGER NOT NULL,"
        "category TEXT NOT NULL,"
        "action TEXT NOT NULL,"
        "detail TEXT"
        ");";
    if (sqlite3_exec(*databaseOut, setup, NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_close(*databaseOut);
        *databaseOut = NULL;
        return NO;
    }
    (void)chmod([paths->database fileSystemRepresentation], 0600);
    return YES;
}

NSArray *VCLoadDiagnosticEventDatabaseAtPaths(const VCStoragePaths *paths) {
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabaseAtPaths(&database, paths)) return [NSArray array];
    const char *query =
        "SELECT timestamp, category, action, detail FROM ("
        "SELECT id, timestamp, category, action, detail "
        "FROM events ORDER BY id DESC LIMIT 250"
        ") ORDER BY id ASC;";
    sqlite3_stmt *statement = NULL;
    NSMutableArray *events = [NSMutableArray array];
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const unsigned char *categoryBytes = sqlite3_column_text(statement, 1);
            const unsigned char *actionBytes = sqlite3_column_text(statement, 2);
            const unsigned char *detailBytes = sqlite3_column_text(statement, 3);
            NSString *category = categoryBytes ? [NSString stringWithUTF8String:(const char *)categoryBytes] : nil;
            NSString *action = actionBytes ? [NSString stringWithUTF8String:(const char *)actionBytes] : nil;
            NSString *detail = detailBytes ? [NSString stringWithUTF8String:(const char *)detailBytes] : nil;
            NSDictionary *event = VCMakeAppDiagnosticEvent(sqlite3_column_int64(statement, 0),
                                                           category,
                                                           action,
                                                           detail);
            if (event) [events addObject:event];
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
    return events;
}

BOOL VCInsertDiagnosticEventBatchAtPaths(NSArray *events, const VCStoragePaths *paths) {
    if (![events isKindOfClass:[NSArray class]] || [events count] == 0) return YES;
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabaseAtPaths(&database, paths)) return NO;
    BOOL ok = sqlite3_exec(database, "BEGIN IMMEDIATE;", NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_stmt *statement = NULL;
    const char *insert = "INSERT INTO events(timestamp, category, action, detail) VALUES(?, ?, ?, ?);";
    if (ok) ok = sqlite3_prepare_v2(database, insert, -1, &statement, NULL) == SQLITE_OK;
    for (NSDictionary *candidate in events) {
        if (!ok) break;
        NSDictionary *event = VCMakeAppDiagnosticEvent(
            [[candidate objectForKey:@"timestamp"] longLongValue],
            [candidate objectForKey:@"category"],
            [candidate objectForKey:@"action"],
            [candidate objectForKey:@"detail"]);
        if (!event) continue;
        NSString *detail = [event objectForKey:@"detail"];
        sqlite3_bind_int64(statement, 1, [[event objectForKey:@"timestamp"] longLongValue]);
        sqlite3_bind_text(statement, 2, [[event objectForKey:@"category"] UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, [[event objectForKey:@"action"] UTF8String], -1, SQLITE_TRANSIENT);
        if ([detail length] > 0) sqlite3_bind_text(statement, 4, [detail UTF8String], -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(statement, 4);
        ok = sqlite3_step(statement) == SQLITE_DONE;
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
    }
    if (statement) sqlite3_finalize(statement);
    if (ok) {
        ok = sqlite3_exec(database,
                          "DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 250);",
                          NULL, NULL, NULL) == SQLITE_OK;
    }
    if (ok) ok = sqlite3_exec(database, "COMMIT;", NULL, NULL, NULL) == SQLITE_OK;
    else sqlite3_exec(database, "ROLLBACK;", NULL, NULL, NULL);
    sqlite3_close(database);
    return ok;
}

void VCClearDiagnosticEventDatabaseAtPaths(const VCStoragePaths *paths) {
    sqlite3 *database = NULL;
    if (VCOpenDiagnosticEventDatabaseAtPaths(&database, paths)) {
        sqlite3_exec(database, "DELETE FROM events;", NULL, NULL, NULL);
        sqlite3_exec(database, "DELETE FROM sqlite_sequence WHERE name='events';", NULL, NULL, NULL);
        sqlite3_exec(database, "VACUUM;", NULL, NULL, NULL);
        sqlite3_close(database);
    }
}

void VCPurgeOptionalDiagnosticEventsAtPaths(const VCStoragePaths *paths) {
    sqlite3 *database = NULL;
    if (!VCOpenDiagnosticEventDatabaseAtPaths(&database, paths)) return;
    sqlite3_exec(database,
                 "DELETE FROM events "
                 "WHERE category NOT IN ('connection','diagnostics','ping') "
                 "AND NOT (category='subscription' AND action LIKE '%update%');",
                 NULL, NULL, NULL);
    sqlite3_close(database);
}
