# Wheedgets

Fidget toys for your Mac, all in one menu bar icon. *Wheee* + widgets.

- **One widget at a time.** Pick a widget in the menu bar; one shortcut (⌃⌥W by default)
  turns it on and off. The menu shows only what concerns the selected widget.
- **Captured or pass-through keys.** In *capture* mode a widget's keys never reach the
  app in front, and Esc turns the widget off. In *pass-through* mode every key still
  types and the widget reacts as well: drum while you write, or keep the spinner spinning.
- **Drums.** Twelve 808/909-style sounds synthesized in code, so the app ships no sample
  files. Any pad can play your own WAV/AIFF/MP3/M4A/CAF instead. While the drums are on, a
  floating panel shows the pads flash as you hit them, and you can click them too.
  They can also be played on the trackpad, as a grid of zones (2×4 by default, up to 4×4).
  Zones can share a sound to make that drum a bigger target. Instead of the grid you can
  draw zones of any shape by tracing their outline on the trackpad. Hits come from touches or
  from physical clicks, and optionally get louder the harder you hit. Nothing is blocked:
  clicks and the pointer keep working.
- **Spinner.** A fidget spinner floating above every window, even full-screen ones. Clicks
  go straight through it. Keys flick it, push it while held, brake it or stop it, and
  optionally every key press nudges it. Ball-bearing physics make it whir for a long time
  and then settle. Its sound is synthesized in real time from its speed, and it blurs into
  a disc when fast. Drag it anywhere; only the spinner itself takes clicks, everything
  around it stays clickable. You can pick its color and size.
  It can be driven by the keyboard or by the trackpad, one at a time. On the trackpad,
  moving a finger around the center turns it 1:1 with the finger. A quick flick pushes
  it and adds to its spin; a finger that keeps moving holds it at the finger's speed. The
  trackpad is only observed, never blocked: the pointer, scrolling and gestures work as
  usual. Finger positions come from Apple's private MultitouchSupport framework, which is
  loaded at runtime and only while the spinner is on in trackpad mode.
