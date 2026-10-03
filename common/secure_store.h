#ifndef VC_SECURE_STORE_H
#define VC_SECURE_STORE_H
#import <Foundation/Foundation.h>
#include <sqlite3.h>

typedef struct {
    NSString *directory;
    NSString *file;
    NSString *database;
    NSString *(*sendCommand)(NSString *);
    BOOL (*protectFile)(NSString *);
} VCStoragePaths;
typedef struct {
    NSArray *configs;
    NSArray *subscriptions;
    BOOL writable;
} VCConfigurationDataSelection;
VCConfigurationDataSelection VCInitialConfigurationData(NSDictionary *protectedData, BOOL secureFileExists, id legacyConfigs, id legacySubscriptions, BOOL writable);

BOOL VCWriteAllToFileDescriptor(int fd, const void *bytes, size_t length);
BOOL VCEnsureSecureStoreDirectoryAtPaths(const VCStoragePaths *paths);
NSData *VCReadSecureStoreFileAtPaths(BOOL *existsOut, const VCStoragePaths *paths);
BOOL VCWriteSecureStoreFileAtPaths(NSData *data, const VCStoragePaths *paths);
BOOL VCLoadSecureStoreKeyAtPaths(unsigned char key[32], BOOL createIfMissing, const VCStoragePaths *paths);
BOOL VCSaveProtectedConfigurationDataAtPaths(NSArray *configs, NSArray *subscriptions, const VCStoragePaths *paths);
NSDictionary *VCLoadProtectedConfigurationDataAtPaths(BOOL *fileExistsOut, const VCStoragePaths *paths);
BOOL VCOpenDiagnosticEventDatabaseAtPaths(sqlite3 **databaseOut, const VCStoragePaths *paths);
NSArray *VCLoadDiagnosticEventDatabaseAtPaths(const VCStoragePaths *paths);
BOOL VCInsertDiagnosticEventBatchAtPaths(NSArray *events, const VCStoragePaths *paths);
void VCClearDiagnosticEventDatabaseAtPaths(const VCStoragePaths *paths);
void VCPurgeOptionalDiagnosticEventsAtPaths(const VCStoragePaths *paths);
#endif
