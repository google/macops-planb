Overview
========

Plan B is a remediation program for managed Macs. It is meant to be run to re-install other management software.

Features
------

  - Secure download of disk images from an Internet-facing server.
  - Installation of package files contained on the disk images.
  - Validation of server certificate against explicitly trusted certificate authorities only.
  - Support for client certificate authentication to ensure only trusted clients can access the server.
  - URL construction to download packages based on a client's configuration in a plist.
  - Extensive logging of presented certificate details for auditing and MITM detection.
  - No external dependencies; the compiled program is tiny and can be easily deployed.

Usage
------

First, create a Web server which will host disk images containing a single `.pkg` package file on each `.dmg` disk image file.

There is a shell script included in this directory to generate a public-key infrastructure, if one is not already in place. There are also many excellent guides and programs, like `easy-rsa`, available online.

If the server has enabled client certificate authentication, first install the client certificate and private key to system keychain. You may first need to convert them to PKCS#12 format with something like, `openssl pkcs12 -export -in client.crt -inkey client.key -certfile ca.pem -out client.p12`. Otherwise, the program will perform server certificate validation only.

Compiling Plan B requires a modern version of Xcode, available from Apple's Developer site.

* Download the source code with `git clone https://github.com/google/macops-planb` 

* Install required CocoaPods with `pod install`

* Open the Xcode project with `open macops-planb/planb.xcodeproj`

* Edit `PBURLBuilder.m` and change `kBaseURL` to the URL of the server and folder containing disk images. By default, the program will use `https://mac.internal.megacorp.com/pkgs/`

* Edit `main.m` and change the `packages` array to match the names of disk image names and their contained packages' receipt names. By default, the program will construct `pkg1/package1-stable.dmg` and forget the receipt for package `com.megacorp.package1` prior to re-installation, and so on.

* Edit `PBURLBuilder.m` and change the `kMachineInfo` to match a machine information plist, which may contain a `ConfigurationTrack` value, for example. This value is used to construct the disk image suffix, like `package1-stable.dmg`, `package1-testing.dmg` or `package1-unstable.dmg`. This is useful if you have machines on multiple configuration tracks.

* Edit `roots.pem` and change the contents to include a single or multiple PEM-encoded certificate authority certificates you wish to trust for server validation. By default, the program will use `GeoTrust Global CA`, the authority used to sign Google's intermediate CA, however you should use the CA which has signed the server's certificate or the server's intermediate certificate.

* Compile the program with `xcodebuild -workspace planb.xcworkspace -scheme planb -configuration Release`. It will appear in `./Build/Products/Release/planb`

The planb binary must be run as `root` in order to install packages. It will run on its own without any external dependencies.

Deployment
----------

It is recommended to create a simple script to determine the health of the machine, for example by checking the last successful run date of the primary management software, and running Plan B if the condition is not met. This script can then be started periodically as a system launch daemon.

Have a look at the `planb_check` shell script and the `com.megacorp.planb.plist` launch daemon property list for an example.

In our environment, we have a wrapper tool for Puppet, which verifies the configuration run was successful and updates the timestamp on a file. We track this in `planb_check` and base the decision to kick off `planb` from it.

