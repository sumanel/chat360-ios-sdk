# Chat360 Swift Library

Chat360 is a Swift library that allows you to easily integrate a chatbot interface into your iOS applications using a WebView. This library simplifies the process of configuring and displaying the Chat360 chatbot.

## Features

- Easy integration of Chat360 chatbot in your iOS app.
- Configurable parameters for customization (bot ID, app ID, debug mode, etc.).
- Supports sending metadata to enhance chatbot functionality.
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
import Chat360Sdk
```

### Step 2: Configure the Chat360Bot

Create an instance of `Chat360Config` with your bot and app IDs:

```swift
    let chatConfig = Chat360Config(botId: "YOUR_BOT_ID", appId: "YOUR_APP_ID",)
```

### Step 3: Display the ChatBot

You can present the `Chat360BotView` using your preferred method (e.g., modal presentation, navigation controller, etc.):

```swift
    Chat360Bot.shared.setConfig(chat360Config: config)
    try Chat360Bot.shared.startChatbot(animated: true)
```

## Configuration Options

- **botId**: The ID of your chatbot.
- **appId**: Your application ID.
- **flutter**: Set to `true` if you are using Flutter SDK.
- **meta**: A dictionary for sending additional metadata as a JSON string.

## Error Handling

If the URL creation fails, ensure that your `botId` and `appId` are correctly set. You can handle potential errors in your app as needed.
