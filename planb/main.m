/*

 Plan B
 main.m

 Installs management software on a managed Mac.

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

#include "roots.pem.h"

#import "PBLogging.h"
#import "PBPackageInstaller.h"
#import "PBURLBuilder.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

int main(int argc, const char * argv[]) {
  @autoreleasepool {

    if (getuid() != 0) {
      PBLog(@"%s must be run as root!", argv[0]);
      exit(99);
    }

    PBLog(@"Starting %s", argv[0]);

    __block BOOL installComplete = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.URLCache = nil;
    config.timeoutIntervalForResource = 30;

    if (![[[NSProcessInfo processInfo] arguments] containsObject:@"--use-proxy"]) {
      config.connectionProxyDictionary = @{ (NSString *)kCFNetworkProxiesHTTPSEnable: @NO };
    }

    MOLAuthenticatingURLSession *authURLSession =
        [[MOLAuthenticatingURLSession alloc] initWithSessionConfiguration:config];

    authURLSession.serverRootsPemData = [NSData dataWithBytes:ROOTS_PEM length:ROOTS_PEM_len];
    authURLSession.refusesRedirects = YES;
    authURLSession.loggingBlock = ^(NSString *line) {
      PBLog(@"%@", line);
    };

    NSArray *packages = @[
      @[ @"pkg1/package1", @"com.megacorp.package1" ],
      @[ @"pkg2/package2", @"com.megacorp.package2" ],
      @[ @"pkg3/package3", @"com.megacorp.package3" ],
    ];

    for (NSArray *packageTuple in packages) {
      NSString *item = [packageTuple objectAtIndex:0];
      NSString *receiptName = [packageTuple objectAtIndex:1];
      NSURL *url = [URLBuilder URLForTrackWithPkg:item];

      PBLog(@"Requesting %@", url.absoluteString);

      [[authURLSession.session downloadTaskWithURL:url
                                 completionHandler:^(NSURL *location,
                                                     NSURLResponse *response,
                                                     NSError *error) {
        PBPackageInstaller *pkg =
            [[PBPackageInstaller alloc] initWithReceiptName:receiptName
                                                packagePath:[location absoluteString]
                                               targetVolume:@"/"];
        [pkg installApplication];
        installComplete = YES;

        PBLog(@"Finished with %@", item);
      }] resume];

      installComplete = NO;

      while (!installComplete) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
      }
    }

    return 0;
  }
}

