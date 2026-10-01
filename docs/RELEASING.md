# Publishing an automatic update

Token Galaxy uses Sparkle 2.10.0. The dependency URL and SHA-256 are pinned in `plugins/token-galaxy/scripts/prepare_sparkle.sh`; the framework is downloaded to ignored Outputs, not vendored into Git. Build/runtime tests do not start update networking. The installed app enables automatic checks only on its normal launch path.

## Signing key

The app embeds the public key in `Resources/UpdatePublicKey.txt`. Release archives and the appcast must be signed by the matching private Ed25519 seed. The maintainer's seed is stored outside Git at `~/Library/Application Support/TokenGalaxy/UpdateSigning/ed25519.key`, with mode 600 and a private parent directory. Back this key up securely; do not put it into commits, release assets, logs, prompts or command-line arguments. Sparkle receives only its file path. Losing this key can break the automatic-update trust chain; do not regenerate it for a routine release.

Sparkle signatures are independent of Apple code signing/notarization. Current bundles are ad-hoc signed and not notarized. First-time downloads may require macOS approval. Existing app preferences use the same bundle identifier and survive upgrades.

## Build, verify, publish

1. Bump both `CFBundleShortVersionString` and monotonic `CFBundleVersion` in the plugin's `build.sh`; update `.codex-plugin/plugin.json` and the changelog. The runtime version comes from the built Info.plist.
2. Build and run the native self-tests and UI smoke tests on synthetic data. Review the changes and commit them. CI must pass for the release commit.
3. Package both architectures and generate signatures, supplying a plain-text notes file:

   ```sh
   python3 scripts/package_release.py --reuse-native \
     --key-file "$HOME/Library/Application Support/TokenGalaxy/UpdateSigning/ed25519.key" \
     --notes /path/to/release-notes.txt
   ```

   `--reuse-native` requires a freshly built/tested native app. Omit it to rebuild both architectures. The script refuses stale versions or mismatched architecture metadata, verifies signatures against the embedded public key, and never publishes. Assets are written to the ignored `Outputs/release-VERSION/assets` directory. Existing assets are not overwritten.
4. Create a **draft** GitHub release targeting the tested commit. Upload the universal zip, `appcast.xml` and `SHA256SUMS.txt`. Do not change an archive or signed appcast after signing.
5. Check the release commit, assets and checksums, then publish it as the latest stable release. The fixed feed URL is `https://github.com/ssg87/token-galaxy/releases/latest/download/appcast.xml`; every new stable release must include the feed asset. A source push alone does not trigger updates.
6. Verify the live feed and archive. `python3 scripts/check_updater.py --app "/path/to/Token Galaxy.app"` checks SDK startup offline. Add `--online --build-offset -1` to verify that an older build sees the release, then use `--online` alone to verify that the current build is up to date. The script uses isolated bundles ending in `.update-test`, disables automatic downloading/installing, and never starts or replaces the installed app. Packaging and CI run the offline startup check before publication.

The appcast is also signed (`SURequireSignedFeed`), with its required `SUVerifyUpdateBeforeExtraction` prerequisite and non-expiring signature validation. `generate_appcast` handles its signature. The `sign_update --verify` tool can validate both appcast and archive; the independent `scripts/verify_update_archive.swift` validates archives with the app's public key. A tampered archive must fail verification.

## User behavior

“自动更新” changes automatic checking and downloading together. The default interval is 24 hours. Sparkle schedules the installation and may ask the user to relaunch or authorize it when needed. It does not promise installation at an exact wall-clock time. Manual checks stay available with automation off. Network/signature failures must leave the current app usable.

## Bootstrap

0.9.1 is the first version containing Sparkle. Users on 0.8.6 or earlier must install it once manually; publishing a feed cannot retrofit an updater into those old binaries. Intel runtime is tested; the universal arm64 slice is built and inspected but still needs native Apple Silicon runtime testing.
