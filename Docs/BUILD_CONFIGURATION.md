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

## Dedicated personal Android Release signing

Android Release uses a dedicated key, not the automatic Debug key. Debug builds
retain their standard Debug signing. On Windows, initialize the Release identity
**once** with `scripts/android_release_signing.ps1 -CreateKey`. This refuses to
overwrite existing signing material. Normal Release builds load the existing key
through `scripts/build_app.ps1 -Mode Release`.

The private key is outside the repository at
`%USERPROFILE%/.astrojournal-signing/release/astrojournal-release.p12`.
The sibling `password.dpapi` contains a random password encrypted for the current
Windows account; `release-public.cer` is a public certificate. Directory access
is restricted to the owning account and SYSTEM. Passwords are passed through
temporary process environment variables, not command-line values or source.

Before replacing `dist/android/AstroJournal.apk`, the build helper verifies the
APK signature against this certificate and checks the package, versionCode and
non-debuggable variant. The previous dist APK is copied to a uniquely named
`AstroJournal.previous-*.apk` backup. Verification/build failure leaves dist intact.

### Permanent backup and future updates

- Keep this signing key for every future phone/tablet update. Never recreate it
  to solve a build failure. Increase versionCode for each release.
- Back up the `.p12` and public certificate to at least two encrypted, separate
  locations (for example an encrypted offline drive and a password-manager vault).
- **DPAPI ciphertext alone is not a portable password backup.** A Windows
  reinstall or another account/computer may not decrypt `password.dpapi`.
  Save the underlying password separately in a trusted password manager.
- To transfer the password without printing it, the owner can manually run the
  following in a private local PowerShell session, paste into the password manager,
  and then clear the clipboard. Disable clipboard history/cloud synchronization
  first. Do not run this in a shared/recorded terminal or CI:

  ```powershell
  $signingSecret = Get-Content "$env:USERPROFILE\.astrojournal-signing\release\password.dpapi" -Raw | ConvertTo-SecureString
  $signingCredential = [PSCredential]::new('AstroJournalRelease', $signingSecret)
  Set-Clipboard -Value $signingCredential.GetNetworkCredential().Password
  Remove-Variable signingCredential, signingSecret
  # After pasting into the password manager:
  Set-Clipboard -Value ''
  ```

The build agent does not execute this clipboard-export procedure. No password
or private key should be pasted into chat, source files, Git or build logs.

The new key cannot update older APKs signed with unrelated Debug keys in place.
Any reinstall/data transfer must be handled separately by the owner; build
scripts never install/uninstall apps or reset data. Register the new certificate
SHA-1 for the Android package in Google Cloud if the Maps API key has Android
certificate restrictions. This does not require changing the Backend.

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
