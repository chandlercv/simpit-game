# Vendored: `hid-gd`

This directory is a pinned copy of a third-party GDExtension. **It is not built by
anything in this project** — it is the provenance record and repair kit for the
binary that ships in [`addons/hid/bin/`](../../addons/hid/bin/), which was
downloaded prebuilt rather than compiled here.

Godot loads that binary at runtime via
[`addons/hid/hid.gdextension`](../../addons/hid/hid.gdextension). Running the game
needs Godot and nothing else; no Rust toolchain is required to build, run or
export Salvager. This source exists so the binary can be read, audited, and — with
the caveats below — rebuilt.

## Upstream

| | |
| --- | --- |
| Repository | <https://github.com/creatoy/hid-gd> |
| Author | creatoy |
| Licence | MIT — see [LICENSE.txt](LICENSE.txt) |
| Vendored tag | `v0.1.0` |
| Tag commit | `6cf8413c7290b4a42c211fb62e9ad9ee1fc15972`, 2023-12-18T06:04:37Z |
| Vendored on | 2026-08-30 |
| Upstream last pushed | 2024-05-27 — dormant for over two years at the time of vendoring |

Files taken from the `v0.1.0` tree: `Cargo.toml`, `README.md`, `src/lib.rs`,
`src/hid.rs`. Upstream's `.github/` and `.gitignore` are not vendored; they
describe upstream's own CI and working tree, not this code.

## The shipped binary

`addons/hid/bin/libhid_ext.windows.x86_64.release.dll`

| | |
| --- | --- |
| SHA256 | `2F3D58F114F56AE6628E6FB25AE1F12AE2B5CDFC90D2782FCBA93CB709184B3C` |
| Size | 3,200,512 bytes |
| Built | 2023-12-18 07:48 |
| Committed here | 2026-07-17, `c1059eb` |

**It is believed to be the `v0.1.0` release asset, not a local build.** The
evidence is inside the binary: its PDB path is
`D:\a\hid-gd\hid-gd\target\x86_64-pc-windows-msvc\release\deps\hid_ext.pdb` and
its Cargo paths are all under `C:\Users\runneradmin\`, both of which are GitHub
Actions Windows-runner paths. The build timestamp falls 1h44m after the `v0.1.0`
tag commit, which is what a release CI run looks like.

This has **not** been confirmed by hashing the published release asset. To
confirm it, download the Windows asset from
<https://github.com/creatoy/hid-gd/releases/tag/v0.1.0> and compare against the
SHA256 above. If it does not match, the binary is a later CI build and the tag
pinned here is approximate.

The binary is Windows x86_64 only, which is why `hid.gdextension` declares no
other platform. On any other platform the extension is absent, and the game
degrades as documented in `README.md`: the switch panel and X55 POV glance are
disabled, everything else runs.

## Licence note

Upstream is MIT, but **`LICENSE.txt` was added after the tag vendored here** — in
commit `81c8334`, 2024-05-27, "Add MIT license". There is no licence file in the
`v0.1.0` tree. The copy here is therefore taken from upstream's default branch,
and its copyright line reads 2024 while the code predates it.

The grant is the author's own and covers the work; the mismatch is recorded
because it is the sort of thing that looks like an error later if nobody wrote
down that it was checked. The reproduced notice satisfies the MIT requirement
that the copyright and permission notice accompany copies of the software — an
obligation that attaches to the binary this project ships, independently of
whether this source were vendored at all. The corresponding entry in
[`THIRDPARTY.md`](../../THIRDPARTY.md) is the authoritative notice for
distributed builds.

## Local modifications

One, in [`Cargo.toml`](Cargo.toml). Upstream `v0.1.0` reads:

```toml
godot = { git = "https://github.com/godot-rust/gdext", branch = "master" }
```

That is a floating branch with no committed `Cargo.lock` behind it, so upstream's
manifest cannot reproduce the shipped binary — `master` today is years of
breaking changes past the 2023 build. It has been pinned to:

```toml
godot = { git = "https://github.com/godot-rust/gdext", rev = "4ce4714b8871bf75e95d03401e44e3f1ccbdd7df" }
```

That revision (2023-12-17, gdext PR #538) was recovered from strings inside the
shipped DLL, which recorded its own build path as
`.cargo/git/checkouts/gdext-76630c89719e160c/4ce4714/`. It is one day before the
`v0.1.0` tag, consistent with the release build. **Until this vendoring, that
revision existed nowhere but inside a binary with no source.**

The other dependency versions the binary records are `hidapi` 2.4.1 (matching the
manifest), `rustc-demangle` 0.1.23 and `hashbrown` 0.14.0.

## What is deliberately not here

**No `Cargo.lock`.** Generating one requires resolving the dependency graph, and
there is no Rust toolchain on the machine this was vendored from. A hand-written
lock file would be a guess presented as a record, which is worse than none. If
you install Rust, run `cargo generate-lockfile` here and commit the result — that
is the remaining piece of reproducibility, and the pinned `rev` above is what
makes it worth having.

**No build script, and no rebuild has been attempted.** See below for why that is
a separate piece of work rather than an omission.

## Rebuilding

```
cargo build --release --target x86_64-pc-windows-msvc
```

The output is `target/x86_64-pc-windows-msvc/release/hid_ext.dll`, which is the
file that would replace `addons/hid/bin/libhid_ext.windows.x86_64.release.dll`.
Note the crate is named `hid` while the cdylib is named `hid_ext`; the committed
filename follows Godot's platform-suffix convention, not Cargo's output name.

**Expect this to fail, and treat it as a project rather than a command.** The
pinned gdext revision is from December 2023 and may not compile under a current
Rust toolchain; the manifest also carries a `[patch]` aiming `godot4-prebuilt` at
branch `4.1`, while this project runs Godot 4.7. The extension nevertheless works
against 4.7 today — `hid.gdextension` declares `compatibility_minimum = 4.1`, and
`tools/Phase5Smoke.gd` asserts the `Hid` class registers at runtime.

Moving to a modern gdext is therefore a real port, not a version bump, and it is
not required by anything at present. The working binary is the artifact of
record; this tree is what makes it recoverable if that changes.

## API surface

`Hid` extends `RefCounted` and registers fifteen methods. From
[`src/hid.rs`](src/hid.rs):

`list_devices` · `open` · `open_serial` · `open_path` · `write` · `read` ·
`read_timeout` · `send_feature_report` · `get_feature_report` ·
`set_blocking_mode` · `get_device_info` · `get_manufacturer_string` ·
`get_product_string` · `get_serial_number_string` · `get_indexed_string`

Of these, Salvager uses `list_devices`, `open`, `open_path` and `read_timeout`.

**There is no `close` method.** The device is an `Option<HidDevice>` field on a
`RefCounted`, so it is released when the object is freed. The bridges in
`systems/hardware/` each call it behind a `has_method("close")` guard, which is
correct and does nothing — worth knowing before anyone "fixes" the guard away.
