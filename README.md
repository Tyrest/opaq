# opaq

Menu bar app that reads `~/Library/Messages/chat.db` in read-only mode and matches handles to Contacts, so replies you still owe stay visible. Behavior is specified in [PLAN.md](PLAN.md).

## Requirements

- macOS 26
- Xcode toolchain (Swift tools 6.2)

## Develop

```bash
make build   # release app bundle at ./opaq.app
make run     # debug build, then launch the debug binary
make test    # swift test
make format  # format Sources and Tests in place
```

`make debug` builds without launching. `make format-check` lints Sources and Tests and exits non-zero when they drift from `.swift-format`.

The app version lives in `Sources/opaq/AppVersion.swift`. Edit `AppVersion.marketing`, then run `make build` so the bundle version matches.

## Permissions

Grant Full Disk Access so opaq can read `~/Library/Messages/chat.db`, and Contacts so it can match names and avatars. The app is read-only.

## Signing

Ad-hoc signatures change cdhash on every rebuild, and macOS drops Full Disk Access. Run `scripts/setup-signing.sh` once so `build_app.sh` signs with the stable `opaq-dev` identity. Override that name with `OPAQ_SIGN_IDENTITY`. If the script imports the certificate but `build_app.sh` still warns, open Keychain Access, select `opaq-dev`, and set Code Signing to Always Trust. `security find-identity -v -p codesigning` only lists trusted identities.
