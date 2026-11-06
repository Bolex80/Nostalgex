# Building a shareable release APK

The debug build everyone can make with plain `gradle assembleDebug` is for development only.
A build you hand to someone else should look like this:

```
cp androidtv/keystore.properties.example androidtv/keystore.properties
# fill in storePassword / keyPassword / keyAlias / storeFile, then:
gradle --no-daemon assembleRelease
```

- With `keystore.properties` present, `assembleRelease` signs automatically (AGP signs in
  assembly; there is no `-unsigned` step).
- Without the properties file the build still completes **unsigned**, so anyone can build
  and sign under their own identity.
- The store and key passwords and the key file location live only in
  `androidtv/keystore.properties`, which is gitignored. Never commit it, and never let any
  password into this repository.

Alex's production key is outside the repository, at
`/home/alex/hermes_data/credentials/bolextv-release.keystore` (mode 600), with its passwords
in the Vaultwarden item **BolexTV release signing key (Android APK)**. Its certificate
starts `b3fb88c0…`. Do not lose it: an APK signed with a different key cannot update a TV
that installed the old one — it requires an uninstall, which erases the Plex login.

## Handing the APK to someone

Ship the file itself plus an install guide; Alex's canonical copy lives in
`/home/alex/workspace/BolexTV/` on ai-agents (`BolexTV-v1.0.0.apk` + `INSTALL-AND-SHARE.md`).
The guide covers enabling unknown sources, `adb install`, first sign-in, what the baked-in
tuner address means for people off the household network, and update behaviour.

## Verify before you send

```
build-tools/34.0.0/apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk
build-tools/34.0.0/aapt dump badging <apk> | head        # package name, versionName, sdkVersion
```

Expect `versionCode/versionName` from `app/build.gradle.kts`, and v1+v2 signature schemes,
which is enough for every sideload target from Android 6 upward.
