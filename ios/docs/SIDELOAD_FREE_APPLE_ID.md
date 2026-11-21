# Install this branch on an iPhone with a free Apple ID

This is for James. It is a personal sideload of his fork, not an App Store build and not something to send upstream. The normal `enve` scheme is unchanged. Use the separate scheme **`enve-sideload`**.

Nothing in this file was installed on a phone. There is no Xcode on the machine that prepared it. Steps that come from the project files are marked **checked in the project**. Steps that depend on Xcode, a free Apple ID, or the iPhone are marked **not checked here**.

## What you are installing

- A second app named **Enve Test**, next to the App Store Enve. It does not replace it.
- Bundle identifier `com.indyjamesb.enve.test` (**checked in the project**: `ios/Config/SideloadFree.xcconfig`).
- The iOS app target `enve`, from the Xcode project `ios/enve.xcodeproj`.
- Minimum iPhone system: iOS 17 (**checked in the project**).
- Xcode 26.4 or newer (**checked in** `ios/DEVELOPMENT.md`). The Mac has to be able to run that Xcode. The required macOS version was **not checked here**.

## Get the code

1. Install Xcode from the Mac App Store. Open it once and let it finish installing the extra components. **Not checked here.**
2. In Xcode, open Settings (the Xcode menu), then Accounts, and sign in with the Apple ID you want to use. You do not need the $99 developer program. **Not checked here.**
3. Download the fork and this branch. In Terminal:

```sh
cd ~
git clone --recurse-submodules https://github.com/indyjamesb/Enve-Book-Player.git
cd Enve-Book-Player
git checkout fix/plex-local-first
git submodule update --init --recursive
```

4. In Finder, open `Enve-Book-Player/ios/enve.xcodeproj` (double-click it). Wait until the top bar stops saying it is fetching Swift packages. The first open needs the network.

If Xcode says files under `ThirdParty/foliate-js` are missing, run the `git submodule` command above again from the `Enve-Book-Player` folder.

## Which scheme to run

At the top of Xcode, the scheme menu is next to the Run button.

- Choose **`enve-sideload`**. That scheme builds the `enve` iOS app with the **Sideload** configuration (**checked in the project**: `ios/enve.xcodeproj/xcshareddata/xcschemes/enve-sideload.xcscheme`).
- Choose your iPhone as the destination, not a simulator and not Apple TV.
- Do not use the scheme named `enve`. That one still uses bundle id `com.enve.enve`, team `9TT6DBK8W3`, and the paid-account entitlements. A free Apple ID cannot sign that.

## Signing with your free team

The Sideload configuration does **not** pick a team on purpose, so Xcode can use yours. Debug and Release still say team `9TT6DBK8W3`. Do not change those two.

1. Click the blue project icon, then the target **enve**.
2. Open **Build Settings**.
3. Search for `Development Team`.
4. Find the **Sideload** column (not Debug, not Release). Set it to your name, the one that says Personal Team.
5. Do the same for the targets **EnveWatch** and **EnveBookWidgets**. The iPhone build embeds both, so they need a team too (**checked in the project**: the `enve` target depends on them).
6. Search for `Code Signing Entitlements` on the **enve** target. The Sideload column should be `enve/Configuration/enve-sideload.entitlements`. That file is empty on purpose. Debug should still be `enve/Configuration/enve.entitlements`.

If the Signing & Capabilities screen shows iCloud, Push, App Groups, HealthKit, or CarPlay, you are probably looking at Debug. Do not click anything that edits `enve/Configuration/enve.entitlements`. That file is the upstream one.

Then press Run (the triangle). The first build is long. Keep the phone unlocked and plugged in.

## What a free account cannot turn on

These are in the real entitlements files. The sideload scheme does not use those files. You do not delete the capabilities from the upstream files.

| Capability | Where it lives in the project | Sideload file |
| --- | --- | --- |
| Push (`aps-environment`) | `ios/enve/Configuration/enve.entitlements` and `ios/enve/enveRelease.entitlements` | empty `ios/enve/Configuration/enve-sideload.entitlements` |
| iCloud / CloudKit (`iCloud.com.enve.enve`) | same two app files, and `ios/enve-tvOS/EnveTV.entitlements` | not used by `enve-sideload` |
| CarPlay audio | the two app entitlements files | removed for sideload |
| HealthKit | the two app entitlements files | removed for sideload |
| App Group `group.com.enve.enve` | the two app files, `ios/EnveWatch/EnveWatch.entitlements`, `ios/EnveBookWidgets/EnveBookWidgets.entitlements` | empty `EnveWatch-sideload.entitlements` and `EnveBookWidgets-sideload.entitlements` |

