# Chat360 Swift Library

Chat360 is a Swift library that lets you embed a full chatbot conversation screen into your iOS app. It ships a native SwiftUI chat interface (message list, drawer/history, input bar, theming) that you configure and present with a few lines of code.

## Features

- Native SwiftUI chat screen — no WebView required.
- Fully themeable: colors (light/dark), typography, and branding (logo, copy) via `Chat360Config`.
- Feature flags to show/hide individual pieces of chrome (menu, history drawer, new chat, feedback, regenerate, voice input, close button, etc.) via `Chat360UIConfig`.
- Conversation history with local caching, resume-on-relaunch, and room switching.
- Bot responses containing an HTML `<table>` render as an actual aligned table (with wrapping
  cell text), instead of jumbled plain text.
- A 1-hour session countdown timer, shown in the header once the user sends their first
  message, that resumes correctly when switching between conversations instead of resetting.
- Like/dislike on bot messages, persisted locally across app restarts. Disliking opens a
  mandatory feedback box (min 20 characters) that blocks the chat until submitted or
  cancelled — cancelling undoes the dislike rather than letting feedback be skipped. Dislike
  is permanent once set; a like can still be switched to a dislike afterward, but not the
  reverse. When `clientId`/`apiKey`/`endUserId` are configured, reactions are also reported to
  Chat360's `third-party-tasks` feedback API.
- `onChatSessionReady` callback so the host app can show its own loading state between
  presenting the chat screen and the connection actually being live.
- Configurable parameters for customization (bot ID, app ID, debug mode, etc.).
- Supports sending metadata to enhance chatbot functionality.
- Back button / close handling with custom callbacks.
- A legacy WebView-based mode is still available (`useNewUI: false`) for existing integrations.

## Requirements

- iOS 12.0+ deployment target (legacy WebView mode).
- **iOS 16.0+ is required for the native chat screen.** If `useNewUI: true` is set but the device is running an older iOS version, the SDK automatically and silently falls back to the legacy WebView screen instead. If you require the native UI, set your app's own minimum deployment target to iOS 16.0 as well — otherwise users on iOS 15 and below will transparently get the older WebView experience.
- Swift 5.

## Installation

### Using Swift Package Manager

To install the Chat360 library using Swift Package Manager, follow these steps:

1. Open your Xcode project.
2. Go to `File` > `Swift Packages` > `Add Package Dependency`.
3. Enter the repository URL for Chat360:

   ```
   https://github.com/sumanel/chat360-ios-sdk.git
   ```

4. Choose the version you want to install (usually the latest version) and click `Next`.
5. Complete the installation.

### Using CocoaPods

```ruby
pod 'Chat360SDK', :git => 'https://github.com/sumanel/chat360-ios-sdk.git', :tag => 'X.Y.Z'
```

Replace `X.Y.Z` with the version you're integrating against.

## Usage

### Step 1: Import the Library

Import the Chat360 library in your Swift file:

```swift
import Chat360SDK
```

### Step 2: Configure the Chat360Bot

Create an instance of `Chat360Config` with your bot and app IDs. Set `useNewUI: true` to use the native SwiftUI chat screen (recommended for new integrations):

```swift
let chatConfig = Chat360Config(botId: "YOUR_BOT_ID", appId: "YOUR_APP_ID", useNewUI: true)
```

If you are using your own custom base url for the bot, set it on `Chat360Bot`:

```swift
Chat360Bot.shared.setBaseUrl(url: "https://your-base-url")
```

### Step 3: Display the ChatBot

You can present the Bot View using the code below:

```swift
Chat360Bot.shared.setConfig(chat360Config: config)
try? Chat360Bot.shared.startChatbot(animated: true)
```

### Step 4: Close the ChatBot

You can close the Bot View using the code below:

```swift
try? Chat360Bot.shared.closeChatBot(animated: true)
```

### Step 5: To Send Events to Bot

You can send events to the Bot View using the code below:

```swift
try? Chat360Bot.shared.sendEventToBot(event: event)
```

## Configuration Options

### Basic Configuration

- **botId**: The ID of your chatbot.
- **appId**: Your application ID.
- **useNewUI**: `Bool` — presents the native SwiftUI chat screen when `true`. Defaults to `false` (legacy WebView).
- **isDebug**: points requests at Chat360's staging environment when `true`.
- **meta**: A dictionary for sending additional metadata as a JSON string.
- **historyEnabled** / **clientId** / **apiKey** / **endUserId**: enable the third-party conversation-history/rooms API (multi-conversation drawer, resume across launches).

### Theming (native UI)

`Chat360Config` exposes a full theming surface for the native chat screen:

```swift
let config = Chat360Config(botId: "YOUR_BOT_ID", appId: "YOUR_APP_ID", useNewUI: true)
config.themePreset = .custom
config.customLightColors = Chat360Colors(
    accent: .blue, accentContrast: .white,
    background: .white, backgroundElevated: .white, backgroundSunken: Color(white: 0.96),
    line: Color(white: 0.9),
    textPrimary: .black, textSecondary: .gray, textDisabled: Color(white: 0.8),
    bubbleUserBackground: .blue, bubbleUserText: .white,
    bubbleAiBackground: .white, bubbleAiText: .black,
    cardBackground: .white, cardBorder: Color(white: 0.9),
    inputBackground: .white, inputBorder: Color(white: 0.8),
    statusBar: .blue
)
config.customDarkColors = /* same shape, dark palette */
config.customTypography = Chat360Typography(headFamily: .system, textFamily: .system) // or .custom("YourFontName")
config.customBranding = Chat360Branding(
    botTitle: "My Assistant",
    logo: .resource(light: "MyLogoLight", dark: "MyLogoDark"), // asset-catalog names, or .remote(url:)
    welcomeHeading: "Hi, how can I help?",
    disclaimerText: "My Assistant can make mistakes. Verify important information.",
    inputPlaceholder: "Ask me anything…",
    welcomeLogoSize: 120 // optional — point size of the logo on the pre-chat welcome splash
)
```

