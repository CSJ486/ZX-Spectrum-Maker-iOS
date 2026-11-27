# ZX Tape Loader (iOS)

iPhone and iPad app that wraps the single-file **ZX Spectrum Mobile Tape & Image Loader / ASM Converter v1.5.2.9** web app in a `WKWebView`.
It works fully offline and needs no special permissions.

## What's included
- The full web app, bundled as `ZXTapeLoader/index.html`
- Your app icon (`Assets.xcassets/AppIcon`) and splash image (`Assets.xcassets/Splash` + `LaunchScreen.storyboard`); the splash also fades out inside the app after the page loads
- **Saving files:** `.TAP`, `.TZX`, `.WAV` and listing downloads are written to the app's Documents folder (visible in the Files app under *On My iPhone > ZX Tape Loader*) and the share sheet opens so you can save them elsewhere
- Image/file pickers, UI sounds and tape playback (audio plays even with the silent switch on)
- Safe-area layout for notch / Dynamic Island, iPhone and iPad, all orientations

## iOS versions
| Setting | Value |
|---|---|
| Minimum iOS (deployment target) | **11.0** |
| Built against (base SDK) | the SDK of the Xcode you use: Xcode 16 = iOS 18, Xcode 26 = iOS 26 |
| Liquid Glass | Automatic on iOS 26+ when built with Xcode 26. The save toast uses a glass effect there and a normal blur on older iOS |

Apple has no "target SDK" setting like Android. Your app is *built against* the newest SDK and *runs on* everything down to the deployment target.

**Important:** current Xcode versions no longer support iOS 11 as a deployment target (Xcode 16 and later start at iOS 12, and Apple's own App Store validation currently asks for iOS 15 or newer). The project is set to 11.0 as you asked, and the GitHub workflow tries 11.0, then 12.0, 13.0 and 15.0 until one builds, then writes which one worked into `build-info.txt`. If Xcode refuses 11.0 on your Mac, set *Minimum Deployments* to the lowest value it accepts (Project > Info).

## Build the IPA on GitHub (no Mac needed)
1. Upload everything in this folder to a new GitHub repository (keep the `.github` folder).
2. Open the **Actions** tab. **Build iOS app** runs on every push, or choose **Run workflow**.
3. Download the **ZXTapeLoader-unsigned-ipa** artifact.

iOS apps are `.ipa` files, not `.apk` (that is Android). The IPA from GitHub is **unsigned**: Apple only lets signed apps run, so install it with a tool that signs it with your Apple ID, such as AltStore or Sideloadly, or sign it with a paid Apple Developer account for TestFlight / App Store.

## Build in Xcode (Mac)
1. Open `ZXTapeLoader.xcodeproj`.
2. Select the **ZXTapeLoader** target > Signing & Capabilities, choose your Team, and change the Bundle Identifier from `com.zxtape.loader` to your own.
3. Pick a device or simulator and press Run.

## Updating the web app
Replace `ZXTapeLoader/index.html` with a newer build (keep the name). Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the target's build settings.

## Notes
- The app uses the classic `AppDelegate` lifecycle because iOS 11 has no scenes. Newer iOS versions may print a console notice about adopting scenes; the app still runs.
- Liquid Glass code is wrapped in `#if compiler(>=6.2)`, so older Xcode versions skip it and still build.
