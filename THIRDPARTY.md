# Third-party notices

Salvager bundles third-party software and assets. Their licenses and required
attribution are reproduced below. This file is the authoritative notice and
**must ship with any distributed/exported build** (the exported binary embeds
the compiled Godot Engine, which counts as distributing it).

For asset-by-asset credits see [CREDITS.md](CREDITS.md). The game's own code is
source-available but proprietary; see [LICENSE](LICENSE).

---

## Godot Engine

This game is made with **Godot Engine 4.7**, available under the MIT license.

The exported binary also embeds several third-party components that Godot itself
bundles (FreeType, Mesa, etc.). The complete, version-accurate list of those
components and their licenses is available at runtime via
`Engine.get_license_info()` / `Engine.get_license_text()` — surface it in an
in-game credits/licenses screen for a fully compliant distribution.

```
This game uses Godot Engine, available under the following license:

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## hid-gd — HID GDExtension

The `Hid` class Salvager uses to read the Saitek switch panel and the X55 POV
directly from their USB HID interfaces, which Godot's `Input` singleton does not
expose. Shipped as a prebuilt Windows x86_64 library in
[addons/hid/bin/](addons/hid/bin/) and loaded at runtime via
`addons/hid/hid.gdextension`.

- **Source:** https://github.com/creatoy/hid-gd
- **Author:** creatoy
- **Version:** `v0.1.0` (tag commit `6cf8413`, 2023-12-18)
- **License:** MIT

The source is vendored at that tag under
[third_party/hid-gd/](third_party/hid-gd/), which also records the binary's hash,
its provenance, and the one local modification made to its manifest — see
[third_party/hid-gd/VENDORED.md](third_party/hid-gd/VENDORED.md). Written in Rust
against [godot-rust/gdext](https://github.com/godot-rust/gdext) (MIT) and the
[hidapi](https://crates.io/crates/hidapi) crate (MIT); those two are dependencies
compiled into the shipped library rather than separately bundled files, and their
own notices travel with their respective projects.

Upstream added its license file after the vendored tag was cut, so the notice
below carries a 2024 copyright line over code released in 2023. This is upstream's
own grant over its own work; the discrepancy is documented in `VENDORED.md`.

```
MIT License

Copyright (c) 2024 creatoy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Kenney — Space Kit

3D models under `assets/cc0/kenney-space-kit/`.

- **Source:** https://kenney.nl/assets/space-kit
- **Author:** Kenney (https://kenney.nl)
- **License:** Creative Commons Zero (CC0 1.0 Universal) — public domain
  dedication. No attribution is legally required and the assets may be used,
  modified, and sold freely. Kenney requests (but does not require) a credit
  and/or a link to https://kenney.nl, which this project provides here.

CC0 legal code: https://creativecommons.org/publicdomain/zero/1.0/legalcode

An abbreviated license summary also lives alongside the assets in
[assets/cc0/kenney-space-kit/LICENSE.txt](assets/cc0/kenney-space-kit/LICENSE.txt).
