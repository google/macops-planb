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
#import "PBPackageInstaller.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

static NSString * const kBaseURL = @"https://mac.internal.megacorp.com/pkgs/";
static NSString * const kMachineInfo = @"/Library/Preferences/com.megacorp.machineinfo.plist";
static NSString * const kMachineInfoKey = @"ConfigurationTrack";
static NSString * const kAssertionName = @"planb";

/**
  Return the list of packages to install, along with their receipt names.
*/
NSArray* Packages() {
  return @[
      @[ @"pkg1/package1", @"com.megacorp.package1" ],
      @[ @"pkg2/package2", @"com.megacorp.package2" ],
      @[ @"pkg3/package3", @"com.megacorp.package3" ],
  ];
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
NSURL* URLForPackagePath(NSString *pkg) {
  static dispatch_once_t onceToken;
  static NSString *track;

  dispatch_once(&onceToken, ^{
    NSDictionary *machineInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:kMachineInfo];
    track = [[machineInfoDictionary objectForKey:kMachineInfoKey] lowercaseString];
    if (!track.length) track = @"stable";
  });

  NSString *path = [NSString stringWithFormat:@"%@-%@.dmg", pkg, track];
  return [NSURL URLWithString:path relativeToURL:[NSURL URLWithString:kBaseURL]];
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
    NSArray *packages = Packages();
    [packages enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      NSString *packagePath = [obj firstObject];
      NSString *receiptName = [obj lastObject];

      PBPackageInstaller *pkgInstaller =
          [[PBPackageInstaller alloc] initWithURL:URLForPackagePath(packagePath)
                                      receiptName:receiptName];
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
