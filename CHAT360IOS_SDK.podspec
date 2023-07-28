#
# Be sure to run `pod lib lint CHAT360IOS_SDK.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |spec|
  spec.name             = 'CHAT360IOS_SDK'
  spec.version          = '1.0.8'
  spec.summary          = 'Chat360 IOS SDK'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  spec.description      = <<-DESC
"Its a Chat360 IOS SDK for ios application."
                       DESC

  spec.homepage         = 'https://github.com/sumanel/chat360-ios-sdk'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  spec.license          = { :type => 'MIT', :file => 'LICENSE' }
  spec.author           = { 'chat360' => 'production@chat360.io' }
  spec.source           = { :git => 'https://github.com/sumanel/chat360-ios-sdk.git', :tag => "1.0.8" }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  spec.ios.deployment_target = '11.0'

  spec.source_files = 'Classes/**/*.{h,swift}'
  
  # s.resource_bundles = {
  #   'CHAT360IOS_SDK' => ['CHAT360IOS_SDK/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
