<p align="center">
  <img src="docs/assets/icon.png" width="128" alt="Wheedgets icon: a glossy bubble about to pop">
</p>

<h1 align="center">Wheedgets</h1>

<p align="center">
  Fidget toys for restless hands, right in your Mac's menu bar.<br>
  Drum on your keyboard, spin a fidget spinner, make every key click.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#whats-inside">What's inside</a> ·
  <a href="#privacy-and-permissions">Privacy</a> ·
  <a href="#if-something-doesnt-work">Help</a>
</p>

<p align="center">
  <a href="https://github.com/Dayfob/wheedgets/releases"><img src="https://img.shields.io/github/v/release/Dayfob/wheedgets?label=release" alt="Latest release"></a>
  <a href="https://github.com/Dayfob/wheedgets/actions/workflows/ci.yml"><img src="https://github.com/Dayfob/wheedgets/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue" alt="PolyForm Noncommercial license"></a>
</p>

If your hands always need something to do while you think, read or sit through a call,
Wheedgets gives them a toy without leaving the Mac: a few small fidget widgets behind one
menu bar icon. It's free, works offline and keeps nothing you type.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask dayfob/tap/wheedgets
```

Or download the zip from the [Releases page](https://github.com/Dayfob/wheedgets/releases),
unzip it and drag **Wheedgets** into Applications.

**First launch.** Wheedgets isn't notarized by Apple yet, so macOS may say it can't check
the app. Open **System Settings → Privacy & Security**, scroll down and click
**Open Anyway** next to Wheedgets. You only need to do this once.

**Update** with `brew upgrade`. **Uninstall** with `brew uninstall --cask wheedgets`; add
`--zap` to also remove its settings and imported sounds.

## Getting started

1. Click the bubble icon in the menu bar and pick a widget.
2. It turns on right away. The first time, macOS asks for **Accessibility** access so
   Wheedgets can hear your keys: allow it in System Settings and the widget starts by
   itself.
3. Press **⌃⌥W** (Control-Option-W) any time to turn the widget off and on again. You can
   change the shortcut in Settings.

Only one widget is on at a time, so it's always clear what your keys are doing. The
bubble in the menu bar fills in while a widget is on.

## What's inside

### Drums

A drum kit under your fingers: kick, snare, hi-hats, toms, cymbals, clap and more.

- **On the keyboard.** Each drum sits on a key (kick on F and Space, snare on J, hats
  under your right hand). Rebind any key, add or remove pads, or load your own sounds
  (WAV, AIFF, MP3, M4A, CAF).
- **On the trackpad.** Turn the trackpad into drum pads: a grid of zones (2×4 by default,
  up to 4×4), or zones of any shape you draw by tracing them with a finger. Give several
  zones the same drum to make it a bigger target. Play with taps or with real clicks.
- **Feel.** Harder taps play louder, if you like. A small floating panel shows the pads
  lighting up as you hit them, and you can click them too.

### Spinner

A fidget spinner that floats above everything on your screen, even full-screen apps.

- **Spin it with keys.** Space flicks it, the arrow keys spin it either way, hold ↓ to
  brake, Return stops it. Or let every key you type nudge it along while you write.
- **Or with the trackpad.** Circle a finger around the trackpad and it turns with you.
  A quick flick pushes it; a flick the other way throws it into reverse.
- **It feels real.** It whirs for a long time and slowly settles, with a sound that rises
  and falls with its speed, and blurs into a disc when it's really going.
- **Make it yours.** Twelve colors inspired by iPhone finishes, any size, and drag it
  wherever you want it. Clicks right next to it go through to whatever is underneath.

### Keyboard sounds

Make every key sound like a mechanical keyboard. Two sets are built in (clicky and
thocky), and you can load any [Mechvibes](https://github.com/hainguyents13/mechvibes)
sound pack for Cherry MX, Topre, typewriters and many more. Your typing is never slowed
down.

### Keys: captured or passed through

For drums and the spinner you choose what your keys do while the widget is on:

- **Only play** — the widget's keys don't type anything. Handy for a quick jam; **Esc**
  turns the widget off.
- **Play and type** — keys type as usual *and* play along, so you can drum or keep the
  spinner going while you write.

Shortcuts with ⌘, ⌃ or ⌥ always work normally.

### Sound

Wheedgets plays over your music and calls: it never pauses, lowers or switches your other
audio. Each widget has its own volume slider (up to 200%), and there's a master volume in
Settings.

## Privacy and permissions

- **No account, no tracking, no network.** Wheedgets doesn't connect to anything.
- **Accessibility** is the only permission it asks for. It's needed to hear which keys
  you press while a widget is on. With every widget off, Wheedgets doesn't watch the
  keyboard at all.
- **Nothing you type is kept.** Widgets only look at *which key* moved to pick a sound or
  a drum; text is never assembled, stored or sent anywhere. Password fields stay silent.
- **The trackpad** is read only while a trackpad widget is on, and nothing is blocked:
  the pointer, scrolling and gestures work as usual.

## If something doesn't work

- **macOS won't open the app.** See *First launch* above: System Settings → Privacy &
  Security → **Open Anyway**.
- **Keys stopped working after an update.** macOS may forget the Accessibility permission
  when an app updates. Turn the widget on again and Wheedgets asks for it. If it still
  doesn't respond, remove Wheedgets from System Settings → Privacy & Security →
  Accessibility with the **−** button and turn the widget on once more.
- **No sound while typing a password.** That's macOS protecting password fields. It's on
  purpose.
- **The spinner is in the way.** Drag it somewhere else, or use **Reset** in the spinner's
  settings to send it back to the bottom-right corner.
- **Trackpad options are missing.** They rely on a part of macOS that Apple doesn't
  document. If a future macOS changes it, the settings say so, and the keyboard options
  keep working.

Found a bug or have an idea? [Open an issue](https://github.com/Dayfob/wheedgets/issues).

## Requirements

- macOS 14 Sonoma or later, on Apple Silicon or Intel
- A trackpad for the trackpad options (MacBook or Magic Trackpad)

## Build it yourself

```sh
git clone https://github.com/Dayfob/wheedgets.git
cd wheedgets
./build.sh --install
```

You need Xcode 26 or later. The [contributing guide](CONTRIBUTING.md) covers the build,
tests, architecture and releases.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): you're free to use, study, change and share
Wheedgets for any noncommercial purpose. Using it, or code from it, in a commercial product
or service is not permitted.

<p align="center">
  <sub>Made by <a href="https://github.com/Dayfob">@Dayfob</a></sub>
</p>
