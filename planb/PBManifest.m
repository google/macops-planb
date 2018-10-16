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

#import <CommonCrypto/CommonDigest.h>

#import "PBManifest.h"

#import "PBLogging.h"

static NSString *const kNameKey = @"name";
static NSString *const kURLKey = @"url";
static NSString *const kSHA256Key = @"sha256";

@interface PBManifest()

/// The URL to download the package manifest from.
@property(readonly, nonatomic, copy) NSURL *manifestURL;

/// The parsed manifest data.
@property(nonatomic) NSDictionary *manifest;

@end

@implementation PBManifest

- (instancetype)initWithURL:(NSURL *)manifestURL {
  if (!manifestURL.absoluteString.length) {
    return nil;
  }
  self = [super init];
  if (self) {
    _manifestURL = [manifestURL copy];
    _downloadAttemptsMax = 5;
    _downloadTimeoutSeconds = 300;
    _session = [NSURLSession sharedSession];
  }
  return self;
}

- (void)downloadManifest {
  __block NSData *jsonData;
  __block NSString *errorDescription;

  for (NSUInteger i = 1; i <= self.downloadAttemptsMax; ++i) {
    PBLog(@"Downloading manifest, attempt %tu/%tu", i, self.downloadAttemptsMax);

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[self.session dataTaskWithURL:self.manifestURL completionHandler:^(NSData *data,
                                                                        NSURLResponse *response,
                                                                        NSError *error) {
      if (((NSHTTPURLResponse *)response).statusCode == 200) {
        jsonData = data;
      } else {
        errorDescription = error.localizedDescription;
      }
      dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW,
                                                self.downloadTimeoutSeconds * NSEC_PER_SEC));

    if (jsonData) {
      break;
    } else if (errorDescription) {
      PBLog(@"Download of manifest failed: %@", errorDescription);
    }
  }

  if (jsonData) {
    [self parseManifestData:jsonData];
  }
}

- (void)parseManifestData:(NSData *)data {
  NSError *error;
  id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error) {
    PBLog(@"Error parsing manifest: %@", error.localizedDescription);
    return;
  }
  // Validate the manifest data which should have the form:
  // {"track1": [ {"key1": "val1", "key2": "val2", ...}, ... ], ...}
  if (![jsonObject isKindOfClass:[NSDictionary class]]) {
    PBLog(@"Invalid manifest -- root object is not a dictionary");
    return;
  }
  NSDictionary *manifest = (NSDictionary *)jsonObject;
  for (id track in manifest) {
    if (![track isKindOfClass:[NSString class]]) {
      PBLog(@"Invalid manifest -- track key is not a string: %@", track);
      return;
    }
    if (![manifest[track] isKindOfClass:[NSDictionary class]]) {
      PBLog(@"Invalid manifest -- track %@ value is not a dictionary: %@", track, manifest[track]);
      return;
    }
    NSDictionary *package = (NSDictionary *)manifest[track];
    for (id key in package) {
      if (![key isKindOfClass:[NSString class]]) {
        PBLog(@"Invalid manifest -- package key is not a string: %@", key);
        return;
      }
      if (![package[key] isKindOfClass:[NSString class]]) {
        PBLog(@"Invalid manifest -- package key %@ value is not a string: %@", key, package[key]);
        return;
      }
    }
  }
  self.manifest = (NSDictionary *)jsonObject;
}

- (NSArray *)packagesForTrack:(NSString *)track {
  if (!self.manifest) {
    return @[];
  }
  NSMutableArray *result = [NSMutableArray array];
  for (NSDictionary *package in self.manifest[track]) {
    if (!package[kURLKey]) continue;
    if (!package[kNameKey]) continue;
    if (package[kSHA256Key]) {
      [result addObject:@[package[kURLKey], package[kNameKey], package[kSHA256Key]]];
    } else {
      [result addObject:@[package[kURLKey], package[kNameKey]]];
    }
  }
  return result;
}

@end
