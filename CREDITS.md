# Asset Credits

For engine and other software attribution (Godot Engine, MIT), see
[THIRDPARTY.md](THIRDPARTY.md) — that file is the authoritative notice that must
ship with distributed builds.

Third-party assets are organized **by license at the folder level** so a future
"what needs replacing before this could be sold" audit is a grep for one folder
path, not a per-asset license lookup (see Docs/Plans/simpit-plan.md, Phase 2):

| Folder | License | Constraint |
|---|---|---|
| `assets/cc0/` | CC0 | None — ship as-is (Kenney, Quaternius, Poly Haven, CC0 Sketchfab finds) |
| `assets/cc-by/` | CC-BY | Attribution required — keep this file current |
| `assets/cc-by-nc/` | CC-BY-NC | Non-commercial only — the folder to empty out first if ever monetizing |
| `assets/generated/sfx/` | Ours | None — synthesised from first principles by `tools/build_sfx.py`, no third-party input of any kind |
| `assets/generated/voice/` | **See below** | Rendered with the Windows SAPI voices — **the folder to re-render before monetizing**, the way `cc-by-nc/` is the folder to empty |

### The voice bank, and why it is flagged

`assets/generated/voice/` is speech rendered by `tools/build_speech.py` through
the Windows SAPI voices installed on the build machine. The Windows licence terms
grant you the **use** of those voices; they do not contain an explicit grant to
redistribute their **output** as an asset inside another product. It is not
prohibited either — it simply is not addressed, which is exactly the kind of thing
the folder-level taxonomy above exists to keep visible instead of buried.

Calling the OS to speak at runtime on a user's own machine would be unambiguously
fine. Baking the output into shipped files is the part nobody has said yes to.

**The mitigation is built in.** `tools/tts_sapi.ps1` is the only part of the
pipeline that knows what a speech engine is; everything downstream — the radio
treatment, the concatenation manifest, the runtime — works on plain WAV. So
re-rendering the whole bank from a permissively-licensed engine (Piper, eSpeak NG,
or a recorded human) is a flag and a rebuild, not a rewrite:

```
python tools/build_speech.py --engine wavdir --raw <dir of clips from any source>
```

eSpeak NG is arguably a better fit for the ship's own annunciator anyway — a
cockpit voice ought to sound synthetic.

Update the table below **as assets are added**, not reconstructed after the fact.

## Assets

| Asset | Source URL | License | Folder |
|---|---|---|---|
| Space Kit (39 selected `.glb` models of the 153-model kit: corridors, structures, pipes, platforms, machines, dishes, meteors/rocks, craft, props) | https://kenney.nl/assets/space-kit | CC0 (see [LICENSE.txt](assets/cc0/kenney-space-kit/LICENSE.txt)) | `assets/cc0/kenney-space-kit/` |

## Recommended sources

- [Kenney — Space Kit / Space Station Kit](https://kenney.nl/assets) (CC0, modular hull/station pieces)
- [Quaternius](https://quaternius.com/) (CC0, low-poly ships/debris)
- [Poly Haven](https://polyhaven.com/) (CC0 PBR textures and HDRIs)
- [Sketchfab — derelict/crashed spaceship niche](https://sketchfab.com/) (check per-model license; CC-BY-NC is acceptable while non-commercial)

All export as glTF, which Godot imports natively.
