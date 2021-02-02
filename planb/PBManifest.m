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

static NSString * const kPackagesKey = @"packages";
static NSString * const kNameKey = @"name";
static NSString * const kPackageIDKey = @"package_id";
static NSString * const kTracksKey = @"tracks";
static NSString * const kFilenameKey = @"filename";
static NSString * const kSHA256Key = @"sha256";
static NSString * const kPlanBIgnoreKey = @"planb_ignore";

@interface PBManifest()

/// The URL to download the package manifest from.
@property(readonly, nonatomic) NSURL *manifestURL;

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
      if (![response isKindOfClass:[NSHTTPURLResponse class]] ||
          ((NSHTTPURLResponse *)response).statusCode == 200) {
        jsonData = data;
      }
      if (error) {
        if (data) {
          NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          errorDescription =
              [NSString stringWithFormat:@"%@\n%@", error.localizedDescription, body];
        } else {
          errorDescription = error.localizedDescription;
        }
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
  } else {
    PBLog(@"Error: couldn't download manifest from %@", self.manifestURL.absoluteString);
  }
}

- (BOOL)parseManifestData:(NSData *)data {
  NSError *error;
  id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (!jsonObject) {
    PBLog(@"Error parsing manifest: %@", error.localizedDescription);
    return NO;
  }
  // Validate the manifest data which should have the form:
  // {"packages": [ <pkg1>, <pkg2>, ...]}
  // Each package object in the list should have the form:
  // {"name":"xxx", "package_id":"xxx", "tracks":{"aaa": <fileobj>, "bbb": <fileobj>, ...}}
  // Each file object value in the tracks dict should have the form:
  // {"filename":"xxx", "sha256":"xxx"} where the "sha256" key is optional.
  if (![jsonObject isKindOfClass:[NSDictionary class]]) {
    PBLog(@"Invalid manifest -- root object is not a dictionary");
    return NO;
  }
  NSDictionary *manifest = (NSDictionary *)jsonObject;
  PBLog(@"Validating manifest...");
  if (![manifest[kPackagesKey] isKindOfClass:[NSArray class]]) {
    PBLog(@"Invalid manifest -- value of %@ is not an array: %@",
          kPackagesKey, manifest[kPackagesKey]);
    return NO;
  }
  NSArray *packages = manifest[kPackagesKey];
  for (id object in packages) {
    if (![self validatePackage:object]) {
      return NO;
    }
  }
  self.manifest = manifest;
  return YES;
}

- (BOOL)validatePackage:(id)object {
  if (![object isKindOfClass:[NSDictionary class]]) {
    PBLog(@"Invalid manifest -- package item is not a dictionary: %@", object)
    return NO;
  }
  NSDictionary *package = (NSDictionary *)object;
  for (NSString *key in @[kNameKey, kPackageIDKey]) {
    if (![package[key] isKindOfClass:[NSString class]]) {
      PBLog(@"Invalid manifest -- package value for %@ key is not a string: %@", key, package[key]);
      return NO;
    }
  }
  // Note: the "planb_ignore" key is optional, so we only verify its class if it exists.
  if (package[kPlanBIgnoreKey] && ![package[kPlanBIgnoreKey] isKindOfClass:[NSNumber class]]) {
    PBLog(@"Invalid manifest -- track value for %@ key is not a boolean: %@", kPlanBIgnoreKey,
          package[kPlanBIgnoreKey]);
    return NO;
  }
  if (![package[kTracksKey] isKindOfClass:[NSDictionary class]]) {
    PBLog(@"Invalid manifest -- package value for %@ key is not a dictionary: %@",
          kTracksKey, package[kTracksKey]);
    return NO;
  }
  NSDictionary *tracks = package[kTracksKey];
  for (id key in tracks) {
    if (![key isKindOfClass:[NSString class]]) {
      PBLog(@"Invalid manifest -- track key is not a string: %@", key);
      return NO;
    }
    if (![self validateTrack:tracks[key]]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)validateTrack:(id)object {
  if (![object isKindOfClass:[NSDictionary class]]) {
    PBLog(@"Invalid manifest -- track item is not a dictionary: %@", object);
    return NO;
  }
  NSDictionary *item = object;
  if (![item[kFilenameKey] isKindOfClass:[NSString class]]) {
    PBLog(@"Invalid manifest -- track value for %@ key is not a string: %@", kFilenameKey,
          item[kFilenameKey]);
    return NO;
  }
  // Note: the "sha256" is optional, so we only verify its class if it exists.
  if (item[kSHA256Key] && ![item[kSHA256Key] isKindOfClass:[NSString class]]) {
    PBLog(@"Invalid manifest -- track value for %@ key is not a string: %@", kSHA256Key,
          item[kSHA256Key]);
    return NO;
  }
  return YES;
}

- (NSArray *)packagesForTrack:(NSString *)track relativeToURL:(NSURL *)baseURL {
  if (!self.manifest) {
    return @[];
  }
  NSMutableArray *result = [NSMutableArray array];
  for (NSDictionary *package in self.manifest[kPackagesKey]) {
    NSString *packageID = package[kPackageIDKey];
    if (!packageID) {
      PBLog(@"Package is missing %@ key, skipping: %@", kPackageIDKey, package);
      continue;
    }
    if ([package[kPlanBIgnoreKey] boolValue]) {
      PBLog(@"Package %@ has ignore key set, skipping", packageID);
      continue;
    }
    NSDictionary *item = package[kTracksKey][track];
    if (!item) {
      PBLog(@"Package %@ has no item for %@ track, skipping", packageID, track);
      continue;
    }
    if (!item[kFilenameKey]) {
      PBLog(@"Package %@ in %@ is missing %@ key, skipping", packageID, track, kFilenameKey);
      continue;
    }
    NSString *path = [[NSURL URLWithString:item[kFilenameKey] relativeToURL:baseURL]
                      absoluteString];
    if (item[kSHA256Key]) {
      [result addObject:@[path, packageID, item[kSHA256Key]]];
    } else {
      [result addObject:@[path, packageID]];
    }
  }
  return result;
}

@end