`themePreset` defaults to `.default`, which ships a brand-neutral palette — set it to `.custom` to apply your own colors/typography/branding as shown above. Colors, logo, and welcome copy can also be partially overridden at runtime from the bot's own server-side appearance settings; explicit `.custom` config always wins over those.

### Feature flags (native UI)

Pass a `Chat360UIConfig` to control which pieces of chrome are shown, via `config.uiConfig`:

```swift
config.uiConfig = Chat360UIConfig(
    theme: Chat360ThemeConfig(defaultTheme: .system, allowThemeSwitch: true, followSystemTheme: true),
    features: Chat360FeatureConfig(
        showMenu: true,              // hamburger menu / drawer entry point
        showHistorySidebar: true,    // conversation history drawer
        showNewChat: true,           // "+" new chat button
        showFeedback: true,          // like/dislike on bot messages — dislike opens a mandatory feedback box, see Feedback section below
        showCopyMessage: true,       // copy icon on bot messages
        showRegenerate: true,        // regenerate icon on bot messages
        showVoiceInput: true,        // mic / voice note button
        showAssistantMode: true,     // Training/Customer toggle in the drawer
        showAppearanceSwitcher: true,// manual Light/Dark toggle in the drawer
        showClose: true              // header close (X) button — see note below
    )
)
```

`showClose` defaults to `true`. The native chat screen presents full-screen with no swipe-to-dismiss gesture, so if you turn this off, make sure your host app provides another way to close the screen (e.g. from your own navigation chrome) — otherwise users have no way out.

`Chat360UIConfig` also exposes `ui` (slots for injecting your own header/footer/message-toolbar/welcome-screen views) and `callbacks` (hooks like `onMenuClicked`, `onNewChatClicked`, `onRegenerateClicked`, `onFeedback`) if you need deeper customization or analytics.

### Feedback (like/dislike)

Dislike is permanent once set for a message — a like can still be switched to a dislike afterward, but not the other way around. Both persist locally and survive app restarts.

Disliking opens a feedback box requiring at least 20 characters before it can be submitted, and it blocks the rest of the chat until it's resolved — there's no way to close it and move on without either submitting or explicitly cancelling. Cancelling (the X in the top-right) undoes the dislike itself rather than letting the user skip giving feedback, so a dislike can't end up silently unaccounted for.

When `clientId`/`apiKey`/`endUserId` are all configured (see `historyEnabled` above), likes and dislikes are also reported to Chat360's `third-party-tasks` feedback API for analytics, separately from the bot's own conversational feedback message. This is automatic and requires no extra integration work; it silently no-ops if those aren't configured.

### Showing your own loading state

`startChatbot` presents the screen immediately, but the chat isn't actually usable until the socket connects. `onChatSessionReady` fires once that happens, so you can show a loader in the gap:

```swift
Chat360Bot.shared.onChatSessionReady = {
    // hide your loader
}
try? Chat360Bot.shared.startChatbot(animated: true)
```

Set it before calling `startChatbot`. It only fires for the native screen (`useNewUI: true`) — the legacy WebView screen has no equivalent connection state to key off of.

### Advanced Features

#### Back Button Handling

You can customize the back button behavior by providing a callback:

```swift
Chat360Bot.shared.startChatbot(animated: true, onBackClick: {
    // Custom back button handling
    print("Back button clicked")
}) {
    print("Chat bot presented")
}
```

#### Window Event Handling

The SDK provides a way to handle events from the web channel through the `handleWindowEvents` callback. This allows you to receive and process events from the chatbot interface:

```swift
Chat360Bot.shared.handleWindowEvents = { eventData in
    // Handle window events here
    // eventData is a dictionary containing event information
    print("Received window event: \(eventData)")
}
```

Common use cases for window event handling, this feature is for Window Event Component:

- Receiving user interactions from the chatbot
- Handling custom actions triggered by the bot
- Integrating with native app features
- Tracking conversation events and analytics
- You can send back your data to the bot by returning map data in this function

Example implementation:

```swift
let config = Chat360Config(
    botId: "YOUR_BOT_ID",
    appId: "YOUR_APP_ID",
    meta: ["user_id": "12345"]
)
Chat360Bot.shared.setConfig(chat360Config: config)

// Set up window event handler
Chat360Bot.shared.handleWindowEvents = { eventData in
    if let eventType = eventData["type"] as? String {
        switch eventType {
        case "message_sent":
            print("User sent a message")
        case "bot_response":
            print("Bot responded")
        case "conversation_ended":
            print("Chat session ended")
        default:
            print("Received event: \(eventType)")
        }
    }
    return eventData
}

try? Chat360Bot.shared.startChatbot(animated: true)
```

## Error Handling

If the URL creation fails, ensure that your `botId` and `appId` are correctly set. The SDK throws `Chat360Error.configDoesNotExit` if configuration is not set before initialization.

Example error handling:

```swift
do {
    try Chat360Bot.shared.startChatbot()
} catch Chat360Error.configDoesNotExit {
    print("Configuration not set. Call setConfig first.")
} catch {
    print("An unexpected error occurred: \(error)")
}
```
