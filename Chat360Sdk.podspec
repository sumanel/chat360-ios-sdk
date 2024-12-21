Pod::Spec.new do |spec|
    spec.name = "Chat360SDK"
    spec.version = "2.1.8"
    spec.summary = "Generative AI for Enhanced CX Engagement"
    spec.homepage = "https://chat360.io/"
  
    spec.license = { :type => "Commercial", :text => "See https://chat360.io/"}
    spec.author = "chat360.io"
    spec.platform = :ios, "12.0"
  
    spec.source = { :git => "https://github.com/sumanel/chat360-ios-sdk.git", :tag => "#{spec.version}" }
    spec.source_files = "Sources/Chat360Sdk/**/*.swift"
    spec.swift_version = '5.0'
  end