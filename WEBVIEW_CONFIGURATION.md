# Chat360 WebView Configuration Guide

## Recent Updates

### 1. Location Sharing (Geolocation)
Location sharing in the webview now works correctly with proper permission handling:

- **iOS 14.5+**: Implements `requestGeolocationPermissionFor` delegate method
- **Automatic Permission Prompt**: When geolocation is requested, iOS will automatically prompt the user
- **Permission Handling**: 
  - If user granted: Permission is granted to the webview
  - If user denied: Permission is denied
  - If not determined: System shows the permission prompt

#### Required Info.plist Entries
Add these keys to your app's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs access to your location to provide location-based services</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs access to your location to provide location-based services</string>
```

Or in Swift code using XcodeGen or similar:
```yaml
infoPlist:
  NSLocationWhenInUseUsageDescription: "This app needs access to your location to provide location-based services"
  NSLocationAlwaysAndWhenInUseUsageDescription: "This app needs access to your location to provide location-based services"
```

### 2. External Link Redirection
External links now open outside the app instead of within the webview:

- **Bot Internal URLs**: Links to the bot domain (containing bot ID) remain within the webview
- **External Links**: All other HTTP/HTTPS links open in the device's default browser
- **Development URLs**: Localhost and 127.0.0.1 URLs are allowed within the webview for development

#### Implementation Details
The `decidePolicyFor navigationAction` method:
- Identifies the link type (internal vs external)
- For external links: Opens them using `UIApplication.shared.open(url)`
- For internal links: Allows them to load within the webview

### 3. Additional Permissions
The following permissions are also implemented:

- **Media Capture**: Camera and microphone access requests are automatically granted (iOS 13+)
- **Device Motion**: Device orientation and motion access requests are automatically granted (iOS 15+)

#### Required Info.plist Entries (if using media capture)
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to your camera for video calls</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone for audio calls</string>
```

## Modified Files

- `Sources/Chat360Sdk/View/Chat360BotView.swift`: Added CoreLocation import and implemented delegate methods

## Testing

1. **Test Location Sharing**:
   - Navigate to a page in the webview that requests geolocation
   - Confirm iOS shows the permission prompt
   - Grant permission and verify geolocation works

2. **Test External Link Redirection**:
   - Click on an external link in the webview
   - Confirm it opens in the system browser (Safari)
   - Verify internal bot links still load within the webview

3. **Test Media Permissions**:
   - If using camera/microphone features, verify they work without additional prompts
