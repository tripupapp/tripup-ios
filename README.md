# TripUp iOS App
![GitHub](https://img.shields.io/github/license/tripupapp/tripup-ios)
![Xcode 12.4+](https://img.shields.io/badge/Xcode-12.4%2B-blue.svg)
![iOS 12.4+](https://img.shields.io/badge/iOS-12.4%2B-blue.svg)
![Swift 5.0+](https://img.shields.io/badge/Swift-5.0%2B-green.svg)

[TripUp](https://tripup.app) is an open source, photo storage and sharing app made for privacy conscious users.

[![Available on the App Store](http://cl.ly/WouG/Download_on_the_App_Store_Badge_US-UK_135x40.svg)](https://apps.apple.com/us/app/tripup-private-photo-storage/id1420176032)

## Screenshots
|<img src="https://tripup.app/public/screenshots/460x0w0.webp" width="180" />|<img src="https://tripup.app/public/screenshots/460x0w1.webp" width="180" />|<img src="https://tripup.app/public/screenshots/460x0w2.webp" width="180" />|
|----|----|----|
|<img src="https://tripup.app/public/screenshots/460x0w3.webp" width="180" />|<img src="https://tripup.app/public/screenshots/460x0w4.webp" width="180" />| <img src="https://tripup.app/public/screenshots/460x0w5.webp" width="180" />

## Features
- Auto backs up all your photos to the cloud
- Background uploads
- Photos, data and metadata are all end-to-end encrypted with PGP
- Supports user registration with a phone number, e-mail address or Sign in with Apple
- Shared albums with fine-grained privacy controls for individual photos
- Supports iOS Dark Mode
- Native Swift app
- Open source client + server

## Questions and Support
Please use the following channels for any questions or support:
- [GitHub Discussions](https://github.com/tripupapp/tripup-ios/discussions)
- [Reddit](https://reddit.com/r/tripup)
- [Discord Channel](https://discord.gg/5xCF7Eb)

❗ Please **DO NOT** use the GitHub issue tracker for support queries. ❗️

## Build Instructions

### Dependencies
- Firebase, for authentication and dynamic links.
- AWS, for data storage.
- OneSignal, for notifications.
- RevenueCat, for managing in-app purchases.
- TripUp server, for hosting and co-ordinating user state.

*Note: where possible, analytics are disabled for the above services.*

### Steps
1. Replace the `GoogleService-Info.plist` file with the one provided to you by Firebase.
2. Update the `awsconfiguration.json` file with your AWS Cognito PoolID and Region, as per your AWS setup.
3. Project build settings -> `User-Defined` heading:
    - change `API_BASE_URL` to the URL of the TripUp server instance that you wish to use.
    - change `AWS_ASSETS_BUCKET` to the name of the bucket that you wish to use on AWS.
4. Modify `Info.plist` accordingly, specifically the following values:
    - Under URL types -> URL Schemes:
        - `com.googleusercontent.apps...` should be set to the `REVERSED_CLIENT_ID` value found in your `GoogleService-Info.plist` file.
        - The `firdynamiclinks` URL Scheme should be set your bundle identifier.
    - Under `AppConfig`:
        - `AWS_ASSETS_BUCKET_REGION`, which should be the same value as the one set in `awsconfiguration.json`.
        - `DOMAIN`, should be a fully qualified hostname.
        - `FEDERATION_PROVIDER`, should be the URL of your federation provider, which in this case is `securetoken.google.com/YOUR_FIREBASE_PROJECT_ID`.
        - `FIREBASE_DYNAMICLINKS_DOMAIN`, should be set to your Firebase Dynamic Links Domain.
        - `ONESIGNAL_APP_ID`, should be set to your OneSignal App ID.
        - `REVENUECAT_APIKEY`, should be set to your RevenueCat API key.
5. Adjust the `Associated Domains` under the TripUp Target, Signing & Capabilities tab to the following values:
    - `applinks:YOUR_FIREBASE_PROJECT_ID.firebaseapp.com`
    - `applinks:YOUR_FIREBASE_DYNAMIC_LINKS_DOMAIN`
6. Build to whichever target you want and Sign with your Apple Developer account.

## Contributing
There are many ways to contribute to TripUp!

### Bug reports
We use the [GitHub issue tracker](https://github.com/tripupapp/tripup-ios/issues) for bug reports. Please search existing issues and create a new one if your bug report has not been raised, providing as much detail as possible.

🛑 **Please DO NOT bump an issue with +1 posts that do not add to the discussion. Use the emoji reactions instead to show that an issue affects you too; we will prioritise issues that have the most reactions.** 🛑

### Code
Swift developers wanted! We prefer native development whenever possible and welcome developers (new and experienced) to contribute. We use [GitHub projects](https://github.com/tripupapp/tripup-ios/projects) for coordinating our work. If you require help with a code change, feel free to open a pull request.

For this repository, we require contributors to sign a copyright license agreement (CLA). The signing process will be presented when you submit a pull request. A CLA is required because the Apple App Store Terms of Service (ToS) are incompatible with the license of this project, the AGPLv3. To include your contributions in our App Store release, we require an exclusive copyright license to any contributions you make, which grants us the ability to dual license the code; under the AGPLv3 (this repository) and under a license that complies with the App Store ToS. Please note that we use a CLA written and approved by the Free Software Foundation which ensures that we always release your contributions under the AGPLv3 and can never exclusively re-license your contributions under a proprietary license. [Refer to our CLA](https://gist.github.com/vin047/f71a956baa4d4f543597a9994edd0fb1) for the full license agreement (also visible when submitting a pull request).

### Feature suggestions
Please use [GitHub Discussions](https://github.com/tripupapp/tripup-ios/discussions) to suggest new features.

### Translations
We welcome translations for as many languages as possible! Contact us if you'd like to help but are unsure on how to use Xcode or GitHub pull requests.

## License
This project is licensed under the AGPLv3. Please see the LICENSE file for the full license terms.

Please note that whilst the code is licensed under the AGPLv3, all assets, logos and branding, including the name, are subject to relevant trademark laws and explicit permission is required before using these for any commercial purposes.
