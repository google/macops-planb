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

/// PBPackageInstaller handles downloading, mounting and installing a package,
/// while forgetting the existing package receipt where necessary.
@interface PBPackageInstaller : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Designated initializer.
- (instancetype)initWithURL:(NSURL *)packageURL
                receiptName:(NSString *)receipt NS_DESIGNATED_INITIALIZER;

/// The NSURLSession to use for downloading packages. If not set, a default one will be used.
@property NSURLSession *session;

/// The number of seconds to allow downloading before timing out. Defaults to 300 (5 minutes).
@property NSUInteger downloadTimeoutSeconds;

/// The number of download attempts before giving up. Defaults to 5.
@property NSUInteger downloadAttemptsMax;

/// A prefix to prepend to all lines logged by this class.
@property(copy) NSString *logPrefix;

/// Mount disk image and install package.
/// @return YES if installation was successful
- (BOOL)install;

@end

