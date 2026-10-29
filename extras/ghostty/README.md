# Ghostty audio visualizer

Strudel-style live waveforms drawn behind each `dN $ ...` block in Neovim, plus
optional audio-reactive effects for the whole terminal, rendered by
[Ghostty](https://ghostty.org) custom shaders.

These extras are optional and macOS-focused. The plugin works without them.

## How it works

Ghostty shaders can't receive data from outside the terminal. The only live
input they can read is the 256-color palette (`iPalette[256]`). The
`ghostty-audio` encoder writes values into unused palette slots with `OSC 4`
escape sequences (three 8-bit values per slot), and the shaders decode them.

```
SuperDirt + ghostty-scope.scd --/ghostty/scope--+
tidal-events.nvim (positions) --/tidal/blocks---+--> ghostty-audio --OSC 4--> Ghostty shaders
system audio (BlackHole) ------------------------+          |
                                                  (via the Neovim relay, or its own tty)
```

| Piece | Path | Role |
|---|---|---|
| `bin/ghostty-audio` | `~/.config/ghostty/bin/` | Encoder: captures audio (8 bands, level, scope), receives OSC on UDP 57130, writes palette slots |
| `shaders/audio-tidal-waves.glsl` | `~/.config/ghostty/shaders/` | Per-pattern waveform behind each `dN` block (needs `--blocks`) |
| `shaders/audio-scope.glsl` | same | Whole-mix waveform across the screen (needs `--scope`) |
| `shaders/audio-pulse.glsl` | same | Zoom, glow and sparkles driven by the bands |
| `shaders/audio-rgb-shift.glsl` | same | RGB split driven by mids and highs |
| `supercollider/ghostty-scope.scd` | `~/.config/tidal/` | Taps each SuperDirt orbit and sends `/ghostty/scope <id> <floats>` per pattern |
| `bin/blackhole-volume.swift` | `~/.config/ghostty/bin/` | Resets BlackHole's volume to 1.0 (it can come back at ~20%) |
| `bin/make-multi-output.swift` | `~/.config/ghostty/bin/` | Creates a "Speakers + BlackHole" output device |

The band analysis uses system audio, so the effects also react to music played
outside Tidal. The per-pattern waveforms come from SuperCollider.

## Requirements

- Ghostty with custom shader support
- Neovim >= 0.12 for the terminal relay (`--nvim`)
- [uv](https://docs.astral.sh/uv/) (`ghostty-audio` is a self-contained uv
  script that installs `numpy` and `sounddevice` on first run)
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) for system audio
  capture (optional; `--demo` and `--blocks` work without it)
- [SwitchAudioSource](https://github.com/diogod/switchaudio-osx)
  (`brew install switchaudio-osx`) to switch the macOS system output between
  the multi-output device and the plain speakers from the shell, e.g. with the
  `blackhole` and `speakers` aliases (optional; Audio MIDI Setup works too)
- SuperCollider + SuperDirt for per-pattern waveforms

## Install

```sh
~/.local/share/nvim/lazy/tidal-events.nvim/extras/ghostty/install.sh --dry-run
~/.local/share/nvim/lazy/tidal-events.nvim/extras/ghostty/install.sh
```

The script copies the files above to `~/.config/ghostty` and `~/.config/tidal`
(override with `GHOSTTY_CONFIG_DIR` and `TIDAL_CONFIG_DIR`). Existing files are
left alone unless you pass `--force`. Pass `--link` to symlink them instead, so
plugin updates apply automatically. It does not edit any of your configs.

To run it on every install/update with lazy.nvim:

```lua
{
  "l00sed/tidal-events.nvim",
  build = "sh extras/ghostty/install.sh",
}
```

With packer.nvim, use `run = "sh extras/ghostty/install.sh"`.

## Setup

1. Route audio to BlackHole (skip for SuperDirt-only waveforms): create the
   multi-output device once, then select it as the system output.

   ```sh
   swift ~/.config/ghostty/bin/make-multi-output.swift <speakers-uid> <blackhole-uid>
   SwitchAudioSource -t output -s "Multi-Output Device"
   ```

   `SwitchAudioSource` comes from `brew install switchaudio-osx`. A device
   created through Audio MIDI Setup instead of `make-multi-output.swift` is
   named "Multi-Output Device"; list the real names with
   `SwitchAudioSource -a -t output` and match the name you switch with.
   Remember this step whenever the shaders seem dead: with the output on the
   plain speakers, BlackHole is silent and only the SuperDirt-driven waveforms
   (`audio-tidal-waves`) still work.

2. Ghostty config. Put `audio-tidal-waves.glsl` first: it reads the raw
   terminal to keep waveforms behind text, and later shaders distort both.

   ```
   custom-shader = shaders/audio-tidal-waves.glsl
   # custom-shader = shaders/audio-pulse.glsl
   # custom-shader = shaders/audio-rgb-shift.glsl
   # custom-shader = shaders/audio-scope.glsl
   custom-shader-animation = always
   ```

3. `BootSuperDirt.scd`, after `~dirt.start`:

   ```supercollider
   "~/.config/tidal/ghostty-scope.scd".standardizePath.load;
   ```

4. tidal-events.nvim: enable block positions and the relay.

   ```lua
   highlight = {
     positions = { ip = "127.0.0.1", port = 57130 },
     relay = { ip = "127.0.0.1", port = 57131 },
   },
   ```

5. Start the encoder, for example when Tidal launches:

   ```lua
   vim.api.nvim_create_autocmd("User", {
     pattern = "TidalLaunch",
     callback = function()
       vim.fn.jobstart({ vim.fn.expand("~/.config/ghostty/bin/ghostty-audio"), "--blocks", "--nvim" })
     end,
   })
   ```

   Start it before SuperDirt boots if you switch audio outputs: SuperDirt binds
   to whichever output is the default at boot. Only one encoder runs at a time.

Try `ghostty-audio --demo` to check the shaders without any audio.

## Notes

- After a macOS update, an aggregate device can survive with a broken
  sub-device: audio reaches BlackHole (shaders react) but nothing comes out of
  the speakers. Recreate it with `make-multi-output.swift` (`SwitchAudioSource
  -a -t output` gives device UIDs; delete the broken one in Audio MIDI Setup).
- Data uses palette slots that gruvbox-style 256-color themes leave unused.
  Text drawn in those colors will flicker. The slot table (`SLOTS` in
  `ghostty-audio`) must match the shaders.
- Slots are reset to the theme's colors (`OSC 104`) when the encoder exits.
- Other tools can feed the shaders by sending
  `/ghostty/scope <int id> <floats in -1..1>` to UDP 57130.
