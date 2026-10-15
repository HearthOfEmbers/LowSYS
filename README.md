# LowSYS

An interactive distillation column simulator built to teach how distillation works, from vapour-liquid equilibrium on a single tray up to full column behaviour: McCabe-Thiele, tray and packed hydraulics, control loops, faults, a crude unit, and guided scenarios and drills.

LowSYS is free for students, teachers and anyone else to use, study, modify and share. See [License](#license).

## Install

Download the file for your device from the [Releases page](../../releases/latest). None of the builds are code-signed by Apple, Microsoft or Google, so each system shows a one-time warning the first time you open the app. The steps below get past it.

| Device | File |
|---|---|
| Windows 10/11 (64-bit) | `LowSYS-windows-x64.zip` |
| macOS (Apple silicon and Intel) | `LowSYS-macos.dmg` (or `LowSYS-macos.zip`) |
| Linux (64-bit, GTK 3) | `LowSYS-linux-x64.tar.gz` |
| Android | `LowSYS-android.apk` |
| iPhone / iPad | `LowSYS-ios-unsigned.ipa` (sideload, see below) |

### Windows

1. Right-click `LowSYS-windows-x64.zip` and choose **Extract All**. Keep the files together; the app does not run from inside the zip.
2. Open the extracted folder and run `lowsys_app.exe`.
3. If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**.

### macOS

1. Open `LowSYS-macos.dmg` and drag `lowsys_app` into **Applications**.
2. The first time, Control-click (or right-click) the app and choose **Open**, then **Open** again. If macOS only offers to move it to the Bin, try to open it once, then go to **System Settings > Privacy & Security** and click **Open Anyway**.
3. Alternatively, in Terminal: `xattr -dr com.apple.quarantine /Applications/lowsys_app.app`

Exported figures are saved to your Downloads folder.

### Linux

```sh
mkdir LowSYS && tar -xzf LowSYS-linux-x64.tar.gz -C LowSYS
./LowSYS/lowsys_app
```

It needs GTK 3, which most desktops already have (`sudo apt install libgtk-3-0` on Debian/Ubuntu if not). Saves go to `~/.local/share/LowSYS`.

### Android

1. Download `LowSYS-android.apk` on the phone and tap it.
2. When Android asks, allow your browser or file manager to **install unknown apps**, then go back and tap **Install**.
3. If Play Protect warns about an unrecognised app, tap **More details**, then **Install anyway**.

When updating, if Android refuses to install over an older copy, uninstall the old one first (builds from different machines are signed with different keys).

### iPhone and iPad

Apple only lets apps from the App Store or a paid developer account install by tapping, so the `.ipa` has to be sideloaded with a free Apple ID:

1. Install [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) on a Mac or PC.
2. Connect the iPhone, add `LowSYS-ios-unsigned.ipa` in the tool, and sign in with your Apple ID.
3. On the iPhone, go to **Settings > General > VPN & Device Management** and trust your Apple ID. On iOS 16 and later, also turn on **Settings > Privacy & Security > Developer Mode**.

With a free Apple ID the app must be re-signed every 7 days (AltStore can refresh it automatically). Building it yourself in Xcode (below) has the same limit.

## Build from source

All platforms need [Flutter](https://docs.flutter.dev/get-started/install) 3.47.7 (stable) and git.

```sh
git clone https://github.com/HearthOfEmbers/LowSYS.git
cd LowSYS/app
flutter pub get
```

| Platform | Extra tools | Build command | Output |
|---|---|---|---|
| Windows | Visual Studio 2022 with "Desktop development with C++" | `flutter build windows --release` | `app/build/windows/x64/runner/Release/` |
| macOS | Xcode | `flutter build macos --release` | `app/build/macos/Build/Products/Release/lowsys_app.app` |
| Linux | `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev` | `flutter build linux --release` | `app/build/linux/x64/release/bundle/` |
| Android | Android Studio (SDK) and JDK 17 | `flutter build apk --release` | `app/build/app/outputs/flutter-apk/app-release.apk` |
| iOS | Xcode and an iPhone | `open ios/Runner.xcworkspace`, set **Signing & Capabilities > Team** to your Apple ID, pick your iPhone, Run | installed on the device |

`flutter run` starts a debug build on whatever device is connected.

Tests:

```sh
cd packages/lowsys_engine && dart test   # engine and validation suite
cd app && flutter test                   # app tests (golden images are made on Windows)
```

### Making a release

Every pull request builds all five platforms in GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)); the files are on the run's summary page. Pushing a tag such as `v0.1.0` also publishes them as a GitHub Release.

## Extending LowSYS

[docs/EXTENDING.md](docs/EXTENDING.md) explains how to add themes, scenarios and drills, column presets, faults, levers, components and panels, with the files to change and the tests to run.

## Specification

| Document | Contents |
|---|---|
| [docs/SCOPE.md](docs/SCOPE.md) | Feature scope, screens and layouts, levers, fault catalog, scenarios and drills, themes, milestone plan with acceptance criteria |
| [docs/PHYSICS.md](docs/PHYSICS.md) | Full mathematical model: thermodynamic tiers, stage dynamics, tray and packing hydraulics, condenser/reboiler/thermosyphon, crude, controllers, faults, numerical scheme |
| [docs/ENGINE_API.md](docs/ENGINE_API.md) | Repository layout, pure-Dart engine API, snapshots, explain API, faults, control, scenarios, units, Flutter app architecture and theme tokens |
| [docs/VALIDATION.md](docs/VALIDATION.md) | Test cases with reference numbers and tolerances |

## License

LowSYS is licensed under the [GNU Affero General Public License v3.0 or later](LICENSE).

In short: anyone may use, study, change and share LowSYS for free, including in classes and courses. If someone distributes a modified version, or runs one as a website or online service, they must release their full source code under the same license. That keeps every version of LowSYS open, so nobody can turn it into a closed, paywalled product.

The physical property data and correlations come from the published literature cited in [docs/PHYSICS.md](docs/PHYSICS.md) §17. The bundled fonts are under the SIL Open Font License 1.1; their license texts are in [app/assets/fonts/LICENSES](app/assets/fonts/LICENSES).
