# opaq

Menu bar list of iMessage replies you still owe.

## Install

Download `opaq-<version>.dmg` from [Releases](https://github.com/Tyrest/opaq/releases). Open the disk image and drag `opaq.app` into Applications.

macOS will refuse the first open. Release builds are ad-hoc signed and not notarized.

1. Open opaq once so macOS records the attempt.
2. Open System Settings → Privacy & Security.
3. Click **Open Anyway**, then **Open**.

Then grant the two permissions the app asks for:

- **Full Disk Access**, so opaq can read `~/Library/Messages/chat.db`.
- **Contacts**, so it can match phone numbers and emails to names and avatars.

The app is read-only. It never writes to Messages.

## Updates

Each GitHub build is ad-hoc signed, so its code signature changes every release. macOS drops Full Disk Access when that happens. After you install an update, grant Full Disk Access to opaq again. Contacts usually stays granted.

## Privacy

opaq stays on your Mac.

- It reads `~/Library/Messages/chat.db` in read-only mode.
- It reads Contacts for names and avatars.
- It stores settings in UserDefaults.
- It has no network code.

## Requirements

- Apple Silicon
- macOS 26 or later

## Build it yourself

Xcode toolchain (Swift tools 6.2).

```bash
make build   # release app bundle at ./opaq.app
make dmg     # dist/opaq-<version>.dmg
make run     # debug build, then launch the debug binary
make test    # swift test
make format  # format Sources and Tests in place
```

`make debug` builds without launching. `make format-check` lints Sources and Tests and exits non-zero when they drift from `.swift-format`.

The app version lives in `Sources/opaq/AppVersion.swift`. Edit `AppVersion.marketing`, then run `make build` so the bundle version matches.

Release builds from GitHub are ad-hoc signed. On your own machine, run `scripts/setup-signing.sh` once so `build_app.sh` signs with the stable `opaq-dev` identity. That certificate is local only. It keeps Full Disk Access across your rebuilds. Override the name with `OPAQ_SIGN_IDENTITY`. If the script imports the certificate but `build_app.sh` still warns, open Keychain Access, select `opaq-dev`, and set Code Signing to Always Trust. `security find-identity -v -p codesigning` only lists trusted identities.

## License

MIT. See [LICENSE](LICENSE).
