# Contributing to Wheedgets

Thanks for helping out. This guide covers building, testing, how the app is put
together, and how releases work.

## Build and run

You need Xcode 26 or later; the app itself runs on macOS 14+.

```sh
./Tools/setup-signing.sh   # once: creates a stable local code-signing identity
./build.sh --install       # builds, copies to /Applications, launches
```

Other options: `./build.sh` (builds to `build/Wheedgets.app` only), `--run`, and
`--universal` (arm64 + x86_64).

**Why the signing step matters.** macOS ties the Accessibility grant to the app's code
signature. An ad-hoc signature changes on every build, so the grant would stop working
after each rebuild. `setup-signing.sh` creates a self-signed identity in a dedicated
keychain (`~/Library/Keychains/wheedgets-signing.keychain-db`), and `build.sh` uses it
automatically. If a Developer ID certificate is installed, `build.sh` prefers it.

## Tests

```sh
swift test                      # unit tests
./Tools/check-localizations.py  # every UI string has a Russian translation
```

To also test against real Mechvibes packs (parsing, Ogg/MP3 decoding, slicing):

```sh
git clone --depth 1 https://github.com/hainguyents13/mechvibes /tmp/mechvibes
MECHVIBES_PACKS=/tmp/mechvibes/src/audio swift test
```

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary`,
for example `feat(drums): …`, `fix(spinner): …`, `perf: …`, `ci: …`, `docs: …`. Keep one
logical change per commit.

## Architecture

```
Sources/
  WheedgetsCore/            UI-free and unit-tested
    AppSettings.swift       settings slices per widget, lenient decoding
    KeyRouting.swift        what a capture-mode widget does with a key
    DrumSettings.swift      pads and key-assignment rules
    DrumSynth.swift         deterministic drum synthesis
    DrumTrackpad.swift      drum zones on the trackpad, touchdown hits and their strength
    DrumZones.swift         traced zones: outlines, hit testing, simplification
    SpinnerPhysics.swift    bearing friction, flicks, push, brake, stop, finger drive
    SpinnerSound.swift      real-time whir synthesis
    TrackpadDrive.swift     finger motion around the pad center → spin speed; flick vs drag
    KeySoundPack.swift      keyboard pack model and Mechvibes config.json parser (v1, v2)
    KeyClickSynth.swift     built-in synthesized key clicks
    MechvibesKeyCodes.swift macOS key codes → Mechvibes key codes
    DSP.swift               oscillators, noise, RBJ biquads
  Wheedgets/
    App/                    composition root: services → widgets → UI
    Core/                   settings store, alerts, launch at login, main-thread watchdog
    Audio/                  shared AudioEngine, sample-accurate Sampler, sample import
    Input/                  KeyboardHub (one shared tap), Carbon hotkey, Accessibility,
                            MultitouchTrackpad (read-only finger positions)
    Widgets/                WidgetHost: the selected widget, on/off, key routing
    Modules/Drums/          DrumKit widget, pad panel, trackpad zones, settings pane
    Modules/Spinner/        overlay window, Core Animation rendering, artwork, audio node
    Modules/KeyboardSounds/ widget, pack library (import/zip), background loader
    UI/                     menu bar, settings window, shared panel components
```

To add a widget, implement `Widget`, add a case to `WidgetKind`, pass it to `WidgetHost`
in `AppDelegate`, and give it a settings pane.

The app icon is drawn in code: `swift Tools/MakeIcon.swift` regenerates
`Resources/AppIcon.icns` (pass a path to also get a 1024 px PNG preview).

### Keyboard and permissions

- One shared keyboard tap exists only while a widget needs it. With everything off, the
  app watches no keystrokes at all. The tap filters (sits in the input path) only while a
  capture-mode widget is on; pass-through widgets use a listen-only tap, which can't
  delay typing.
- Widgets only see which physical key moved. Typed text is never assembled, stored or
  logged. The on/off shortcut goes through `RegisterEventHotKey`, which needs no
  permission.
- A grant belongs to one code signature. If a build with a different signature shows as
  enabled but isn't trusted, Wheedgets clears its own stale entry with
  `tccutil reset Accessibility dev.wheedgets.Wheedgets` and asks again.
- Trackpad positions come from Apple's private MultitouchSupport framework, loaded with
  `dlopen`/`dlsym` only while a trackpad widget is on. If it's missing, the trackpad
  options report themselves unavailable.

### Audio

macOS mixes all apps' audio, so staying out of the way means avoiding what would
interfere. The shared engine:

- never touches the input node (opening it can switch Bluetooth headphones into
  low-quality headset mode for the whole system);
- never enables voice processing, which ducks other apps' audio;
- never changes the output device, its sample rate, or the system volume;
- stops after 30 s of silence and restarts in a few milliseconds on the next sound;
  the spinner keeps it running while it turns;
- follows output device changes and re-renders sounds at the new sample rate.

Graph: each widget's `Sampler` (or the spinner's real-time generator) feeds a master bus,
then a master limiter and the main mixer, which applies the master volume. The sampler
applies each hit's gain and the widget volume from the first sample, and silent sources
mark their buffers silent so idle audio costs almost nothing.

## Releases

Pushing a version tag runs `.github/workflows/release.yml`:

```sh
git tag -a v0.2.0 -m "Wheedgets 0.2.0" && git push origin v0.2.0
```

It tests, builds a universal app stamped with the tag's version, publishes
`Wheedgets-<version>.zip` as a GitHub release and updates the cask in
[Dayfob/homebrew-tap](https://github.com/Dayfob/homebrew-tap). Developer ID signing and
notarization switch on by themselves once the secrets listed at the top of the workflow
are set. Version tags follow semver: `feat` bumps the minor version, `fix` and `perf` the
patch.