**Checked in the project.** Whether a free team accepts the empty files was **not checked here**.

These stay in `ios/enve/Configuration/Info.plist` and in the target's build settings. They are not the restricted entitlements above. They are **not checked** against a free team:

- Background modes: audio, fetch, processing, remote-notification. Audio is what keeps a book playing with the screen off. Remote-notification without the push entitlement may only mean push does nothing.
- A CarPlay scene in the Info.plist. CarPlay itself should not connect. It is **not checked** whether that scene causes a warning.
- Health usage sentences. Sleep insights will not work without the HealthKit entitlement.
- Local network and Bonjour usage sentences.
- Background task ids `com.enve.enve.storyalign` and `com.enve.enve.abs-session-close`.

On this install, expect these to be missing: iCloud library sync, push, Home Screen widgets sharing data with the app, the Watch app sharing data, CarPlay, and sleep rewind. Playback of a Plex book on the iPhone is the part this build is for.

The Watch app and the widget still get built, with their own bundle ids (**checked in the project**):

- App: `com.indyjamesb.enve.test`
- Watch: `com.indyjamesb.enve.test.watchkitapp`
- Widget: `com.indyjamesb.enve.test.widgets`

That is three ids. A free account only allows a few apps on the phone. People usually hit a limit of 3, and the profile dies after 7 days. **Those two numbers were not checked on a device here.** If Xcode prints a different limit, believe Xcode. Delete other apps you installed with the free account if it says you are full.

### If the Watch or widget signing fails

Only do this if Run stops on EnveWatch or EnveBookWidgets. Plex on the iPhone does not need them.

1. Select the **enve** target, then **Build Phases**.
2. Delete **Embed Watch Content**, **Embed App Extensions**, and the **EnveWatch** and **EnveBookWidgets** rows under Dependencies.

Those names are **checked in the project**. The menus were **not checked in Xcode**. This edit also changes the normal `enve` scheme. Do not commit it.

## On the iPhone

**Not checked here.** This is the usual iOS 16+ path, and the app requires iOS 17:

1. **Developer Mode.** Settings → Privacy & Security → Developer Mode. Turn it on, restart, and confirm. iOS only shows this row after Xcode has tried to install a development app at least once.
2. **Trust the developer.** If the app will not open, go to Settings → General → VPN & Device Management, tap your Apple ID, and choose Trust.
3. **Local Network.** The first time Enve Test talks to a Plex server on your Wi-Fi, iOS asks for local network access. Allow it. If you tapped Don't Allow, turn it back on under Settings → Privacy & Security → Local Network. The project has two sentences iOS might show: "Enve needs access to your local network to discover and connect to your media servers." and a second one about an Apple TV. Which one appears was **not checked here**.

## Seven-day expiry

A free Personal Team profile stops opening the app after about 7 days (**not checked on a device here**). Plug the phone back in, open this same project, choose `enve-sideload`, and press Run again. Keep the bundle id `com.indyjamesb.enve.test`. Changing it makes a different app.

## Passwords and the Plex login

The real app stores server tokens in an iCloud-style keychain that requires the App Group. A free team cannot use that group. The Sideload build, and only that build, falls back to a keychain that stays on this iPhone (`SIDELOAD_FREE_APPLE_ID` in `SideloadFree.xcconfig`, code in `SideloadKeychainFallback.swift`). **Not checked on a device.**

`PlexAuthStore.swift` is locked in this repo and was not read. If the Plex account token lives only in that store, you may have to sign in to Plex again after a relaunch. The server you add is also saved on the connection itself, which is the path this fallback covers.

## What to try for the Plex fix

1. Add a Plex server. Your own servers should be listed before shared ones, with a short LAN / Remote / Relay line. One row shows a spinner while it is tested. The error should not say "this Mac".
2. Play a book on Wi-Fi.
3. Turn Wi-Fi off so the phone goes to cellular, or join the other way around. Start the book again. The app should keep the last address that worked, and look for a better one after the network change, not while you are pressing play.

## Keep this out of an upstream pull request

The Plex behavior is one commit. This sideload scheme, the empty entitlements, `SideloadFree.xcconfig`, and the keychain fallback are a later commit. When you eventually ask to propose the fix upstream, that second commit stays on the fork.
