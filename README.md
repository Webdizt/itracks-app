# iTracks App

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
## Local configuration

The app uses the authenticated login session by default. If a legacy API
endpoint requires an additional bearer token, provide it only at build time;
do not store it in source control:

```powershell
flutter run --dart-define=API_STATIC_TOKEN=<token>
```
