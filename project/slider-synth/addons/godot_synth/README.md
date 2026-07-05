# godot_synth

A wavetable synthesizer, dynamic music system, and runtime SFX bank for Godot 4. Compose your soundtrack with chord progressions instead of audio files. Generate sound effects from math instead of digging through asset packs at 2 AM.

## What's in the box

- **Polyphonic wavetable synth.** Additive harmonics, sine, square, saw, triangle. Or just bring your own one-cycle waveform — the engine doesn't care.
- **Resonant SVF filter** with its own ADSR envelope. The squelchy kind you hear in trance music. Use sparingly.
- **FM operator** for bells, electric pianos, and clangs. Set `fm_index` to 3.0 if you want regrets.
- **Noise generator** with independent decay + LP/HP filters. Snare drums and ocean waves come from the same place, philosophically speaking.
- **Per-channel audio buses** routed through Godot's mixer, so you get reverb / delay / EQ / compression for free via Godot's built-in `AudioEffect` nodes.
- **Dynamic music director.** Define a chord progression once, then write patterns as scale degrees or chord tones. The melody automatically harmonizes with whatever chord is active. Swap progressions at runtime without restarting the song.
- **MIDI file parser** because you might want to import that demo from 1996.
- **Visual pattern editor** with a piano roll, marquee select, copy/paste, movable playhead, and live preview against any patch. Click around. Make noise.
- **Patch designer** with sliders for every parameter and ten or so factory presets to deconstruct.

## Installation

Drop the addon into your project at `addons/godot_synth/`. Or add as a git submodule:

```bash
git submodule add https://github.com/lost-conn/gd-synth.git addons/godot_synth
```

That's it. No editor plugin to enable — the classes register themselves via `class_name`. The `examples/music_test.tscn` scene is F6-able as soon as the addon is in your project.

## Quick start: making a noise

```gdscript
var synth := SynthEngine.new()
add_child(synth)

var patch := SynthPatch.make_organ()
synth.set_patch(0, patch)
synth.note_on(0, 60, 0.8)  # MIDI 60 (C4), velocity 0.8

# Later:
synth.note_off(0, 60)
```

You now have an organ. Congratulations.

## Quick start: making music

The recommended setup uses three autoloads — a synth, a director (beat clock + chord progression), and an SFX dispatcher. Wire them in `project.godot`:

```ini
[autoload]
Synth="*res://scenes/audio/synth.tscn"
Music="*res://scenes/audio/music.tscn"
```

Each of those scenes is a single Node with the right script attached.

Then drop a `MusicTrack` somewhere in your scene tree, hand it a `MusicPattern.tres`, and `activate()` it. The track auto-wires to `/root/Music` and `/root/Synth`, plays its pattern in time with the global beat, and resolves note pitches against the current chord.

## Architecture, briefly

Three layers, each owning one job:

| Layer | What it does | Doesn't do |
|---|---|---|
| `SynthEngine` | Pushes audio frames through a buffer pool. Manages voices, channels, buses. | Anything tempo- or music-related. |
| `MusicDirector` | Tracks beats, advances through chord blocks, exposes "what chord/scale is active right now" queries. | Make any sound itself. |
| `MusicTrack` | Reads a pattern, resolves notes against the director, drives a synth channel. | Care which director or synth it talks to (auto-wires). |

This means the synth is happily reusable for SFX even without music playing, the director is queryable from game code (e.g. "fire a particle on every beat"), and tracks can come and go without anyone noticing.

## Key resources

| Class | Saved as | Edit it in |
|---|---|---|
| `SynthPatch` | `.tres` | The patch editor. Or the inspector. Or notepad if you're feeling brave. |
| `MusicPattern` | `.tres` | The piano-roll pattern editor. |
| `PatternNote` | inline sub-resource | Footer of the pattern editor. |
| `MusicBlock` | inline or `.tres` | Inspector. Defines one chord + scale + duration. |
| `MusicData` | `.tres` | Inspector. A list of MusicBlocks plus BPM. |

## Editor tools

- `addons/godot_synth/editor/pattern_editor.tscn` — visual pattern editor. F6-able. Loads/saves `MusicPattern.tres`. Has a piano roll, copy/paste, marquee select, and a movable playhead. Configure a `preview_music_data` and `preview_patch` in the inspector to play patterns back live.
- `addons/godot_synth/examples/music_test.tscn` — the demo scene. Shows the patch editor and the pattern editor side-by-side, includes a typing-keyboard piano (A-K), and a sample song that toggles with F2.

## SFX without the music side

If you only want the synth (no chord progression, no patterns, just trigger-a-sound-on-an-event), you can skip the music director entirely. Use `SynthEngine` directly, or build your own thin dispatcher with a pool of `MusicTrack` nodes pre-configured for one-shot patterns. There's a worked example in the parent project this addon was extracted from.

## Channel allocation

The synth has 16 channels. Each holds one `SynthPatch` and gets its own `AudioServer` bus (named `Ch{N}`) routed to wherever you want via `output_bus`. Two tracks sharing a channel will share its patch and effect chain — fine for some uses, surprising for others. There's a 24-voice global pool; voice stealing is "oldest wins."

## Performance notes

GDScript per-sample audio rendering is CPU-bound but runs comfortably for ~16 active voices at 22050 Hz on a modern desktop. Bump `mix_rate` to 44100 if your saws sound aliased. Drop `max_voices` if your Steam Deck is angry. Enabling FM, the resonant filter, or many noise voices increases per-voice cost — most patches use only a subset.

## License

MIT. Do whatever you want, attribution appreciated, no warranty if the FM index of 8.0 makes your speakers leave.

## Credits

Built incrementally for [3dimenshift](https://github.com/lost-conn) and extracted as a standalone addon. Patches contributed willingly. Bug reports contributed reluctantly.