- **Keyboard sounds.** Every key you type sounds like a mechanical keyboard. There are
  two synthesized packs built in (clicky and thocky), and you can import any
  [Mechvibes](https://github.com/hainguyents13/mechvibes) sound pack (a folder or .zip)
  with its press and release sounds. It only listens and never delays a key.
- **Plays over your music.** Nothing gets ducked, paused or switched (see [Audio](#audio)).
  There is a master volume, plus a volume for each module that goes up to 200 % behind a
  limiter.
- English and Russian UI.

Requires macOS 14 or later.

## Install

```sh
brew install --cask dayfob/tap/wheedgets
```

Update with `brew upgrade`, remove with `brew uninstall --cask wheedgets` (add `--zap` to
also delete settings and imported sounds). Releases are also on the
[Releases page](https://github.com/Dayfob/wheedgets/releases).

Wheedgets isn't notarized by Apple yet. The first time you open it, macOS may refuse:
open System Settings → Privacy & Security, scroll down and click **Open Anyway**. Then
turn a widget on and allow **Accessibility** when asked.

## Build and run

Building needs Xcode 26 or later (the app itself runs on macOS 14+).

```sh
./Tools/setup-signing.sh   # once: creates a stable local code-signing identity
./build.sh --install       # builds, copies to /Applications, launches
```

Other options: `./build.sh` (builds to `build/Wheedgets.app` only), `--run`, and
`--universal`. Run the tests with `swift test`, and check that every UI string is
translated with `./Tools/check-localizations.py`.

To also test against real Mechvibes packs (parsing, Ogg/MP3 decoding, slicing):

```sh
git clone --depth 1 https://github.com/hainguyents13/mechvibes /tmp/mechvibes
MECHVIBES_PACKS=/tmp/mechvibes/src/audio swift test
```

**Why the signing step matters.** macOS ties the Accessibility grant to the app's code
signature. An ad-hoc signature changes on every build, so the grant would stop working
after each rebuild. `setup-signing.sh` creates a self-signed identity in a dedicated
keychain (`~/Library/Keychains/wheedgets-signing.keychain-db`), and `build.sh` uses it
automatically. If a Developer ID certificate is installed, `build.sh` prefers it.

## Permissions

Wheedgets needs **Accessibility** access to handle keys. It asks the first time you turn
a widget on, and the widget starts automatically once you grant it.

- One shared keyboard tap exists only while a module needs it. With everything idle, the
  app watches no keystrokes at all. The tap only filters (sits in the input path) while a
  capture-mode widget is on. Pass-through widgets use a listen-only tap, which can't delay
  typing.
- Keyboard sounds look only at which physical key moved. Typed text is never assembled,
  stored or logged. The on/off shortcut goes through
  `RegisterEventHotKey`, which needs no permission.
- Password fields turn on Secure Input, which blocks all key taps. Modules stay silent
  there by design.
- A grant belongs to one code signature. If a build with a different signature shows as
  enabled but isn't trusted, Wheedgets clears its own stale entry with
  `tccutil reset Accessibility dev.wheedgets.Wheedgets` and asks again. Other apps'
  entries are never touched.

## Audio

macOS mixes all apps' audio, so staying out of the way means avoiding what would
interfere. The shared engine:

- never touches the input node. Opening it can switch Bluetooth headphones into
  low-quality headset mode for the whole system;
- never enables voice processing, which ducks other apps' audio;
- never changes the output device, its sample rate, or the system volume;
- stays running while the drums are on or the spinner turns, so the first sound isn't
  delayed while Bluetooth output wakes up. Otherwise the engine stops after 20 s of silence;
- follows output device changes and re-renders sounds at the new sample rate.

Graph: each widget gets a channel (sample voices or a real-time generator → mixer → limiter). All channels feed a master
bus and limiter, then the main mixer, which applies the master volume.

## Architecture

```
Sources/
  WheedgetsCore/            UI-free and unit-tested
    AppSettings.swift       settings slices per module, lenient decoding
    KeyRouting.swift        what a capture-mode widget does with a key
    SpinnerPhysics.swift    bearing friction, flicks, push, brake, stop
    SpinnerSound.swift      real-time whir synthesis
    TrackpadDrive.swift     finger motion around the pad center → spin speed; flick vs drag
    DrumTrackpad.swift      drum zones on the trackpad, touchdown hits and their strength
    DrumSettings.swift      pads and key-assignment rules
    DrumSynth.swift         deterministic drum synthesis
    KeySoundPack.swift      keyboard pack model and Mechvibes config.json parser (v1, v2)
    KeyClickSynth.swift     built-in synthesized key clicks
    MechvibesKeyCodes.swift macOS key codes → Mechvibes key codes
    DSP.swift               oscillators, noise, RBJ biquads
  Wheedgets/
    App/                    composition root: services → modules → UI
    Core/                   settings store, alerts, launch at login
    Audio/                  shared AudioEngine, per-module AudioChannel, sample import
    Input/                  KeyboardHub (one shared tap), Carbon hotkey, Accessibility,
                            MultitouchTrackpad (read-only finger positions)
    Widgets/                WidgetHost: the selected widget, on/off, key routing
    Modules/Drums/          DrumKit widget, floating pad panel, settings pane
    Modules/Spinner/        overlay window, Core Animation rendering, artwork, audio node
    Modules/KeyboardSounds/ widget, pack library (import/zip), background loader
    UI/                     menu bar, settings window, shared panel components
```

To add a widget, implement `Widget`, add a case to `WidgetKind`, pass it to `WidgetHost`
in `AppDelegate`, and give it a settings pane.

The app icon is drawn in code: `swift Tools/MakeIcon.swift` regenerates
`Resources/AppIcon.icns` (pass a path to also get a 1024 px PNG preview).

## Releases

Pushing a version tag (`git tag v0.2.0 && git push origin v0.2.0`) runs
`.github/workflows/release.yml`. It tests, builds a universal app, publishes
`Wheedgets-<version>.zip` as a GitHub release and updates the cask in
[Dayfob/homebrew-tap](https://github.com/Dayfob/homebrew-tap). Signing with a Developer ID
and notarization turn on by themselves once the secrets listed at the top of the workflow
are set.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): you may use, study, change and share Wheedgets
for any noncommercial purpose. Using it, or code from it, in a commercial product or
service is not permitted.
