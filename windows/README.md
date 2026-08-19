# FAL Studio for Windows

Windows edition of FAL Studio — Sean's desktop client for fal.ai image/video
generation. Built with Tauri 2 (Rust shell + React/TypeScript UI); a faithful
port of the macOS SwiftUI app in the repo root.

## Features (parity with the macOS app)

- Left control panel / right gallery-wall layout; light/dark follows the system
- Image/Video mode tabs; ONE dropdown entry per model family with automatic
  endpoint routing based on the provided reference images
  (0 refs → text-to-x, 1 → image-to-video with optional end frame,
  2+ → edit/reference variant)
- Full model catalog: Grok Imagine v2, Seedream 5 Pro, GPT Image 2,
  Seedance 2.5/2.0/Fast, MiniMax H3, Kling v3 Pro, Grok Imagine Video,
  Wan 2.7, LTX-2.5 Pro/Fast
- fal.ai API: sync `fal.run` for images, `queue.fal.run` + polling for video;
  the user supplies their own FAL key (never bundled)
- Parameter chips, cost estimates, ✨ prompt improver (per-model official
  guidance via fal's openrouter/router), red-markup annotation editor for
  reference images, gallery filters + past-generations section, one-click
  image→video, Traditional Chinese / English UI toggle, mock mode,
  done notifications, Seedance face-filter auto-fallback (Seedream re-render)
- Updater: checks GitHub Releases at `cakemacaronsy/fal-studio` for a newer
  Windows installer

## Development

```
npm install
npm run tauri dev     # native window (macOS or Windows)
npm run dev           # UI only in a browser (mock mode works)
```

## Building the Windows installer

CI does this automatically: pushing a `v*` tag runs
`.github/workflows/windows-release.yml` on a `windows-latest` runner, builds
the NSIS installer (`FAL Studio_<version>_x64-setup.exe`), and attaches it to
the GitHub release for that tag — alongside the macOS `.dmg`.

On a Windows machine you can build locally with:

```
npm install
npx tauri build --bundles nsis
# → src-tauri/target/release/bundle/nsis/*.exe
```

## Where data lives

`%APPDATA%/com.seanyu.falstudio/` — `library.json`, `media/`, `thumbnails/`,
`refs/`, and the `fal_key` file. UI preferences (language, mock mode, improve
LLM, update repo) live in the webview's localStorage.

## Release versioning

Keep `windows/package.json`, `windows/src-tauri/tauri.conf.json`, and
`windows/src-tauri/Cargo.toml` versions in sync with the release tag: the
in-app updater compares the running version against the latest release tag and
offers the download when the tag is newer and carries a Windows installer
asset.
