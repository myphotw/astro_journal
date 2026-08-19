# AstroJournal build configuration

AstroJournal users do not enter server addresses or provider credentials in the app. The release build embeds the mobile-side settings, while Weather, Geocoding, Places, Astrometry, and Vision credentials remain on TC-Backend.

## First setup on a development PC

1. Copy `config/local.env.example` to `config/local.env`.
2. Fill `GOOGLE_MAPS_API_KEY` with the Android Maps SDK key.
3. Fill `TC_BACKEND_AUTH_TOKEN` with the AstroJournal client token.

`config/local.env` is ignored by Git. Do not add it or paste its contents into build logs, issues, or documentation. `android/local.properties` remains only for the Android SDK path and does not need credential edits.

The application uses `https://onepieces.synology.me:8443` by default. Developers may add `TC_BACKEND_URL` to the local file for a build-time override; normal users cannot change it at runtime.

## Release APK

From the project root run:

```powershell
.\scripts\build_release.ps1
```

The helper validates both required values without printing them, runs `flutter pub get`, injects the backend token through a temporary Dart-define file, builds the release APK, removes the temporary file, and prints the APK path and size.

Release builds fail fast when either required value is absent. `flutter analyze` and `flutter test` remain credential-free.
