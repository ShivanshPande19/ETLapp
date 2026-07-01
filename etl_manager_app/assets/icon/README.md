# App launcher icon

Drop the ETL logo here, then generate all platform icon sizes in one command.

## Files to add (PNG, square, 1024x1024)

1. **`app_icon.png`** — the full logo (red circle on a **white background**, no
   transparency). Used for iOS + as the base Android icon.
2. **`app_icon_foreground.png`** — the same logo art, centered, sized to roughly
   the **middle 66%** of the canvas with transparent padding around it (this is
   the Android 8+ adaptive-icon "safe zone"; the system masks it to a
   circle/squircle, so keep important art away from the edges). Transparent
   background.

> Tip: export both at 1024x1024. For `app_icon_foreground.png`, place the circle
> logo centered with ~17% empty transparent margin on every side so it isn't
> clipped by the adaptive mask.

## Generate the icons

From `etl_manager_app/`:

```bash
flutter pub get
dart run flutter_launcher_icons
```

This regenerates:
- Android: `android/app/src/main/res/mipmap-*/` + adaptive icon XML
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Config lives in `pubspec.yaml` under `flutter_launcher_icons:`.
Adaptive background is white (`#FFFFFF`) — change it there if you prefer the
brand red behind the mark.
