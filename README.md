# Chat360 Swift Library

Chat360 is a Swift library that lets you embed a full chatbot conversation screen into your iOS app. It ships a native SwiftUI chat interface (message list, drawer/history, input bar, theming) that you configure and present with a few lines of code.

## Features

- Native SwiftUI chat screen — no WebView required.
- Fully themeable: colors (light/dark), typography, and branding (logo, copy) via `Chat360Config`.
- Feature flags to show/hide individual pieces of chrome (menu, history drawer, new chat, feedback, regenerate, voice input, close button, etc.) via `Chat360UIConfig`.
- Conversation history with local caching, resume-on-relaunch, and room switching. In the
  history drawer only the conversation list scrolls — the "New chat" button and the Assistant
  Mode / Appearance / Language controls stay pinned. On short (landscape) screens, where pinning
  everything would leave no room for the list, the whole drawer scrolls as one piece instead.
- Bot responses containing an HTML `<table>` render as an actual aligned table, with cells that
  wrap and grow to fit their content instead of truncating or overlapping adjacent rows.
- Nudge/quick-reply options render as comma-separated underlined links (wrapping onto multiple
  lines for long options) rather than stacked full-width buttons.
- A 1-hour session countdown timer, anchored to the server's real session start time — it shows
  up the instant you open a conversation with time left, not only after sending a message, and
  resumes correctly (rather than resetting) when switching between conversations.
- A conversation is automatically checked for a missed reply whenever it's reopened (after
  switching rooms, backgrounding, or restarting the app while the bot was still responding). A
  reply that never actually arrives marks the message "Not delivered" with tap-to-retry; the
  connection-error banner also has an explicit Retry button.
- Like/dislike on bot messages, persisted locally across app restarts. Disliking opens a
  mandatory feedback box (min 20 characters) that blocks the chat until submitted or
  cancelled — cancelling undoes the dislike rather than letting feedback be skipped. Dislike
  is permanent once set; a like can still be switched to a dislike afterward, but not the
  reverse. When `clientId`/`apiKey`/`endUserId` are configured, reactions are also reported to
  Chat360's `third-party-tasks` feedback API.
- Optional periodic feedback prompt (`showPeriodicFeedbackPrompt`, defaults to `true`) — a
  mandatory, un-dismissable "how's it going so far?" text box that can appear every random 3-5
  bot replies.
- `onChatSessionReady` callback so the host app can show its own loading state between
  presenting the chat screen and the connection actually being live.
- Configurable parameters for customization (bot ID, app ID, debug mode, etc.).
- Supports sending metadata (`meta`) that pre-seeds the bot flow's `@`-variables at session
  start — on both the native screen and the legacy WebView.
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

### Step 5: Window Events (data exchange with the bot flow)

If your bot flow uses a **Window Event** node, the SDK hands that node's payload to your app and
sends your reply back so the flow can continue. Register a handler before presenting the chat —
see [Window Event Handling](#window-event-handling) below. On the legacy WebView screen you can
also push an event to the bot with `Chat360Bot.shared.sendEventToBot(event:)`.

## Configuration Options

### Basic Configuration

- **botId**: The ID of your chatbot.
- **appId**: Your application ID.
- **useNewUI**: `Bool` — presents the native SwiftUI chat screen when `true`. Defaults to `false` (legacy WebView).
- **isDebug**: points requests at Chat360's staging environment when `true`.
- **meta**: `[String: String]` of extra key/value pairs sent at session init (as a compact JSON
  string). The backend seeds these into the conversation's flow variables, so a value passed as
  `meta: ["user_id": "12345"]` is readable in the flow as `@user_id`. Applies to the native
  screen and the legacy WebView alike.
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
        showRegenerate: false,       // regenerate icon on bot messages (off by default)
        showVoiceInput: true,        // mic / voice note button
        showAssistantMode: true,     // Training/Customer toggle in the drawer
        showAppearanceSwitcher: true,// manual Light/Dark toggle in the drawer
        showClose: true,             // header close (X) button — see note below
        showPeriodicFeedbackPrompt: true // mandatory "how's it going?" prompt every ~3-5 bot replies
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

A **Window Event** node in the bot flow is a request/response step: the flow sends your app a
payload and then pauses until your app answers with the values it asked for. On the web this is
served by the host page; in a native app your code provides the answer through
`Chat360Bot.shared.handleWindowEvents`.

```swift
Chat360Bot.shared.handleWindowEvents = { sendData in
    // `sendData` is the node's payload, e.g. ["type": "get_details"] — the keys are defined
    // by whoever built the flow, not by the SDK.
    // Return the values the flow expects back, keyed exactly as the node's "receive data".
    return ["emp_id": currentEmployeeId, "dealer_id": currentDealerId]
}
```

- The closure is **synchronous** — return the dictionary directly. Return `[:]` if you have
  nothing to contribute.
- Register it **before** calling `startChatbot`.
- If the flow reaches a Window Event node and no handler is registered (or the handler returns
  `[:]` when the node needs data), the flow has nothing to advance on and the conversation will
  appear to hang — Window Event nodes are not shown in the transcript. Make sure any flow that
  uses one has a handler that answers it.

Example:

```swift
let config = Chat360Config(botId: "YOUR_BOT_ID", appId: "YOUR_APP_ID", useNewUI: true)
Chat360Bot.shared.setConfig(chat360Config: config)

Chat360Bot.shared.handleWindowEvents = { sendData in
    switch sendData["type"] {
    case "get_details":
        return ["emp_id": Session.current.employeeId, "dealer_id": Session.current.dealerId]
    default:
        return [:]
    }
}

try? Chat360Bot.shared.startChatbot(animated: true)
```

On the legacy WebView screen (`useNewUI: false`), `Chat360Bot.shared.sendEventToBot(event:)`
pushes an event into the embedded page.

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
