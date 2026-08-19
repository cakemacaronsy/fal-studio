# FAL Studio

A native macOS app for generating images and videos with [fal.ai](https://fal.ai)
models — Grok Imagine, Seedream, GPT Image 2, Seedance, MiniMax, Kling, Wan,
LTX — in one window. You bring your own fal.ai API key; the app ships with none.

Left side is the control panel, right side is your gallery wall. Pick a model,
type a prompt, press Generate. Drop an image in and the app automatically
switches to the right endpoint (image-to-video, edit, or multi-reference)
without you having to know which is which.

## Install (no build required)

1. Download the latest `FAL-Studio-*.dmg` from
   [Releases](https://github.com/cakemacaronsy/fal-studio/releases/latest).
2. Open the DMG and **drag FAL Studio into the Applications shortcut**.
   Install it in Applications — running it from the DMG or Downloads breaks
   in-app updates (macOS runs quarantined apps from a temporary read-only copy).
3. First launch, macOS blocks it once because this free app isn't notarized:
   - Double-click it, click **Done** on the warning.
   - Open **System Settings → Privacy & Security**, scroll down, click
     **Open Anyway**, confirm.
   - Or skip the dialogs entirely:
     `xattr -dr com.apple.quarantine "/Applications/FAL Studio.app"`
4. Press **⌘,** and paste your fal.ai key (fal.ai → Dashboard → Keys).

Requires macOS 14 (Sonoma) or newer. Universal binary — Apple Silicon and Intel.

**Try it with zero credits:** Settings → turn on **Mock mode**. Every
generation returns a local placeholder so you can explore the whole UI without
an account.

## Build from source

Prerequisites (macOS only):

- Xcode 26 or newer (`xcode-select --install` is not enough — the full Xcode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
git clone https://github.com/cakemacaronsy/fal-studio.git
cd fal-studio
./scripts/build.sh        # generates the Xcode project and builds Release
open "build/Build/Products/Release/FAL Studio.app"
```

Other scripts:

| Script | What it does |
|---|---|
| `scripts/build.sh` | XcodeGen + `xcodebuild` Release build, stamped with a timestamp build number |
| `scripts/package.sh` | Wraps the built app into `dist/FAL-Studio-<version>.dmg` |
| `scripts/release.sh <owner>/<repo>` | Builds, packages, and publishes a GitHub release (needs `gh auth login`) |

Nothing in the build depends on paths outside the repo, so it works from any
folder on any Mac. `build.sh` records its output path under
`~/Library/Application Support/FAL Studio/` purely so that a machine which
builds the app can offer one-click "install this build" updates.

## How your data is stored

Everything is local to your machine, per user:

```
~/Library/Application Support/FAL Studio/
├── fal_key            your API key, chmod 600 (never leaves your Mac except to fal.ai)
├── library.json       gallery index: prompts, models, settings, costs
├── custom_models.json endpoints you added yourself
├── media/             finished images and videos
├── thumbnails/
└── refs/              copies of reference images you used
```

Keys and galleries do **not** sync between machines — set up each Mac once.

## Adding models yourself

fal ships new models constantly. **Settings → Models → Add model**: paste any
fal endpoint path (e.g. `fal-ai/flux/dev`), choose image or video, say whether
it takes reference images, and it appears in the model dropdown running on your
own key. No app update needed.

## Costs

The estimate next to Generate (e.g. `~$0.30`) is what fal.ai will bill **your**
account for that generation. Video costs far more than images — a 20-second 4K
LTX clip is a few dollars, while a Grok image is a few cents. Check the number
before you press the button.

## Notes

- Not notarized: distributing without the Apple Developer Program means the
  one-time Privacy & Security approval above. Managed/enterprise Macs that
  forbid unnotarized apps can't run it.
- Prompt improvement (✨) and the model catalog follow each model's official
  fal.ai prompting guide, per model — not one generic template.
- A Windows edition is in progress in a separate branch of work.
