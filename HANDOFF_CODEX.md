# FAL Studio — Codex Handoff (with computer use)

Scope: verify the FAL Studio macOS app end-to-end. Codex has computer use, so
this covers BOTH headless checks and the interactive GUI walkthrough.
Hard limits: treat the project folder as read-only, never read/print the
user's FAL key, and do NOT run the real fal.ai generations without the user's
explicit approval in chat (~$0.49 total). Write harnesses/reports to a scratch
directory OUTSIDE the project (e.g. `$TMPDIR/falstudio-verify/`).

## Context

- Project: `/Users/seanyu/Desktop/FAL Studio` (read-only for you).
- Built app: `build/Build/Products/Release/FAL Studio.app` — already built and working on this host. Do NOT rebuild unless a rebuild is explicitly needed; if the sandboxed Xcode macro service fails on `@Observable`, that's the sandbox, not the source.
- Mock mode = local placeholders, zero credits: enable via the Settings (⌘,) toggle, or launch with the env var:
  `FAL_STUDIO_MOCK=1 "/Users/seanyu/Desktop/FAL Studio/build/Build/Products/Release/FAL Studio.app/Contents/MacOS/FAL Studio" &`
- Library data lives at `~/Library/Application Support/FAL Studio/` (`library.json`, `media/`, `thumbnails/`, `refs/`). You may delete items **through the app UI**; don't hand-edit the folder.
- Compiles with plain `swiftc` (no macros): `Sources/Models/*`, `Sources/Services/{FALClient,MockFALClient,ImageEncoding,ThumbnailMaker,KeychainStore}.swift`. The SwiftUI/`@Observable` files (`Sources/App/*`, `Sources/Views/*`, `LibraryStore.swift`, `GenerationManager.swift`) must NOT be compiled standalone — verify those interactively or by reading.

## GUI driving tips (learned the hard way)

- Bring the app frontmost before every interaction burst: `open -a "FAL Studio"`. The user moves focus; other apps' windows overlap invisibly.
- Take a FRESH screenshot immediately before each click — the window position drifts between calls. Never reuse coordinates from an old screenshot.
- The Generate button sits bottom-left pane; chips are small — zoom to confirm labels before clicking.
- For drag & drop, have a test image ready (e.g. copy any PNG to `~/Desktop/falstudio-test-ref.png`) and drag from a Finder window, or use the drop zone's click-to-browse fallback (it opens a file picker).

## 1. Headless checks (no GUI needed)

- [ ] `codesign --verify --deep --strict` on the app bundle → exit 0; `plutil -lint` the Info.plist; `file` the executable (universal Mach-O).
- [ ] Payload harness (`swiftc` with `JSONValue/ModelCatalog/Pricing/PayloadBuilder.swift` + a scratch `main.swift`): grok defaults (16:9/2k/medium/png), grok-edit `image_urls` + no aspect, seedream 9:16 → `portrait_16_9` and "2:1" → `{2048,1024}`, seedance string `duration:"auto"`, seedance-i2v `image_url`+`end_image_url`, minimax duration → Int, minimax-ref `reference_image_urls` + adaptive aspect, kling duration stays string, kling-i2v `start_image_url`. Pricing: kling 10s+audio=1.68, minimax 15s=3.90, grok 1k×3=0.105, seedance-fast 480p×4s=0.432.
- [ ] Catalog invariants: 4 image + 11 video models; every ref-taking spec has `refPayloadKey`; every `.startEnd` spec has `endImagePayloadKey`; all choice defaults are in their own option lists.
- [ ] Mock media harness (`MockFALClient/FALClient/JSONValue.swift`): `makeImage` → valid PNG magic bytes; `makeVideo` → MP4 (`ftyp` at offset 4, >10 KB); `ThumbnailMaker.imageThumbnail` → JPEG ≤ 480 px.
- [ ] `GalleryItem` encode/decode round-trip with ISO-8601 dates and mixed `JSONValue` params.

