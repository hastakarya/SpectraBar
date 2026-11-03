# SpectraBar

![SpectraBar on the Touch Bar](docs/styles/needles.png)

Now playing on the MacBook Touch Bar: album art, a rainbow equalizer that follows the real sound,
slide to seek, and previous / play / next in one capsule. The system Control Strip stays on the right.

Works with YouTube Music (in Google Chrome), Spotify and Apple Music. A playing source wins over a
paused one, and the bar steps aside when nothing is playing.

## Requirements

- A MacBook Pro with a Touch Bar
- macOS 14.2 or later (Core Audio process taps)
- Xcode Command Line Tools (`xcode-select --install`); full Xcode is not needed

## Build and run

```bash
./build.sh
open build/TouchBarDisplay.app
```

The app has no Dock icon. Use ♪ in the menu bar or in the Control Strip to show the bar again or to quit.

## Equalizer options

From ♪ in the menu bar:

- **Equalizer**: *Real sound* follows what the Mac plays; *Simulated* bounces to a fake beat and needs
  no audio permission.
- **Style**: one of the five below.

Both choices apply at once and are remembered.

### Styles

**Rainbow needles**: thin needles in a drifting rainbow, with peak dots.

![Rainbow needles](docs/styles/needles.png)

**Glow waves**: overlapping sine waves that swell with the music, cyan to magenta.

![Glow waves](docs/styles/glowWaves.png)

**Bars and ribbons**: mirrored rainbow bars with thin white ribbons drifting across.

![Bars and ribbons](docs/styles/barsAndRibbons.png)

**Reflection**: bars on a floor line with a faint mirror and a slow white curve.

![Reflection](docs/styles/reflection.png)

**Center pulse**: a dot marks the playhead, blue behind and magenta ahead, with rings that pulse on the bass.

![Center pulse](docs/styles/centerPulse.png)

## Permissions

- **Automation**: macOS asks once per player so the app can read the current song.
- **System Audio Recording**: drives the equalizer. While music plays, macOS shows a recording
  indicator in the Control Strip. The audio is only measured, never saved or sent anywhere.
- **YouTube Music**: in Chrome, turn on View → Developer → Allow JavaScript from Apple Events.

The build is ad-hoc signed, so macOS may ask for permissions again after a rebuild.

## How it works

| File | Role |
| --- | --- |
| `main.swift` | Touch Bar layout, polling, buttons, menu bar item |
| `Players.swift` | AppleScript for Spotify, Music and YouTube Music: track info, controls, seek |
| `AudioSpectrum.swift` | Core Audio process tap and FFT into 96 log-spaced bands with auto-gain |
| `TrackView.swift` | Title, time, equalizer strip, slide-to-seek touches |
| `SpectrumStyle.swift` | The five equalizer drawing styles |
| `SimulatedSpectrum.swift` | Fake beat for the Simulated equalizer |
| `TouchBarPrivate.h` | Private DFRFoundation / AppKit calls for the Control Strip and system-wide bar |

**Note:** showing a bar over every app relies on private Touch Bar APIs. A macOS update may break it.
