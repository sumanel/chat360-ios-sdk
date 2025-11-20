# Chat360 Swift Library

Chat360 is a Swift library that allows you to easily integrate a chatbot interface into your iOS applications using a WebView. This library simplifies the process of configuring and displaying the Chat360 chatbot.

## Features

- Easy integration of Chat360 chatbot in your iOS app.
- Configurable parameters for customization (bot ID, app ID, debug mode, etc.).
- Supports sending metadata to enhance chatbot functionality.
- Back button navigation support with custom callback handlers
- Lightweight and easy to use.

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

## Usage

### Step 1: Import the Library

Import the Chat360 library in your Swift file:

```swift
import Chat360SDK
```

### Step 2: Configure the Chat360Bot

Create an instance of `Chat360Config` with your bot and app IDs:

```swift
    let chatConfig = Chat360Config(botId: "YOUR_BOT_ID", appId: "YOUR_APP_ID",)
```

### Step 3: Display the ChatBot

You can present the Bot View using below code:

```swift
    Chat360Bot.shared.setConfig(chat360Config: config)
    try? Chat360Bot.shared.startChatbot(animated: true)
```

### Step 4: Close the ChatBot

You can close the Bot View using below code:

```swift
    try? Chat360Bot.shared.closeChatBot(animated: true)
```

### Step 5: To Send Events to Bot

You can send events to the Bot View using below code:

```swift
    try? Chat360Bot.shared.sendEventToBot(event: event)
```

## Configuration Options

### Basic Configuration

- **botId**: The ID of your chatbot.
- **appId**: Your application ID.
- **meta**: A dictionary for sending additional metadata as a JSON string.

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
- You can send back you data to the bot by returing map data in this function

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