## 2. Mock-mode GUI walkthrough (zero credits)

Launch with `FAL_STUDIO_MOCK=1` (env) so no key is needed.

- [ ] Window opens: left control panel, right gallery empty state.
- [ ] **Tabs**: Image ↔ Video — dropdown repopulates (Image ×4; Video: Seedance ×6, MiniMax ×3, Kling ×2; Video default = Seedance 2.0); chips re-render.
- [ ] **Chips**: open each menu on 2–3 models, options match (Seedance duration auto/4–15; Kling aspect 16:9/9:16/1:1); Audio chip toggles; cost label updates live (Kling 10 s + audio → ~$1.68).
- [ ] **Generate (image)**: type prompt → Generate → placeholder card ("Generating…" + seconds) → gradient MOCK image in ~2–4 s.
- [ ] **Concurrent**: click Generate 3× fast → 3 placeholders, all complete, oldest-first order.
- [ ] **Generate (video)**: Video tab → placeholder shows "queued" → "in progress" → mp4 card with ▶ badge and thumbnail.
- [ ] **num_images**: Grok, Images · 3 → cost ×3 shown, three completed cards from one job.
- [ ] **Refs**: pick "Seedance 2.0 · Image to Video" → Start/End slots appear; add an image via drag or click-to-browse; ✕ removes; Generate disabled with hint until start frame present. Switch to "…Reference to Video" → multi strip, cap 9.
- [ ] **Hover overlay**: hover finished card → Download + Delete top-right. Download → file lands in `~/Downloads` (`<model>-<date>.<ext>`, uniqued). Delete → confirmation → card and files gone.
- [ ] **Detail sheet**: click a finished card → enlarged preview (VideoPlayer for video, plays), prompt selectable, model + endpoint, all settings rows, est. cost, created date; Download works; close and reopen.
- [ ] **Cancel**: start a video job, hover placeholder → ✕ → failed "Cancelled" card with Retry/Delete.
- [ ] **Retry**: on the failed card → new placeholder appears, old card removed, completes.
- [ ] **Persistence**: ⌘Q, relaunch (same env var) → gallery identical; any mid-flight job shows "Interrupted".
- [ ] **Light/dark**: toggle System Settings → Appearance → app follows instantly, text readable both ways (screenshot both).
- [ ] **Settings (⌘,)**: SecureField + Save shows "Saved ✓"; Mock mode toggle present. (Don't type a real key; a dummy value is fine — delete it after by saving an empty field.) One-time Keychain "Always Allow" prompt after a rebuild is expected, not a bug.

## 3. Real API checks — STOP, needs user approval (~$0.49)

Only after the user explicitly approves the spend in chat:

- [ ] User adds their real FAL key (Settings) or sets `FAL_KEY`; mock mode OFF.
- [ ] Grok Imagine v2, 1k / low / 1 image (~$0.04) → real image appears, settings correct in detail sheet.
- [ ] Seedance 2.0 Fast, 480p / duration 4 / audio off (~$0.43) → queue statuses tick, mp4 plays, thumbnail present.
- [ ] Error path: save an obviously wrong key → generate → failed card shows the HTTP 401 body. Have the user restore their real key.

## Known notes

- Pricing values for non-default Seedance/Grok/Seedream/MiniMax tiers are estimates marked `TODO verify` in `Sources/Models/Pricing.swift`; MiniMax $0.26/s and Kling $0.112+$0.056/s are confirmed.
- `minimax-ref`/`seedance-ref` payload field names come from fal docs; a real-run 422 would show fal's error body on the failed card — the fix would go in `ModelCatalog.swift` (report, don't edit).

## Report format

One markdown report in scratch: pass/fail table per section, screenshots for
the GUI steps (at least: both tabs, a placeholder card, a finished wall,
detail sheet, light+dark), exact commands used, findings with `file:line`.
No project files modified.
