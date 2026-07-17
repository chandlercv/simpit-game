# Asset Credits

Third-party assets are organized **by license at the folder level** so a future
"what needs replacing before this could be sold" audit is a grep for one folder
path, not a per-asset license lookup (see Docs/Plans/simpit-plan.md, Phase 2):

| Folder | License | Constraint |
|---|---|---|
| `assets/cc0/` | CC0 | None — ship as-is (Kenney, Quaternius, Poly Haven, CC0 Sketchfab finds) |
| `assets/cc-by/` | CC-BY | Attribution required — keep this file current |
| `assets/cc-by-nc/` | CC-BY-NC | Non-commercial only — the folder to empty out first if ever monetizing |

Update the table below **as assets are added**, not reconstructed after the fact.

## Assets

| Asset | Source URL | License | Folder |
|---|---|---|---|
| Space Kit (39 selected `.glb` models of the 153-model kit: corridors, structures, pipes, platforms, machines, dishes, meteors/rocks, craft, props) | https://kenney.nl/assets/space-kit | CC0 | `assets/cc0/kenney-space-kit/` |

## Recommended sources

- [Kenney — Space Kit / Space Station Kit](https://kenney.nl/assets) (CC0, modular hull/station pieces)
- [Quaternius](https://quaternius.com/) (CC0, low-poly ships/debris)
- [Poly Haven](https://polyhaven.com/) (CC0 PBR textures and HDRIs)
- [Sketchfab — derelict/crashed spaceship niche](https://sketchfab.com/) (check per-model license; CC-BY-NC is acceptable while non-commercial)

All export as glTF, which Godot imports natively.
