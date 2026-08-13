# FAL Studio — Verification Checklist

Hand-off checklist for verifying the FAL Studio macOS app end-to-end. The app is
fully implemented and builds cleanly; automated payload tests already pass.
What remains is interactive UI verification.

## Context

- **Project**: `~/Desktop/FAL Studio` — native SwiftUI macOS app (xcodegen + xcodebuild, ad-hoc signed, not sandboxed, macOS 14+).
- **What it does**: generates AI images/videos via fal.ai. Left pane = control panel (Image/Video tabs, model dropdown, drag-drop reference images, prompt, parameter chips, Generate button with cost estimate). Right pane = gallery wall (placeholder card while generating, click to preview with settings, hover for Download/Delete).
- **Key sources**: `Sources/Models/ModelCatalog.swift` (all model/parameter definitions), `Sources/Services/GenerationManager.swift` (job lifecycle), `Sources/Services/FALClient.swift` (sync + queue API), `Sources/Views/…`.
- **Mock mode**: Settings toggle or `FAL_STUDIO_MOCK=1` env — renders local placeholders, spends no credits. Use it for everything except the two "real" checks at the end.
- **Library data**: `~/Library/Application Support/FAL Studio/` (`library.json`, `media/`, `thumbnails/`, `refs/`). Delete this folder to reset state between tests if needed.
- **API key**: stored in Keychain via Settings (⌘,), or `FAL_KEY` env var override. Never print the key.

## Already verified — do not redo

- [x] Release build succeeds with zero Swift errors/warnings (`scripts/build.sh`).
- [x] Payload builder output matches the Python skill scripts' `--dry-run` payloads for all 15 models (12 checks incl. seedream `image_size` mapping, minimax int duration, kling string duration, ref payload key names, pricing math). Test harness: scratchpad `main.swift` from the session; re-create only if payload code changes.

## Build & launch

- [ ] `cd ~/Desktop/"FAL Studio" && ./scripts/build.sh` → BUILD SUCCEEDED.
- [ ] Launch in mock mode:
      `FAL_STUDIO_MOCK=1 "build/Build/Products/Release/FAL Studio.app/Contents/MacOS/FAL Studio" &`
- [ ] Window opens: left control panel / right gallery with empty state. No console errors.

## Mock-mode UI walkthrough (no credits)

- [ ] **Tabs**: switch Image ↔ Video — model dropdown repopulates (Image: Grok/Seedream ×4; Video: Seedance ×6, MiniMax ×3, Kling ×2), chips re-render per model, Video default model is Seedance 2.0.
- [ ] **Chips**: each chip opens a menu with the right options (e.g. Seedance duration auto/4–15; Kling aspect 16:9/9:16/1:1); Audio chip toggles on/off; cost label updates live (e.g. Kling 10 s + audio → ~$1.68).
- [ ] **Generate (image)**: type a prompt, press Generate → placeholder card appears immediately in the gallery ("Generating…" + elapsed seconds), completes to a gradient MOCK image in ~2–4 s.
- [ ] **Concurrent jobs**: press Generate 3× quickly → 3 placeholder cards, all complete, order preserved (oldest first).
- [ ] **Generate (video)**: Video tab, any model, Generate → placeholder shows queue status ("queued" → "in progress"), completes to a 2 s mp4 card with a ▶ badge and a video thumbnail.
- [ ] **num_images**: Grok with Images · 3 → three completed cards from one job (cost ×3 shown before generating).
- [ ] **Drag & drop**: pick an i2v video model (e.g. "Seedance 2.0 · Image to Video") → drop zone shows Start/End slots; drop an image file onto Start (dashed border highlights); ✕ removes it. Switch to "…Reference to Video" → multi-image strip, max enforced (9). Generate button stays disabled until required refs present (hint text explains).
- [ ] **Hover overlay**: hover a finished card → Download + Delete buttons appear top-right. Download lands the file in `~/Downloads` (named `<model>-<date>.<ext>`, uniqued). Delete asks for confirmation, removes card and files.
- [ ] **Detail sheet**: click a finished card → enlarged preview (VideoPlayer for videos), right column shows prompt (selectable), model + endpoint, every setting, est. cost, created date; Download button works.
- [ ] **Cancel**: start a video job, hover its placeholder → ✕ cancel → card flips to failed "Cancelled" with Retry/Delete.
- [ ] **Retry**: click Retry on a failed card → new placeholder appears, old failed card removed.
- [ ] **Persistence**: quit (⌘Q) and relaunch → gallery identical; any job that was mid-flight shows failed "Interrupted".
- [ ] **Light/dark**: toggle System Settings → Appearance — app follows automatically, text readable in both.
- [ ] **Settings (⌘,)**: SecureField saves key to Keychain ("Saved ✓" feedback); Mock mode toggle present. Expect ONE keychain "Always Allow" prompt after each rebuild (ad-hoc signing) — that's known, not a bug.

## Real API checks (spends ~$0.10 total — get user OK first)

- [ ] Ensure FAL key is set (Settings or `FAL_KEY` env), mock mode OFF.
- [ ] **Cheap image**: Grok Imagine v2, resolution 1k, quality low, 1 image (~$0.04) → real image appears; detail sheet settings correct.
- [ ] **Cheap video**: Seedance 2.0 Fast, 480p, duration 4, audio off (~$0.45) → queue statuses tick, mp4 plays in detail sheet, thumbnail present.
- [ ] **Error path**: temporarily save a wrong API key → generate → card fails showing the HTTP 401 body text. Restore the real key after.

## Known quirks / footguns

- UI automation from a filtered screen-capture context is unreliable here: other apps' invisible windows overlap FAL Studio and the user moves focus — prefer manual testing or AppleScript/AX with the app frontmost (`open -a "FAL Studio"` first).
- Pricing values for Seedance/Grok/Seedream/MiniMax non-default resolutions are estimates marked `TODO verify` in `Sources/Models/Pricing.swift` — verify against the fal.ai model pages when convenient; MiniMax $0.26/s and Kling $0.112+$0.056/s are confirmed.
- `minimax-ref` / `seedance-ref` payload field names came from fal docs; if a real run 422s, the failed card shows fal's error body — fix the key in `ModelCatalog.swift`.
