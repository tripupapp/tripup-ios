source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '12.4'
use_frameworks!
inhibit_all_warnings!

target 'TripUp' do
    pod 'Alamofire'
    pod 'AlamofireNetworkActivityIndicator'
    pod 'AnimatedGradientView'
    pod 'AWSMobileClient'
    pod 'AWSS3'
    pod 'BadgeSwift'
    pod 'Charts'
    pod 'Connectivity'
    pod 'CryptoSwift'
    pod 'Firebase/Analytics'
    pod 'Firebase/Auth'
    pod 'Firebase/Crashlytics'
    pod 'Firebase/DynamicLinks'
    pod 'FTLinearActivityIndicator'
    pod 'IQKeyboardManagerSwift'
    pod 'OneSignal', '>= 3.0.0', '< 4.0'
    pod 'PhoneNumberKit'
    pod 'Purchases'
    pod 'SwiftProtobuf'
    pod 'SwiftyBeaver'
    pod 'Toast-Swift'

    target 'TripUpTests' do
        inherit! :search_paths
    end
end

target 'OneSignalNotificationServiceExtension' do
    pod 'OneSignal', '>= 3.0.0', '< 4.0'
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
        end
    end
end
