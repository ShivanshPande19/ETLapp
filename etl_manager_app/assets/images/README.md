# App image assets

Drop the official ETL logo here as:

    assets/images/etl_logo.png

Recommended: a square PNG with a transparent background, at least 512x512 px
(the "EAT TRUCK LOVE by Azimuth" red-circle logo).

The splash screen (`lib/app/splash_screen.dart`) loads `etl_logo.png` from this
folder. Until the file is added, the splash shows a built-in fallback badge, so
the app still builds and runs fine.
