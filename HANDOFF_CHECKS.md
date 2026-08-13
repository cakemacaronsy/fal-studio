# FAL Studio — Remaining Manual Checks (handoff)

The app is built, packaged, and installed. Everything below is what still
needs human (or another agent's) eyes — no computer-use automation required
from this session.

## Already verified — no need to redo

- [x] Release build clean; payloads for all 15 models match the Python skill scripts (12/12 harness checks).
- [x] DMG created at `dist/FAL-Studio-1.0.dmg` (4.1 MB); mounts correctly; contains the app, an Applications shortcut, and "READ ME FIRST.txt".
- [x] `codesign --verify --deep --strict` passes on the app inside the DMG.
- [x] **No API key is bundled** — bundle scanned for key patterns; the app only reads the user's own key from their keychain (entered in Settings) or a `FAL_KEY` env var.
- [x] Installed to `/Applications` and launched: correct first-run state — Generate disabled with the hint "Add your FAL key in Settings (⌘,)", Settings window shows the FAL API Key field ("Stored in your macOS keychain. Get a key at fal.ai → Dashboard → Keys.") and the Mock mode toggle.

## 1. First-run experience on YOUR Mac (2 min)

- [ ] Open `/Applications/FAL Studio.app` (already installed).
- [ ] Settings (⌘,) → turn ON **Mock mode** → generate an image and a video with any prompt: placeholder card → finished card; hover shows Download/Delete; click card opens the preview with prompt + settings.
- [ ] Toggle System Settings → Appearance to check light mode readability.

## 2. Real generation with YOUR key (your cost, ~$0.05+)

- [ ] Get a key at fal.ai → Dashboard → Keys; paste in Settings → Save (expect a one-time keychain "Always Allow" prompt).
- [ ] Turn Mock mode OFF. Generate one cheap image (Grok, resolution 1k, quality low) — check the real image arrives and Download works.
- [ ] Optional: one cheap video (Seedance 2.0 Fast, 480p, duration 4, audio off, ~$0.43).
- [ ] If a generation fails, the card shows fal's error text — a 422 on a `-ref` model would mean a payload field name needs fixing in `Sources/Models/ModelCatalog.swift` (report it).

## 3. Distribution test on ANOTHER Mac (the check this machine can't do)

The app is ad-hoc signed (no Apple Developer ID), so on any other Mac,
Gatekeeper will warn on first open. Verify the documented workaround works:

- [ ] Send `dist/FAL-Studio-1.0.dmg` to a second Mac (AirDrop/download so it gets quarantined).
- [ ] Mount, drag the app to Applications, read "READ ME FIRST.txt".
- [ ] First launch: right-click → Open → Open. If macOS refuses even that:
      `xattr -d com.apple.quarantine "/Applications/FAL Studio.app"` then open normally.
- [ ] Recipient adds THEIR OWN fal.ai key in Settings and generates once.
- [ ] Note macOS version tested — if the right-click → Open path fails on newer macOS, the fix is proper notarization, which needs an Apple Developer account ($99/yr): Developer ID cert + `xcrun notarytool` (would slot into `scripts/package.sh`).

## Rebuild / repackage commands

```bash
cd ~/Desktop/"FAL Studio" && ./scripts/build.sh && ./scripts/package.sh
```

New DMG lands in `dist/`. Bump `MARKETING_VERSION` in `project.yml` for new versions.
