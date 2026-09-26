# Release, Linux and distribution plan

Prepared 27 Sep 2026. Nothing here is executed yet — every step needs explicit
authorisation. Nothing is committed or pushed.

## 1. Attribution (done)

| Surface | State |
|---|---|
| `NOTICE` | New. Names Harsh Gandhi (harshgandhi.com) and Buho Smart Tools (buho.co.in), GPL-3.0-or-later. |
| Source headers | 39 Swift files carry a copyright header. |
| `Package.swift` | Header comment above the manifest. |
| `Scripts/build.sh` | `NSHumanReadableCopyright` credits both and notes the bundled Hugo. |

Hugo is credited to the Hugo Authors under **Apache-2.0** — not MIT, as an
earlier draft of this document and the Info.plist both claimed. Fetched from the
v0.166.0 tag. App is GPL-3.0; the two licences are compatible, and the notice in
§5 has been fixed.

## 2. What was fixed this round

- **"Open an existing site" did nothing.** The button set `showOpenPanel = true`
  and the `.onChange` handler was an empty stub. It now opens an `NSOpenPanel`,
  checks the folder really is a Hugo site, and explains itself if not. Covered by
  tests for `hugo.toml`, `config.toml`, `config/_default`, a directory
  masquerading as a config file, and a file masquerading as a site folder.
- **Clipboard image paste** (`Core/ClipboardImage.swift`). Handles a copied file
  *and* a screenshot, which arrives as raw pixels with no name — so both name and
  format are derived here. Bound to ⌘V and to a toolbar button, since ⌘V alone is
  not discoverable. Pasting text still pastes text.
- **Inline image was laid out in a square slot.** `NSTextAttachment` reserves
  space from the cell's bounds, not from `cellSize()`, so a 900×500 picture got a
  square box and rendered 475×605 portrait. Fixed with `ScaledImageAttachment`
  overriding `attachmentBounds(for:proposedLineFragment:position:)`. Measured
  aspect 0.785 → **1.80**; the orange accent bar returned.
- **Screenshot pipeline was corrupting itself.** It composited AppKit subviews
  over an already-drawn layer (duplicated panels, mirrored text) and picked a
  different target page each run, littering the site. Both fixed.

## 3. Verification state

```
swift build                    Build complete — 0 warnings
./Scripts/test.sh              All checks passed — 108 checks
verify_all.sh                  All checks passed
check_portability.py           PASS — every Apple-only import guarded
check_inline_render.py         PASS  with image: 309,370 px, aspect 1.80
check_inline_render.py         FAIL  control: 0 px — the check has teeth
screenshots.sh                 idempotent over 3 runs; 1 image, not 6
Keychain round trip            isAvailable true, set/get/has/remove all ok
DMG contents                   hugo-LICENSE.txt, NOTICE, hugo binary — all present
```

The control matters: it is what makes the PASS meaningful. Before this round the
check passed every screenshot, including ones with no image at all.

## 4. Linux

**A Linux build is a port, not a packaging change.**

`./Scripts/check_portability.py` now measures this, and passes:

```
Core + Models: 4469 lines in 19 files
guarded: 19 files — every Apple-only import sits behind a canImport guard
```

**What was done:** every Apple-only import in `Core` and `Models` is now behind
a `canImport` guard.

| File | Was | Now |
|---|---|---|
| `CredentialVault` | `import Security` | guarded, with a fallback that *refuses* rather than storing secrets in a file |
| `ClipboardImage` | `import AppKit` | guarded; pasteboard-only on Apple |
| `Builder`, `SiteEngine`, `PreviewServer` | `import Combine` | guarded, via an `ObservationBase` alias |
| `MediaLibrary` | `import ImageIO` | guarded; pixel size becomes `nil`, which callers already handle |

**Known limitation, stated rather than hidden:** on a platform without Combine,
`@Published` stores the value but notifies nobody. Behaviour is correct, change
notification is absent. Fixing that properly needs a notification mechanism for
the target platform, which is that client's job to choose. It is documented in
`Core/PortableObservation.swift`.

**What is NOT verified:** that any of this compiles for Linux. There is no Linux
Swift toolchain on this machine, and `canImport(Security)` cannot be faked on
macOS. An earlier version of the check tried to simulate the preprocessor and
produced wrong answers; it now reports structure only and says so.

**The blocker is the UI.** 5,026 lines of SwiftUI/AppKit have no Linux
equivalent — not a reduced version, none.

1. **SwiftUI on Linux** — corelibs SwiftUI is not usable for a real app.
2. **Rewrite the UI on GTK4** — months, and effectively a different app sharing
   a core. Needs a maintainer, not a passing interest.
3. **Terminal client over the same Core** — viable now, because Core is 88%
   portable. Weeks, not months. No WYSIWYG preview, but writing, media and
   deploy are all reachable.

**Recommendation: (3), keep Core portable, do not attempt (2) now.**

The guarding is **done** (above). What remains for a real build:

- Split the package so `Core` is a library target, so a third-party deploy
  target can link a public module instead of the inside of an executable. This
  also makes the `PublishTarget` plugin seam real.
- Build on a Linux host. Not attempted: no Linux host, no container runtime, no
  Linux Swift toolchain here.

## 5. GitHub Releases — the plan

`gh` is not installed, so releases go via `git push` of a tag plus the API, or a
signed-in browser. Neither has been done.

Blockers, in order:

1. **Nothing is committed.** 8 modified/untracked paths including all of
   `Sources/`, `Scripts/`, `Presentation/`.
2. **No remote configured**, and no push authorised.
3. **Ad-hoc signed, not Developer ID.** Gatekeeper will warn on any other Mac.
   A public release needs a real Developer ID certificate plus notarisation, or
   users must right-click → Open every time.
4. ~~**Hugo's licence text is not bundled.**~~ **Fixed.** Hugo is Apache-2.0
   (verified against the v0.166.0 tag, not assumed), and the licence now ships
   as `Contents/Resources/hugo-LICENSE.txt`. The build fails if it is missing,
   so this cannot regress silently.
5. **No Linux artefact exists** to attach (§4), and none is possible until
   `Core` becomes a library target.

Ordered path, once authorised:

```
1. Commit the tree on a branch for review — no push yet.
2. ~~Bundle Hugo's LICENSE~~ — done; confirm in the mounted DMG.
3. Add Developer ID + notarise. Skippable for a private build, not a public one.
4. Tag v0.1.0, push the tag.
5. Publish the release with the DMG attached, plus a checksum and the licence
   files. Via the web UI until `gh` or a token is available.
```

The DMG builds at roughly 48 MB; its bundled-Hugo smoke test passes.

## 6. Open questions

- **Developer ID certificate** — do you have one, or should the first release be
  an explicitly unsigned preview?
- **Linux** — is the terminal client (§4.3) worth scoping, or park it?
- **Plugin SDK** — every Apple-only import in `Core` is now guarded, but `Core`
  is still inside the executable target, so a third-party deploy target still
  cannot link it. That module split is the remaining piece. Before the first
  public release?
