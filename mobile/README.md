# Rohomieo iOS / Flutter viewer

Same signaling + WebRTC flow as the web PWA.

## Setup

```bash
# Install Flutter SDK, then from this directory:
flutter create . --platforms=ios   # adds full ios/ runner if missing
flutter pub get
cd ios && pod install && cd ..
flutter run -d ios
```

## VPN + ATS

- Connect WireGuard before opening the app.
- Default signaling URL: `wss://10.8.0.20:8443/ws`
- [ios/Runner/Info.plist](ios/Runner/Info.plist) allows the VPN subnet for dev; replace with your cert/CN for production.

## Background

iOS suspends WebRTC in background — keep the app foreground while controlling.
