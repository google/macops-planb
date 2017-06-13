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

@import Foundation;

///
///  PBCommandController is a wrapper around NSTask which makes I/O with the task easier,
///  avoids the use of Objective-C exceptions and adds a timeout property.
///
@interface PBCommandController : NSObject

///  The full path to the binary to launch
@property(copy, nonatomic) NSString *launchPath;

///  An array of arguments to pass to the binary.
@property(copy, nonatomic) NSArray *arguments;

///  A dictionary of environment variables to pass to the binary.
@property(copy, nonatomic) NSDictionary *environment;

///  A string sent to the binary as standard input as soon as the task is launched.
@property(copy, nonatomic) NSString *standardInput;

///  Number of seconds to allow task to run before it is killed.
///  If set to 0, the command will be allowed to run indefinitely.
@property unsigned int timeout;

///  Unlike NSTask's launch, this won't throw an exception for any reason.
///  @param output - if provided, will be filled with the output of the command.
///  @param int - the termination status of the command or -1 if an exception occurred.
- (int)launchWithOutput:(NSString **)output;

@end
