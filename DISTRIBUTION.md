# MyHelper Distribution

This app is distributed outside the Mac App Store as a downloadable DMG.

## Supported targets

- macOS 14 or later.
- Apple Silicon Macs with the `arm64` DMG.
- Intel Macs with the `x86_64` DMG.
- `make release` builds the current host architecture by default. Use the explicit architecture targets below when preparing GitHub Release artifacts.
- A local Codex installation and a signed-in Codex account are required for account quota data.

## Local unsigned DMG

Use this for private testing or installation on your own machines:

```sh
make clean dmg
```

The artifact is written to:

```text
dist/MyHelper-<version>-mac-<arch>.dmg
```

Because this build is ad-hoc signed, another Mac may show a Gatekeeper warning on first launch.

If macOS blocks the app, open **System Settings > Privacy & Security**, scroll to
the **Security** section, click **Open Anyway** for `MyHelper.app`, then confirm
with Touch ID or your password. Finder right-click > **Open** also shows the
manual allow prompt.

To build an Intel-only artifact from a compatible toolchain:

```sh
make release-intel
```

This writes `dist/MyHelper-<version>-mac-x86_64.dmg` and its `.sha256` file.

To build an Apple Silicon artifact explicitly:

```sh
make release-arm64
```

To build both Release DMGs in one command:

```sh
make release-all
```

You can still override the target triple directly when needed:

```sh
make clean release TARGET_TRIPLE="x86_64-apple-macos14.0"
```

## Release DMG with checksum

```sh
make release
```

This creates the DMG and a `SHA-256` checksum file next to it.

## Build from GitHub Actions

The repository includes a manual workflow for packaging from the GitHub web UI:

1. Open the repository on GitHub.
2. Go to **Actions**.
3. Select **Build macOS DMG**.
4. Click **Run workflow**.
5. Choose `arm64` or `x86_64`.
6. Leave **Create or update a GitHub Release** unchecked if you only want a downloadable workflow artifact.
7. Check it and provide a tag such as `v1.0.0-beta02` if you want the DMG uploaded to GitHub Releases.

The workflow writes:

```text
dist/MyHelper-<version>-mac-<arch>.dmg
dist/MyHelper-<version>-mac-<arch>.dmg.sha256
```

The default GitHub Actions build uses ad-hoc signing. It is useful for internal
testing, but other Macs may still show a Gatekeeper warning until a Developer ID
signed and notarized release pipeline is configured.

## Developer ID signed build

For broad distribution outside the App Store, sign with a Developer ID Application certificate:

```sh
make clean dmg SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DMG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The app bundle is signed with hardened runtime and timestamping when `SIGN_IDENTITY` is not `-`.

## Notarization

After building with a Developer ID certificate, notarize and staple the DMG:

```sh
make notarize \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DMG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  APPLE_ID="you@example.com" \
  TEAM_ID="TEAMID" \
  NOTARY_PASSWORD="app-specific-password"
```

`NOTARY_PASSWORD` should be an Apple app-specific password or a keychain profile value accepted by `xcrun notarytool`.

## Verify an artifact

```sh
hdiutil verify dist/*.dmg
hdiutil attach dist/*.dmg
codesign --verify --deep --strict "/Volumes/MyHelper/MyHelper.app"
```

For notarized releases, also run:

```sh
spctl -a -t open --context context:primary-signature -v dist/*.dmg
```

## Runtime dependencies

The app does not bundle Codex. It reads:

- `codex app-server` from the local Codex installation.
- `~/.codex/state_5.sqlite` for local token and thread statistics.
- `~/.codex/automations/**/automation.toml` for enabled automation tasks.

If Codex changes its app-server API or local SQLite schema, the widget should fail into a partial-data mode instead of blocking launch.
