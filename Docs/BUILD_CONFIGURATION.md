# AstroJournal build configuration

AstroJournal users do not enter server addresses or provider credentials in the app. The release build embeds the mobile-side settings, while Weather, Geocoding, Places, Astrometry, and Vision credentials remain on TC-Backend.

## First setup on a development PC

1. Copy `config/local.env.example` to `config/local.env`.
2. Fill `GOOGLE_MAPS_API_KEY` with the Android Maps SDK key.
3. Fill `TC_BACKEND_AUTH_TOKEN` with the AstroJournal client token.
4. Fill `TC_BACKEND_URL_INTERNAL` and `TC_BACKEND_URL_EXTERNAL` with the two
   trusted endpoints. Leave `TC_BACKEND_URL` empty unless a legacy
   single-endpoint build is required.

`config/local.env` is ignored by Git. Do not add it or paste its contents into build logs, issues, or documentation. `android/local.properties` remains only for the Android SDK path and does not need credential edits.

Backend endpoints are supplied only through the untracked `config/local.env` file. Use `TC_BACKEND_URL_INTERNAL` and `TC_BACKEND_URL_EXTERNAL` for automatic reachability-based selection. The legacy `TC_BACKEND_URL` remains a single-endpoint fallback; normal users cannot change these values at runtime.

## Release APK

From the project root run:

```powershell
.\scripts\build_app.ps1 -Mode Debug
.\scripts\build_app.ps1 -Mode Release
```

`scripts/build_release.ps1` remains as a backward-compatible Release wrapper.

The helper validates both required values without printing them, runs `flutter pub get`, injects the backend token through a temporary Dart-define file, builds the release APK, removes the temporary file, and prints the APK path and size.

Release builds fail fast when either required value is absent. `flutter analyze` and `flutter test` remain credential-free.

## Fixed release package locations

Run these commands from the project root:

```powershell
.\build.ps1 android
.\build.ps1 windows
.\build.ps1 all
```

The wrapper uses `scripts/build_app.ps1` for the existing credential checks and
build-time injection. It publishes only after a successful Release build. The
Android APK is `dist/android/AstroJournal.apk`. The complete Windows package
is in `dist/windows/`, with `AstroJournal.exe` alongside its DLLs and
`data/` directory. Keep that entire Windows folder together when copying it.
The previous package is retained if the build fails. `dist/` is ignored by Git.

On Windows, the app database lives in the user's application support directory
(`%APPDATA%/com.example/astro_journal/databases/` for the current Windows
runner metadata), outside the release package. Existing development databases
created under the former working-directory-based `.dart_tool/sqflite_common_ffi/databases/`
path must be backed up and copied to the new location before first launch.
Do not delete the original database.
