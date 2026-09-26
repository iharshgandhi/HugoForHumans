# Build plan — media, embeds, deployment, releases and Linux

> All of §1–6 below are implemented and verified: `swift build` clean, 108/108
> checks passing, real Hugo builds publishing the image, script and embed.
> Current state, the Linux port assessment, and the release plan live in
> [`RELEASE_PLAN.md`](RELEASE_PLAN.md).

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done and verified

## 1. Credential vault
- [x] Probe: Keychain reachable from an unsigned CLT tool (SecItemAdd/CopyMatching → 0)
- [x] `CredentialVault` — store/read/delete secrets, never in UserDefaults
- [x] Store-only-what-is-needed: GitHub token, FTP/SFTP password
- [x] Surface "forget" in the UI; never echo a secret back into a text field

## 2. Embed engine
- [x] `EmbedParser` — pure function: URL → `EmbedKind` + canonical payload
- [x] YouTube (watch / youtu.be / shorts / embed)
- [x] Vimeo
- [x] Twitter/X (status URL → oEmbed)
- [x] Instagram (post / reel / TV)
- [x] Facebook (video / post)
- [x] Unknown URL → `.link` fallback, never a silent failure
- [x] Emit Hugo-native shortcodes where the theme supports them, raw HTML otherwise

## 3. Media library
- [x] Inline images → the page's own bundle folder; files stay standard `.md`
- [x] Attachments → not renderable inline, so listed in the inspector
- [x] Never rewrite the Markdown file into a different shape
- [x] Dedup filenames, keep original bytes

## 4. Editor
- [x] Render `![alt](path)` as an actual image inline in the writing surface
- [x] Attachment row as the 4th inspector item
- [x] Custom JavaScript block per page

## 5. Deployment
- [x] `PublishTarget` protocol + registry (the plugin seam)
- [x] GitHub Pages — auth via git, deploy by pushing `public/` to `gh-pages`
- [x] FTP / SFTP — curl for ftp/ftps, `sftp` batch mode for sftp (curl has no SFTP here)
- [x] Wizard Q&A: where will this live?

## 6. Verification
- [x] `./Scripts/test.sh` green
- [x] `swift build` clean
- [x] Real end-to-end: create → media → embed → build → deploy dry-run

## Notes from the environment
- `/usr/bin/curl` 8.7.1 has **no SFTP** (no libssh2). Use `/usr/bin/sftp`.
- `gh` is **not** installed — GitHub work must go through `git`.
- Keychain: do **not** set `kSecUseDataProtectionKeychain`; it needs entitlements.
