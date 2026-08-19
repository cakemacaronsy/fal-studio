import Foundation

/// Builds the LLM instructions for the ✨ Improve Prompt button.
/// Guidance below is distilled from each model's OFFICIAL prompting guide:
/// - Seedance 2.0: fal.ai/learn/tools/seedance-2-0-prompting-guide
/// - Seedance 2.5: fal.ai/learn/devs/seedance-2-5-prompting-guide
/// - MiniMax H3:   fal.ai/learn/devs/minimax-h3-prompting-guide
/// - Kling 3.0:    blog.fal.ai/kling-3-0-prompting-guide
/// - Seedream 5:   fal.ai/learn/tools/how-to-use-seedream-5-0-pro-v2
/// - GPT Image 2:  fal.ai/learn/tools/prompting-gpt-image-2
/// None of them recommend raw JSON — the structured toggle emits each
/// model's own official template instead.
nonisolated enum PromptImprover {
    static let defaultLLM = "deepseek/deepseek-chat"

    /// Models from Chinese labs understand Chinese prompts natively; for them
    /// a Chinese input stays Chinese. International models get English.
    private static func isChineseCapable(_ spec: ModelSpec) -> Bool {
        spec.endpoint.contains("bytedance") || spec.endpoint.contains("kling")
            || spec.endpoint.contains("minimax") || spec.endpoint.contains("/wan/")
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    private enum Family {
        case seedance20, seedance25, minimax, kling, grok, grokVideo, wan, ltx, seedream, gptImage, custom
    }

    private static func family(of spec: ModelSpec) -> Family {
        let endpoint = spec.endpoint
        if endpoint.contains("seedance-2.5") { return .seedance25 }
        if endpoint.contains("seedance") { return .seedance20 }
        if endpoint.contains("minimax") { return .minimax }
        if endpoint.contains("kling") { return .kling }
        if endpoint.contains("grok-imagine-video") { return .grokVideo }
        if endpoint.contains("grok-imagine") { return .grok }
        if endpoint.contains("/wan/") { return .wan }
        if endpoint.contains("ltx") { return .ltx }
        if endpoint.contains("seedream") { return .seedream }
        if endpoint.contains("gpt-image") { return .gptImage }
        return .custom
    }

    static func systemPrompt(spec: ModelSpec, jsonMode: Bool, userPrompt: String) -> String {
        var rules: [String] = []

        rules.append("You rewrite prompts for the AI \(spec.kind == .video ? "video" : "image") generation model \"\(spec.displayName)\" (endpoint \(spec.endpoint)). Return ONLY the rewritten prompt — no preamble, no explanations, no markdown fences.")

        if isChineseCapable(spec) && containsCJK(userPrompt) {
            rules.append("The user wrote in Chinese and this model understands Chinese natively: write the improved prompt in Traditional Chinese, keeping any quoted dialogue exactly as given.")
        } else {
            rules.append("Write the improved prompt in English (translate the user's idea faithfully if it isn't English). Keep any quoted dialogue in its original language inside double quotes.")
        }

        rules.append(guidance(for: family(of: spec), kind: spec.kind))

        if jsonMode {
            rules.append(structuredTemplate(for: family(of: spec), kind: spec.kind))
        } else {
            rules.append("Output one flowing prompt. Preserve the user's core subject and intent exactly — enrich and direct, never replace. Respect the model's word-count sweet spot noted above.")
        }
        return rules.joined(separator: "\n\n")
    }

    // MARK: Per-model official guidance

    private static func guidance(for family: Family, kind: MediaKind) -> String {
        switch family {
        case .seedance20:
            return """
            Seedance 2.0 official guide — write a shot brief in plain natural language (50–150 words), like instructions to a director of photography:
            1. STRUCTURE: Subject + Motion first, then Camera, then Environment/Lighting, then Look, then Audio.
            2. ONE primary action and ONE camera move per shot. Stack extra shots explicitly with "cut to" (up to ~3 cuts).
            3. ACTING = physical consequences, not abstractions. Never "dances beautifully" — instead "drops into a low spin, the skirt flaring wide, then snaps upright". Body weight must read in every contact: gravel kicks up on landing, the mug slides and tips, jacket flaps with motion.
            4. DIALOGUE: short lines in double quotes (they lip-sync). Block each line — what the actor does before, during, and after speaking — and direct the read: "play her line dry and a little proud".
            5. CAMERA: use concrete terms the model reads cleanly — dolly, push-in, pan, tilt, crane, rack focus, handheld, locked-off. Never "epic cinematic camera".
            6. AUDIO: name diegetic sounds (heel strikes, steam hiss, rain on metal), specify room tone, and say "no music" when a score is unwanted — under-directed audio is the most common failure.
            7. BAN the slop words: beautiful, stunning, cinematic, epic, masterpiece — they give the model nothing to point a camera at.
            """
        case .seedance25:
            return """
            Seedance 2.5 official guide — everything from Seedance 2.0 (shot-brief structure, physical acting with body-weight consequences, quoted lip-synced dialogue with blocking, explicit diegetic audio, no slop adjectives) PLUS the long-shot rules:
            1. TIMELINE BLOCKS for anything beyond one beat: [0–5s] …, [5–12s] … — each block picks up from the previous block's end state; more seconds does NOT mean more events, so don't over-pack.
            2. CAUSE BEFORE REACTION: sequence contact → resulting movement → sound → reaction. Never write "looks surprised" without first writing what causes it.
            3. REFERENCE ROLES: if reference images exist, give each ONE narrow job: "@Image1 controls only the character's face and outfit. Do not copy its background."
            4. OCCLUSION CONTINUITY: when a subject passes behind something, restate their identity on re-emergence ("the same woman, same green coat, emerges from the other side").
            """
        case .minimax:
            return """
            MiniMax H3 official guide:
            1. Write a timed shot list: [0–2s] overhead shot …, [2–4s] push in ….
            2. Use precise cinematography vocabulary — rack focus, handheld shake, lens choice, exposure behavior, film stock, fine grain.
            3. Art-direct the audio explicitly (deep sub-bass, metallic resonance, restrained hit).
            4. State negative constraints plainly: "no soft dissolves", "no garbled text".
            5. Lock character identity with a specific feature list ("preserve platinum hair, narrow sunglasses, black trench coat").
            6. Describe transitions as physical events ("whip movement with motion blur"), never as effect names.
            7. Favor composition instructions over story narration; assign explicit jobs to any reference images.
            """
        case .kling:
            return """
            Kling 3.0 official guide — think in SHOTS, not clips:
            1. Label shots and give each its framing, subject, and motion (up to 6 shots). Use real cinematic terms: tracking shot, POV, shot-reverse-shot.
            2. Anchor characters at the START with unique consistent names and appearance; NEVER attribute dialogue with bare pronouns ("he says").
            3. Dialogue format: [Character A: exhausted partner, trembling voice]: "You never listen to me." — bind each line to a named character with a tone label, and tie lines to that character's physical action.
            4. Control sequence with linking words ("Immediately, …").
            5. Describe camera movement explicitly for every shot; generic motion language is the main failure mode.
            """
        case .grok:
            return """
            Grok Imagine v2 — photographic natural language. Cover five things concretely:
            1. Subject: focal point, expression, pose, emotion, clothing and prop details.
            2. Composition: subject scale and placement, camera angle (close-up, wide, low angle), balance, negative space.
            3. Scene: environment, light source and quality, atmosphere, particular details (smoke, water droplets).
            4. Style: art direction with visual targets, palette, material and texture quality.
            5. Lens: e.g. 50mm f/1.8, depth of field.
            Anti-slop: visual facts over vague praise — replace "stunning/beautiful/masterpiece" with observable specifics ("overcast daylight", "50mm feel", "realistic skin texture").
            """
        case .grokVideo:
            return """
            Grok Imagine Video 1.5 — natural-language shot direction (6–15 s clips, native audio):
            1. One clear subject action arc per clip with physical consequences (weight, contact, reaction), not adjectives.
            2. Explicit camera movement (push-in, tracking, handheld, static) and framing.
            3. Scene and light described concretely; motion in the environment.
            4. Audio is generated in the same pass: name the sounds and any short dialogue in double quotes; say "no music" if unwanted.
            5. No slop words (cinematic, stunning, epic) — observable specifics only.
            """
        case .wan:
            return """
            Wan 2.7 — cinematic natural language:
            1. Subject + action first with concrete physical detail, then scene, then camera movement, then lighting and look.
            2. One coherent motion arc per clip; describe cause and effect so movement stays believable.
            3. It supports a negative prompt — put unwanted artifacts there conceptually by keeping the main prompt positive and specific.
            4. Audio: it auto-scores background music unless directed; mention preferred ambience briefly or "no music".
            5. Avoid adjective piles; use observable visual facts and real camera vocabulary.
            """
        case .ltx:
            return """
            LTX-2.5 (Lightricks) — natural-language shot direction with native multishot and synchronized audio:
            1. One clear action arc per shot; for multiple shots, describe each cut explicitly — it holds scene and character consistency across cuts natively.
            2. Faces and on-screen text stay sharp — it's safe to include legible text and close-up facial performance beats.
            3. Concrete camera vocabulary (push-in, tracking, locked-off) and lighting direction.
            4. Audio generates in the same pass: name diegetic sounds and short quoted dialogue; "no music" if unwanted.
            5. Observable specifics over adjectives; no filler words like cinematic/stunning.
            """
        case .seedream:
            return """
            Seedream 5.0 Pro official guide — brief it like a photographer or a designer:
            1. PHOTO briefs: subject first, then where the camera stands, then the light, then the finish.
            2. DESIGN briefs: name the grid, the regions, what goes in each; wrap any copy in double quotes with a placement note (it renders text natively in 14 languages).
            3. LIGHT: say where it comes from, how hard it falls, and what color it is. Never write "well lit".
            4. COMPOSITION: set the subject off-center, catch a gesture mid-action, put something in the foreground — dead-center evenly-lit frames read as templates.
            5. EDITS: "Change only [element] to [spec]. Keep everything else exactly as it is." One region per instruction; colored markup boxes on the input image are honored per color.
            6. Don't overload one prompt with dense multi-region layouts — fewer, clearer regions win.
            """
        case .gptImage:
            return """
            GPT Image 2 official guide — structured brief with anti-slop rules:
            1. Organize the content as: Scene (where/when) → Subject (main focus) → Important details (materials, lighting, camera angle, composition, mood) → Use case (editorial photo, product mockup, poster…) → Constraints (what must not drift: no watermark, preserve face…).
            2. Visual facts over vague praise; style tags need visual targets ("cream background, heavy black sans serif, asymmetrical type block" instead of "minimalist brutalist").
            3. TEXT IN IMAGE: wrap literal copy in double quotes, mark it EXACT TEXT, give font/size/color/placement, and state "no extra words, no duplicate text".
            4. EDITS: separate change from preserve — "change only X; keep everything else the same" — and repeat the preserve list every iteration.
            """
        case .custom:
            return kind == .video
                ? "General video prompting: one clear subject action per beat with physical consequences, explicit camera movement, environment dynamics, lighting/mood, brief audio notes. Concrete verbs over adjectives; no filler words like cinematic/stunning."
                : "General image prompting: subject detail, composition and camera angle, scene and lighting (source, hardness, color), art style with visual targets, lens/depth of field. Visual facts over vague praise."
        }
    }

    // MARK: Structured mode (the { } toggle) — each model's OFFICIAL template

    private static func structuredTemplate(for family: Family, kind: MediaKind) -> String {
        switch family {
        case .seedance25:
            return """
            Format the output using Seedance 2.5's production-note sections, in this order, as labeled plain-text lines (no JSON, no markdown):
            FORMAT: duration feel, look, pacing.
            REFERENCE ROLES: one line per reference image, if any.
            TIMELINE: time blocks [0–Xs] with cause→reaction beats, each continuing the previous state.
            CAMERA: the move(s), one per beat.
            CONTINUITY: identity anchors to hold (faces, wardrobe, props).
            AUDIO: diegetic sounds, room tone, dialogue in double quotes, "no music" if unwanted.
            CONSTRAINTS: what must not happen.
            """
        case .seedance20:
            return """
            Format the output as an explicit multi-shot brief in plain text (no JSON): number each shot ("Shot 1 — …"), one action and one camera move per shot, join with "cut to", then a final AUDIO line naming diegetic sounds/room tone/dialogue in double quotes.
            """
        case .minimax:
            return """
            Format the output as a timed shot list in plain text (no JSON): lines of [0–2s] …, [2–4s] …, each with framing + action + camera; then an AUDIO line and a CONSTRAINTS line of explicit negatives.
            """
        case .kling:
            return """
            Format the output as labeled shots in plain text (no JSON): "Shot 1 (framing): …" per shot, characters introduced by name up front, dialogue as [Name: tone]: "line", sequence controlled with linking words.
            """
        case .gptImage:
            return """
            Format the output using GPT Image 2's official sections as labeled lines (no JSON):
            Scene: …
            Subject: …
            Important details: …
            Use case: …
            Constraints: …
            """
        case .seedream:
            return """
            Format the output as a design/photo brief with labeled lines (no JSON): Subject / Camera / Light / Finish for photos, or Grid / Regions (one line per region, copy in double quotes with placement) / Style for layouts.
            """
        case .grokVideo, .wan, .ltx:
            return "Format the output as labeled beats in plain text (no JSON): Subject / Action / Camera / Scene / Audio lines (one Shot line per cut for multishot)."
        case .grok, .custom:
            if kind == .video {
                return "Format the output as labeled beats in plain text (no JSON): Subject / Action / Camera / Scene / Audio lines."
            }
            return "Format the output as labeled lines (no JSON): Subject / Composition / Scene / Style / Lens."
        }
    }
}
