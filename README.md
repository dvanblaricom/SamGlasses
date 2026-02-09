# Sam Glasses

A companion iOS app for Meta Ray-Ban smart glasses that connects to OpenClaw for AI-powered voice interactions.

## Overview

Sam Glasses enables hands-free AI conversations through Meta Ray-Ban smart glasses by leveraging:

- **OpenClaw**: AI gateway for chat completions, TTS, and Whisper transcription
- **Bluetooth HFP**: Audio routing through glasses microphone and speakers
- **Swift Concurrency**: Modern async/await patterns for seamless user experience
- **SwiftUI**: Native iOS interface with real-time status updates

## Features

### Current Features
- ✅ Voice-to-voice AI conversations via OpenClaw
- ✅ Bluetooth audio routing to Ray-Ban glasses
- ✅ On-device + cloud speech recognition (Apple Speech + OpenClaw Whisper)
- ✅ High-quality TTS via OpenClaw Edge TTS
- ✅ Real-time conversation history
- ✅ Secure auth token storage in Keychain
- ✅ Connection status monitoring

### Planned Features
- 🔄 Camera capture and vision analysis (requires Meta DAT)
- 🔄 Wake word detection
- 🔄 Offline mode with cached conversations
- 🔄 Multi-language support
- 🔄 Custom voice commands and shortcuts

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   SwiftUI App   │    │   Ray-Ban       │    │   OpenClaw      │
│                 │    │   Smart Glasses │    │   Gateway       │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • MainView      │    │ • Microphone    │    │ • Chat API      │
│ • SettingsView  │◄──►│ • Speakers      │◄──►│ • TTS Service   │
│ • Status        │    │ • Bluetooth HFP │    │ • Whisper STT   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Service Layer   │    │ Audio Pipeline  │    │ Network Layer   │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • OpenClawClient│    │ • AudioManager  │    │ • URLSession    │
│ • SpeechManager │    │ • AVAudioSession│    │ • Tailscale     │
│ • TTSManager    │    │ • AVAudioEngine │    │ • Auth Headers  │
│ • AudioManager  │    │ • HFP Routing   │    │ • Error Handling│
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Setup Instructions

### Prerequisites

1. **Meta Ray-Ban Smart Glasses** with Bluetooth connectivity
2. **OpenClaw Gateway** running and accessible via Tailscale
3. **iOS Device** (iPhone/iPad) running iOS 15.2+
4. **Xcode 14+** for building the app

### Installation

1. **Clone and Build**
   ```bash
   cd /Users/dvbii/Development/SamGlasses
   open Package.swift  # Opens in Xcode
   ```

2. **Configure OpenClaw Gateway**
   - Ensure OpenClaw is running with Tailscale access
   - Note your gateway URL: `https://daves-mac-studio.taile75ef.ts.net`
   - Generate an auth token: `openclaw auth token`

3. **Pair Ray-Ban Glasses**
   - Enable Bluetooth on your iPhone
   - Pair glasses through Settings > Bluetooth
   - Ensure HFP (Hands-Free Profile) is connected

4. **App Configuration**
   - Launch Sam Glasses app
   - Open Settings (gear icon)
   - Enter your OpenClaw auth token
   - Verify connection status shows "Connected"
   - Grant microphone and speech recognition permissions

### Usage

1. **Basic Conversation**
   - Tap the blue "Tap to Talk" button
   - Speak your question/request
   - Tap "Stop Recording" when done
   - Listen to AI response through glasses speakers

2. **Quick Actions**
   - "Identify" - Ask "What am I looking at?" (vision placeholder)
   - "Ask" - Ask "What should I do next?"

3. **Settings**
   - Configure preferred TTS voice
   - Adjust speech rate
   - Choose on-device vs cloud speech recognition
   - Select audio device routing

## Development Notes

### Project Structure

```
Sources/SamGlasses/
├── App/
│   └── SamGlassesApp.swift          # App entry point
├── Services/
│   ├── OpenClawClient.swift         # Core API client
│   ├── AudioManager.swift           # Bluetooth HFP audio
│   ├── SpeechManager.swift          # Speech recognition
│   └── TTSManager.swift             # Text-to-speech
├── Views/
│   ├── MainView.swift               # Primary interface
│   └── SettingsView.swift           # Configuration UI
├── Models/
│   └── ConversationMessage.swift    # Message data model
└── Utilities/
    └── KeychainHelper.swift         # Secure storage
```

### Key Components

- **OpenClawClient**: Central API client handling all OpenClaw communication
- **AudioManager**: Manages Bluetooth HFP routing to glasses
- **SpeechManager**: Dual-mode speech recognition (on-device + cloud)
- **TTSManager**: High-quality TTS with audio routing
- **KeychainHelper**: Secure credential storage

### Swift Patterns Used

- **@MainActor**: UI-safe async operations
- **@Observable / @StateObject**: Reactive data flow
- **async/await**: Modern concurrency throughout
- **Combine**: Publisher/subscriber for real-time updates
- **URLSession**: HTTP client with proper error handling

### API Endpoints

- **Chat Completions**: `POST /v1/chat/completions`
- **TTS**: `POST /tts` (assumed)
- **Whisper**: `POST /whisper` (assumed)
- **Health Check**: `GET /health` (assumed)

## Meta Ray-Ban Integration

### Audio Pipeline
1. **Recording**: Glasses mic → Bluetooth HFP → iOS AudioEngine
2. **Processing**: Audio data → Speech recognition → OpenClaw chat
3. **Response**: OpenClaw TTS → iOS AudioSession → Bluetooth HFP → Glasses speakers

### Camera Integration (Future)
- Requires Meta DAT (Device Access Token)
- Will enable real-time vision analysis
- Image capture → Base64 encoding → OpenClaw vision model

## Troubleshooting

### Connection Issues
- Verify Tailscale connectivity: `ping daves-mac-studio.taile75ef.ts.net`
- Check OpenClaw service status
- Validate auth token with `openclaw auth whoami`

### Audio Issues
- Ensure Ray-Ban glasses are connected via Bluetooth
- Check HFP profile is active (not just A2DP)
- Verify microphone permissions granted
- Test with built-in iPhone audio first

### Speech Recognition Issues
- Grant Speech Recognition permission in iOS Settings
- Try toggling between on-device and cloud recognition
- Check internet connectivity for Whisper fallback
- Verify supported language selection

## Contributing

1. Follow Swift style guidelines
2. Use async/await for all async operations
3. Add comprehensive error handling
4. Write unit tests for service classes
5. Document public APIs with Swift DocC

## License

MIT License - See LICENSE file for details

## Support

- **Documentation**: [OpenClaw Docs](https://docs.openclaw.dev)
- **Issues**: GitHub Issues
- **Meta Ray-Ban**: [Meta Developer Portal](https://developers.meta.com)

---

*Built with ❤️ for seamless AI-powered smart glasses experiences*