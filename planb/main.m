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

@import IOKit.pwr_mgt;
@import Foundation;

#include "roots.pem.h"

#import "PBLogging.h"
#import "PBManifest.h"
#import "PBPackageInstaller.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

static NSString * const kBaseURL = @"https://mac.internal.megacorp.com/pkgs/";
static NSString * const kManifestURL = @"https://mac.internal.megacorp.com/manifest";
static NSString * const kMachineInfo = @"/Library/Preferences/com.megacorp.machineinfo.plist";
static NSString * const kMachineInfoKey = @"ConfigurationTrack";
static NSString * const kAssertionName = @"planb";

/**
  Return the list of hard-coded packages to install, along with their receipt names, and
  optional SHA-256 checksums to be verified.
*/
NSArray* StaticPackages() {
  return @[
      @[ @"pkg1/package1", @"com.megacorp.package1" ],
      @[ @"pkg2/package2", @"com.megacorp.package2" ],
      @[ @"pkg3/package3", @"com.megacorp.package3" ],
  ];
}

/**
  Return the machine's track, read from the property list specified above. Defaults to "stable".
 */
NSString *MachineTrack() {
  static dispatch_once_t onceToken;
  static NSString *track;

  dispatch_once(&onceToken, ^{
    NSDictionary *machineInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:kMachineInfo];
    track = [[machineInfoDictionary objectForKey:kMachineInfoKey] lowercaseString];
    if (!track.length) track = @"stable";
  });

  return track;
}

/**
  Create URL for a resource to download, by combining:
    * The base URL above
    * The path provided as an argument
    * The machine's track, read from the property list specified above. Defaults to "stable"
    * The suffix '.dmg'.

  E.g. using the default parameters above with the parameter 'pkg1/sample' the URL would be:
  https://mac.internal.megacorp.com/pkgbase/pkg1/sample-stable.dmg
*/
NSString* StringURLForPackagePath(NSString *pkg) {
  NSString *path = [NSString stringWithFormat:@"%@-%@.dmg", pkg, MachineTrack()];
  NSURL *url = [NSURL URLWithString:path relativeToURL:[NSURL URLWithString:kBaseURL]];
  return [url absoluteString];
}

/**
 Return the list of packages to install, both static and from a downloaded manifest.
 */
NSArray* Packages(NSURLSession *session) {
  NSMutableArray *result = [NSMutableArray array];

  for (NSArray *item in StaticPackages()) {
    NSMutableArray *newItem = [NSMutableArray arrayWithArray:item];
    newItem[0] = StringURLForPackagePath(item[0]);
    [result addObject:newItem];
  }

  if (kManifestURL.length) {
    PBManifest *manifest = [[PBManifest alloc] initWithURL:[NSURL URLWithString:kManifestURL]];
    if (session) manifest.session = session;
    [manifest downloadManifest];
    [result addObjectsFromArray:[manifest packagesForTrack:MachineTrack()]];
  }

  return result;
}

/**
  Create a power assertion to stop the system from idle sleeping while planb is running.
  The assertion will automatically free when planb exits.
*/
void CreatePowerAssertion() {
  IOPMAssertionID assertionID;
  IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
                              kIOPMAssertionLevelOn,
                              (__bridge CFStringRef)kAssertionName,
                              &assertionID);
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (getuid() != 0) {
      PBLog(@"%@ must be run as root!", [[NSProcessInfo processInfo] processName]);
      exit(99);
    }

    PBLog(@"Starting %@", [[NSProcessInfo processInfo] processName]);
    CreatePowerAssertion();

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.URLCache = nil;

    if (![[[NSProcessInfo processInfo] arguments] containsObject:@"--use-proxy"]) {
      config.connectionProxyDictionary = @{
          (__bridge NSString *)kCFNetworkProxiesHTTPSEnable: @NO
      };
    }

    MOLAuthenticatingURLSession *authURLSession =
        [[MOLAuthenticatingURLSession alloc] initWithSessionConfiguration:config];

    authURLSession.serverRootsPemData = [NSData dataWithBytes:ROOTS_PEM length:ROOTS_PEM_len];
    authURLSession.refusesRedirects = YES;
    authURLSession.loggingBlock = ^(NSString *line) {
      PBLog(@"Session: %@", line);
    };

    __block BOOL success = YES;
    NSArray *packages = Packages(authURLSession.session);
    [packages enumerateObjectsUsingBlock:^(NSArray* obj, NSUInteger idx, BOOL *stop) {
      NSString *packagePath = obj[0];
      NSString *receiptName = obj[1];
      NSString *checksum = obj.count >= 3 ? obj[2] : nil;

      PBPackageInstaller *pkgInstaller =
          [[PBPackageInstaller alloc] initWithURL:[NSURL URLWithString:packagePath]
                                      receiptName:receiptName
                                         checksum:checksum];
      pkgInstaller.logPrefix =
          [NSString stringWithFormat:@"[%lu/%lu %@]",
              (unsigned long)idx + 1, (unsigned long)packages.count, receiptName];
      authURLSession.loggingBlock = ^(NSString *line) {
        PBLog(@"%@ %@", pkgInstaller.logPrefix, line);
      };
      pkgInstaller.session = authURLSession.session;
      success &= [pkgInstaller install];
    }];

    return !success;
  }
}
