#
# Be sure to run `pod lib lint chat360_ios_sdk.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'chat360-ios-sdk'
  s.version          = '1.0.4'
  s.summary          = 'Chat360 IOS SDK'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Its a Chat360 IOS SDK for ios application.
                       DESC

  s.homepage         = 'https://github.com/sumanel/chat360-ios-sdk/tree/master'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Chat360' => 'production@chat360.io' }
  s.source           = { :git => 'https://github.com/sumanel/chat360-ios-sdk.git', :tag => "1.0.4"  }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '11.0'

  s.source_files = 'Classes/**/*.{h,swift}'
  
  # s.resource_bundles = {
  #   'chat360_ios_sdk' => ['chat360_ios_sdk/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
