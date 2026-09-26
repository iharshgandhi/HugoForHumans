# Hugo for Humans

**A Mac app that turns [Hugo](https://gohugo.io) into something you don't need a terminal for.**

Hugo is the fastest website engine on earth, and it is free. It is also, for most
people, unusable: you install it with a package manager, create folders by hand,
write a config file in TOML, and learn a command line.

Hugo for Humans is a native macOS app that wraps Hugo so that installing it means
double-clicking a disk image, and making a website means answering six questions.

The important part: **nothing is simulated**. The app bundles the real Hugo
binary and shells out to it. Your site is a real Hugo project in a real folder
that you own, and you can open it in Terminal at any time and keep going.

---

## Credits

Copyright (c) 2026 **Harsh Gandhi** ([harshgandhi.com](https://harshgandhi.com))
and **Buho Smart Tools** ([buho.co.in](https://buho.co.in)).

Licensed under GPL-3.0-or-later. See [`NOTICE`](NOTICE) for third-party
attribution. The app bundles the real Hugo binary — copyright the Hugo Authors,
Apache-2.0 — whose licence ships at `Contents/Resources/hugo-LICENSE.txt`.

---

## What it does

**One-click setup.** Answer a few questions — what kind of site, what it's
called, where it should live, which look you want — and the app creates the
project, installs a theme, writes `hugo.toml`, starts a Git repository, seeds
your first pages, and builds the site to prove it works. You never create a
folder or type a command.

**The WordPress model.** A sidebar of sections and pages, with **New Page** and
**New Section** buttons. Content lives in `content/` as Markdown, sections are
folders with an `_index.md`, exactly as Hugo defines them — the app just makes
those concepts visible and clickable.

**An editor that knows about front matter.** Title, summary, tags, slug and
publish state are form fields beside the text. Word count and reading time are
live. Changes autosave. A formatting toolbar acts on your real selection, and an
advanced mode lets you edit the raw front matter when you need to.

**Live preview that is the truth.** The preview pane loads pages from a real
`hugo server`, so what you see is exactly what Hugo will publish — not an
approximation rendered by the app.

**Every Hugo command reachable from the UI.** Builds expose `-D`, `-F`, `-E`,
`--minify`, `--cleanDestinationDir`, `--enableGitInfo`, `--gc`, `-M`, `-e` and
`-b` as checkboxes and fields, and show you the exact command line they
correspond to. Content counts come from `hugo list`. Nothing is hidden.

**Themes, verified.** Sixteen themes ship in the gallery, each one tested
against Hugo 0.166 extended by actually cloning it and building a site with it.
Themes install with one click and require no Go toolchain.

---

## Install

Download the `.dmg` from Releases, open it, and drag **Hugo for Humans** into
Applications.

The app is self-contained. It does **not** need Homebrew, Go, or Hugo installed
— a Hugo *extended* binary is bundled inside the app. If you already have an
extended Hugo on your `PATH`, the app will use that instead.

Requires macOS 14 or later. Apple Silicon and Intel.

---

## Build it yourself

```bash
git clone https://github.com/iharshgandhi/HugoForHumans.git
cd HugoForHumans
./Scripts/build.sh
```

That produces `dist/Hugo for Humans.app` and `dist/Hugo for Humans-0.1.0.dmg`.
The script downloads the matching Hugo release, extracts the binary from the
macOS package, assembles the bundle, generates the icon, and ad-hoc signs it.

Useful flags:

| Flag | Effect |
|---|---|
| `./Scripts/build.sh --no-dmg` | Build the `.app` only |
| `./Scripts/build.sh --debug` | Debug build |

### Tests

```bash
./Scripts/test.sh              # run everything
./Scripts/test.sh FrontMatter  # run one suite (substring match)
```

Note: this is `Scripts/test.sh`, not `swift test`. Running an XCTest bundle
requires a full Xcode install, and the Command Line Tools alone cannot run one —
`swift test` reports success while executing nothing. So the suite is compiled
directly, against the same sources as the app, into a binary that reports its
own results. It works anywhere the app builds.

The suite includes integration tests that create real sites with the real Hugo
binary, edit them through the app's own code, and assert Hugo still builds them
— which is the only meaningful definition of "working" for a wrapper. One test
walks the entire user journey: wizard → open site → add page → edit and save →
build, touching no terminal.

### Screenshots

```bash
./Scripts/screenshots.sh       # renders the real views to dist/screenshots
```

Renders the app's actual views offscreen to PNG. Useful for reviewing UI changes
without granting screen-recording or accessibility permissions.

---

## Why the app shells out to Hugo

Because a wrapper that reimplements Hugo is a worse Hugo. Every operation in this
app is a real `hugo` invocation:

| What you do in the app | What actually runs |
|---|---|
| Create a site | `hugo new site <path>` |
| New page | `hugo new content <section>/<name>.md` |
| New section | `hugo new content <section>/_index.md` |
| Build | `hugo` with the flags you selected |
| Live preview | `hugo server --port 1313 --buildDrafts` |
| Content counts | `hugo list all` / `drafts` / `future` / `published` |
| Theme install | `git clone --depth 1` into `themes/` |

A few consequences worth knowing:

- **Themes install with `git clone`, not `hugo mod get`.** Hugo Modules needs the
  Go toolchain, which almost nobody has. A shallow clone is the documented
  fallback and needs nothing but the `git` that ships with macOS.
- **The extended build is required.** Non-extended Hugo cannot compile SCSS, and
  most themes use it.
- **`hugo new content` must run with the project as the working directory.**
  Passing a path prefix fails with a confusing "no existing content directory"
  error; the app always sets the working directory correctly.

---

## Project layout

```
Sources/HugoForHumans/
  App/          SwiftUI app entry point, menu commands
  Core/         HugoBinary, ProcessRunner, SiteEngine, SiteCreator,
                PreviewServer, Builder
  Models/       FrontMatter, ContentItem, SiteConfig, ThemeCatalog
  Views/        WelcomeView (setup wizard), MainWorkspace, Sidebar,
                EditorPane, PreviewPane, Dashboard, Settings, Themes, Publish
  Design/       DesignSystem
Sources/Tests/  CoreTests, IntegrationTests, main (test harness)
Scripts/        build.sh, test.sh, screenshots.sh, make_icon.swift,
                render_screenshots.swift
```

One module, on purpose. Splitting the code into a library plus a thin app made
every internal type need `public`, which added access-control noise without
adding a boundary worth having. The test runner compiles the same files directly
rather than importing them.

---

## License

GPL-3.0 — see [LICENSE](LICENSE).

Hugo itself is copyright the Hugo Authors and distributed under BSD-3-Clause.
This project is not affiliated with or endorsed by the Hugo project.

---

## Writing

**Images, the way you would expect.** Insert a picture from a file picker, or
press <kbd>⌘V</kbd> after taking a screenshot — the app copies the image into the
page's own Hugo bundle, promotes the page to a leaf bundle if needed, and writes
an ordinary relative `![alt](image.png)` reference. The picture appears inline
while you type. **Your file stays a standard Hugo page**: open it in any editor
and it is plain Markdown.

A screenshot pasted from the OS has no filename, so the app generates one
(`pasted-2026-09-27-021512.png`) and sniffs the format from the image's own bytes
rather than trusting the clipboard's label. A `.png` that is really copied HTML
is refused with an explanation instead of written out as a broken file.

**Attachments.** Files that cannot be shown inline are imported as page
resources and listed in the fourth inspector section — deliberately not inline
in the text, so your post body stays what you wrote.

**Per-page JavaScript.** A script saved on a page is written as a page resource
and emitted only by the published Hugo page. **It never runs in the editor.**

**Embeds from a URL.** Paste a YouTube, Vimeo, Twitter/X, Instagram or Facebook
URL and it becomes a Hugo shortcode — you never write one by hand.

**Publishing.** Export to a folder, or deploy to GitHub Pages, FTP, FTPS or
SFTP. Every target implements one `PublishTarget` protocol, so a new destination
is a new file rather than a change to the app. Credentials are stored in the
macOS Keychain and never written to a config file, a log, or a command line.

## Building it

```bash
./Scripts/test.sh          # 108 checks
./Scripts/verify_all.sh    # build, tests, a real Hugo publish, screenshots, release
./Scripts/build.sh         # Hugo for Humans.app and a .dmg
```

Two checks worth knowing about:

- `Scripts/check_inline_render.py` measures whether an inline image was really
  drawn, at the right aspect ratio — and is run against a control that must
  **fail**, because a pixel check that passes everything verifies nothing.
- `Scripts/check_portability.py` reports which Apple-only imports sit behind a
  `canImport` guard. It is a structural signal, not a Linux build: no Linux
  toolchain is involved, so the compile itself is unverified.

See [`RELEASE_PLAN.md`](RELEASE_PLAN.md) for the current release state and what
a Linux port would and would not involve.

## Themes

The gallery lists themes that were each cloned and built against Hugo
\(v0.166.0 extended) during development. **Import…** takes a theme from your own
disk instead, for a theme you are building yourself, one you downloaded from
somewhere the gallery does not carry, or one you are working on offline.

Choose a folder, or a `.zip`/`.tar`/`.tar.gz` archive. The theme is copied into
`themes/<name>/` — the same place a catalogue theme lands, so nothing downstream
behaves differently. It is **copied, not moved**: a theme that is itself a git
working tree keeps its `.git` and stays usable.

The name comes from the folder or from `theme.toml`, made safe as a folder name
(`Romana Imperia` → `romana-imperia`). Importing the same theme twice gives
`romana-imperia` and `romana-imperia-2` rather than overwriting the first.

Three shapes of archive are handled, because repositories publish all of them: a
`themes/<name>/` root, a nested `themes/<name>.zip`, and a plain zip of the theme
folder. A zip made on macOS is handled too — its `__MACOSX/` resource-fork mirror
sorts first alphabetically and would otherwise be installed instead of the theme.

Choosing the wrong folder is the usual mistake, so a folder without `layouts/`
is refused with a message saying what a theme needs, rather than copied in and
producing a site that does not build.
