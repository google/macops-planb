/*
 Copyright 2018 Google Inc.

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

/// PBManifest handles downloading and parsing a list of packages to fetch and install.
@interface PBManifest : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Designated initializer.
- (instancetype)initWithURL:(NSURL *)manifestURL NS_DESIGNATED_INITIALIZER;

/// Download and parse the manifest.
- (void)downloadManifest;

/// Return list of packages in the manifest for the given track.  The path in baseURL is prepended
/// to each relative package URL specified in the manifest.  Each package item is represented as
/// an NSArray having the form @[<package-id>, <absolute-URL-to-package>, <SHA256>]
- (NSArray *)packagesForTrack:(NSString *)track relativeToURL:(NSURL *)baseURL;

/// The NSURLSession to use for downloading packages. If not set, a default one will be used.
@property NSURLSession *session;

/// The number of seconds to allow downloading before timing out. Defaults to 300 (5 minutes).
/// TODO(nguyenphillip): use session config's timeoutIntervalForResource to handle timeouts, and
/// make session a required argument of initializer for both PBManifest and PBPackageInstaller.
@property NSUInteger downloadTimeoutSeconds;

/// The number of download attempts before giving up. Defaults to 5.
@property NSUInteger downloadAttemptsMax;

@end
