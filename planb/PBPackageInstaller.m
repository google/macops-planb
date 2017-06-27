/*
  Copyright 2016 Google Inc.

  Licensed under the Apache License, Version 2.0 (the "License"); you may not
  use this file except in compliance with the License.  You may obtain a copy
  of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
  License for the specific language governing permissions and limitations under
  the License.
*/

@import Foundation;

#import <CommonCrypto/CommonDigest.h>

#import "PBCommandController.h"
#import "PBLogging.h"
#import "PBPackageInstaller.h"

static NSString *const kHdiutilPath = @"/usr/bin/hdiutil";
static NSString *const kInstallerPath = @"/usr/sbin/installer";
static NSString *const kPkgutilPath = @"/usr/sbin/pkgutil";

@interface PBPackageInstaller ()

/// Package receipt name, e.g. 'com.megacorp.corp.pkg'.
@property(readonly, nonatomic, copy) NSString *receiptName;

/// The URL to downlaod the package from.
@property(readonly, nonatomic, copy) NSURL *packageURL;

/// Path to mounted disk image, e.g. '/tmp/planb-pkg.duc3eP'.
@property(readonly, nonatomic, copy) NSString *mountPoint;

@end

@implementation PBPackageInstaller

- (instancetype)initWithURL:(NSURL *)packageURL
                receiptName:(NSString *)receipt {
  self = [super init];

  if (self) {
    if (!receipt.length || !packageURL.absoluteString.length) {
      return nil;
    }

    _receiptName = [receipt copy];
    _packageURL = [packageURL copy];
    _mountPoint = [self generateMountPoint];

    _downloadAttemptsMax = 5;
    _downloadTimeoutSeconds = 300;
    _session = [NSURLSession sharedSession];
  }

  return self;
}

- (void)dealloc {
  if (self.mountPoint) {
    NSError *err;
    [[NSFileManager defaultManager] removeItemAtPath:self.mountPoint error:&err];
    if (err) {
      [self log:@"Error: could not delete temporary mount point %@: %@",
          self.mountPoint, err.localizedDescription];
    }
  }
}

- (BOOL)install {
  NSString *path = [self downloadPackage];
  if (!path) return NO;

  BOOL success = [self diskImageAttach:path];
  if (!success) return NO;

  [self log:@"Mounted at %@", self.mountPoint];

  // We don't care if this works or not.
  [self forgetPackageWithName:self.receiptName];

  // TODO(rah): Add ability to install to a different volume.
  success = [self installPackageFromLocation:[self firstPackageOnImage] toVolume:@"/"];
  if (success) {
    [self log:@"Install complete"];
  }

  // Success is not tied to whether detaching succeeded.
  [self diskImageDetach];

  return success;
}

#pragma mark Helper Methods

- (NSString *)firstPackageOnImage {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *fmError;
  NSArray *dirContents = [fm contentsOfDirectoryAtPath:self.mountPoint error:&fmError];
  if (!dirContents) {
    [self log:@"Error: could not determine package path: %@", fmError];
    return nil;
  }

  NSPredicate *filterPKGs = [NSPredicate predicateWithFormat:@"self ENDSWITH '.pkg'"];
  NSArray *onlyPKGs = [dirContents filteredArrayUsingPredicate:filterPKGs];
  return [onlyPKGs firstObject];
}

- (NSString *)generateMountPoint {
  char tmpdir[] = "/tmp/planb-pkg.XXXXXX";
  if (!mkdtemp(tmpdir)) {
    [self log:@"Error: could not create temporary installation directory %s.", tmpdir];
    return nil;
  }
  return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tmpdir
                                                                     length:strlen(tmpdir)];
}

- (NSString *)downloadPackage {
  __block NSString *path;  // path of downloaded package file
  __block NSString *errorDescription;

  for (NSUInteger i = 1; i <= self.downloadAttemptsMax; ++i) {
    [self log:@"Downloading, attempt %tu/%tu", i, self.downloadAttemptsMax];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[self.session downloadTaskWithURL:self.packageURL completionHandler:^(NSURL *location,
                                                                           NSURLResponse *response,
                                                                           NSError *error) {
      if (((NSHTTPURLResponse *)response).statusCode == 200) {
        path = location.path;
      } else {
        errorDescription = error.localizedDescription;
      }
      dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW,
                                                self.downloadTimeoutSeconds * NSEC_PER_SEC));

    if (path) {
      [self log:@"Download complete, SHA-1: %@", [self SHA1ForFileAtPath:path]];
      break;
    } else if (errorDescription) {
      [self log:@"Download failed: %@", errorDescription];
    }
  }

  return path;
}

- (BOOL)diskImageAttach:(NSString *)path {
  PBCommandController *t = [[PBCommandController alloc] init];
  t.launchPath = kHdiutilPath;
  t.arguments = @[ @"attach",
                   path,
                   @"-nobrowse",
                   @"-readonly",
                   @"-mountpoint",
                   self.mountPoint ];
  t.timeout = 30;
  return [t launchWithOutput:NULL] == 0;
}

- (BOOL)diskImageDetach {
  PBCommandController *t = [[PBCommandController alloc] init];
  t.launchPath = kHdiutilPath;
  t.arguments = @[ @"detach", @"-force", self.mountPoint ];
  t.timeout = 30;
  return [t launchWithOutput:NULL] == 0;
}

- (BOOL)installPackageFromLocation:(NSString *)location toVolume:(NSString *)volume {
  if (location.pathComponents.count != 1) {
    [self log:@"Error: %@ is not a direct subpath", location];
    return NO;
  }

  NSString *packageLocation = [self.mountPoint stringByAppendingPathComponent:location];
  [self log:@"Attempting to install %@ to %@", packageLocation, volume];

  PBCommandController *t = [[PBCommandController alloc] init];
  t.launchPath = kInstallerPath;
  t.arguments = @[ @"-pkg", packageLocation, @"-tgt", volume ];
  t.timeout = (60 * 5);  // some packages take a while, especially if they have postflight scripts.

  NSString *output;
  if ([t launchWithOutput:&output] != 0) {
    [self log:@"Error: failed to install %@: %@", location, output];
    return NO;
  }
  return YES;
}

- (void)forgetPackageWithName:(NSString *)packageReceipt {
  PBCommandController *t = [[PBCommandController alloc] init];
  t.launchPath = kPkgutilPath;
  t.arguments = @[ @"--forget", packageReceipt ];
  t.timeout = 10;
  [t launchWithOutput:NULL];
}

- (NSString *)SHA1ForFileAtPath:(NSString *)path {
  unsigned char sha1[CC_SHA1_DIGEST_LENGTH];
  NSData *fileData = [NSData dataWithContentsOfFile:path
                                            options:NSDataReadingMappedIfSafe
                                              error:nil];

  CC_SHA1(fileData.bytes, (CC_LONG)fileData.length, sha1);
  NSMutableString *buf = [[NSMutableString alloc] initWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];

  for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
    [buf appendFormat:@"%02x", sha1[i]];
  }

  return buf;
}

- (void)log:(NSString *)fmt, ... NS_FORMAT_FUNCTION(1,2) {
  va_list ap;
  va_start(ap, fmt);
  NSString *formatted = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);

  PBLog(@"%@ %@", self.logPrefix, formatted);
}

@end

