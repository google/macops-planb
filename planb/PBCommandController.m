/*
  Copyright 2017 Google Inc.

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

#import "PBCommandController.h"

@interface PBCommandController ()
@property NSTask *task;
@end

@implementation PBCommandController

- (instancetype)init {
  self = [super init];
  if (self) {
    _task = [[NSTask alloc] init];
  }
  return self;
}

- (NSString *)launchPath {
  return self.task.launchPath;
}

- (void)setLaunchPath:(NSString *)launchPath {
  self.task.launchPath = [launchPath copy];
}

- (NSArray *)arguments {
  return self.task.arguments;
}

- (void)setArguments:(NSArray *)arguments {
  self.task.arguments = [arguments copy];
}

- (NSDictionary *)environment {
  return self.task.environment;
}

- (void)setEnvironment:(NSDictionary *)environment {
  self.task.environment = [environment copy];
}

- (int)launchWithOutput:(NSString *__autoreleasing *)output {
  self.task.standardInput = [NSPipe pipe];
  self.task.standardOutput = self.task.standardError = [NSPipe pipe];

  __weak typeof(self) weakSelf = self;
  __block NSException *exception;

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    typeof(weakSelf) self = weakSelf;

    @try {
      [self.task launch];

      if (self.standardInput) {
        NSData *data = [self.standardInput dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *inputFh = [self.task.standardInput fileHandleForWriting];

        [inputFh writeData:data];
        [inputFh closeFile];
      }

      [self.task waitUntilExit];
    } @catch (NSException *e) {
      exception = e;
    } @finally {
      dispatch_semaphore_signal(sema);
    }
  });
  dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, self.timeout * NSEC_PER_SEC));

  if ([self.task isRunning]) {
    kill(self.task.processIdentifier, SIGKILL);
    sleep(2); // Give the process time to exit
  }

  if (exception) {
    if (output) *output = exception.reason;
    return -1;
  }

  if (output) {
    NSData *availableData = [[self.task.standardOutput fileHandleForReading] availableData];
    *output = [[NSString alloc] initWithData:availableData encoding:NSUTF8StringEncoding];
  }

  int status = -1;
  @try {
    status = self.task.terminationStatus;
  } @catch (NSException *e) {}

  return status;
}

@end
