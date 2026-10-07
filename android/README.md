# Cuba Match Explorer for Android

Android package: `com.imgcubajourney.matchexplorer`. Version 5.3.3 (5303), Android 8.0/API 26 or newer, target API 36.

This Trusted Web Activity opens https://cubamatchexplorer.org/ using Android Browser Helper 2.6.2. It uses the user's compatible browser for authentication and the live website; no applicant records, backend keys or web content snapshots are bundled. A browser that does not support Trusted Web Activities may display the website in a Custom Tab. Internet and a compatible browser are required. Offline availability follows the website service worker; no offline data access is guaranteed.

Build with JDK 17, Gradle 8.13 and Android SDK platform 36/build-tools 35.0.0:

```
gradle --no-daemon -p android :app:assembleRelease :app:lintRelease
```

The GitHub Actions workflow produces an **unsigned** APK. Before distribution, align and sign it with the owner's retained release key using Android `zipalign` and `apksigner`; verify with `apksigner verify --verbose --print-certs`. Signing keys and passwords must never be committed or uploaded as CI artifacts. Update `.well-known/assetlinks.json` only when the signing identity changes.

The historical v1 test APK used a different temporary certificate. It cannot be updated in place using the new release signature; testers must uninstall that old APK before installing this release. This APK is for direct installation, not a claim of Play Store approval.

The artifact's signature, manifest, target URL, logo resources and build are checked during preparation. Device installation, login, back navigation and session persistence still require an Android device/emulator check; do not claim those passed without running them.


Version 5.3.3 changes the launcher artwork and adaptive icon background to white. It retains the package identifier and release signing identity so the signed APK can update version 5.3.2 in place.
