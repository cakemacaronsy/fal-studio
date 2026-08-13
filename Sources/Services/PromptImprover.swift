import Foundation

/// Builds the LLM instructions for the ✨ Improve Prompt button. Guidance is
/// distilled from each model's official prompting docs (fal.ai model guides).
nonisolated enum PromptImprover {
    static let defaultLLM = "deepseek/deepseek-chat"

    /// Models from Chinese labs understand Chinese prompts natively; for them
    /// a Chinese input stays Chinese. International models get English.
    private static func isChineseCapable(_ spec: ModelSpec) -> Bool {
        let family = spec.id.split(separator: "-").first.map(String.init) ?? spec.id
        return ["seedance", "seedream", "kling", "minimax"].contains(family)
            || spec.endpoint.contains("bytedance") || spec.endpoint.contains("kling")
            || spec.endpoint.contains("minimax")
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    static func systemPrompt(spec: ModelSpec, jsonMode: Bool, userPrompt: String) -> String {
        var rules: [String] = []

        rules.append("You rewrite prompts for the AI \(spec.kind == .video ? "video" : "image") generation model \"\(spec.displayName)\" (endpoint \(spec.endpoint)). Return ONLY the rewritten prompt — no preamble, no explanations, no markdown fences.")

        // Language rule
        if isChineseCapable(spec) && containsCJK(userPrompt) {
            rules.append("The user wrote in Chinese and this model understands Chinese natively: write the improved prompt in Traditional Chinese, keeping any quoted dialogue exactly as given.")
        } else {
            rules.append("Write the improved prompt in English (translate the user's idea faithfully if it isn't English). Keep any quoted dialogue in its original language inside double quotes.")
        }

        // Per-model guidance (distilled from the official fal.ai prompting guides)
        rules.append(guidance(for: spec))

        if jsonMode {
            rules.append(jsonGuidance(kind: spec.kind))
        } else {
            rules.append("Output one flowing prompt of 60–140 words. Preserve the user's core subject and intent exactly — enrich, never replace.")
        }
        return rules.joined(separator: "\n\n")
    }

    private static func guidance(for spec: ModelSpec) -> String {
        let family = spec.id.hasPrefix("custom-") ? "custom" : (spec.id.split(separator: "-").first.map(String.init) ?? spec.id)
        switch family {
        case "grok", "seedream":
            return """
            Cover these five elements concretely:
            1. Subject — the visual focal point; expression, pose, emotion, clothing and prop details.
            2. Composition — subject scale and placement, camera angle (close-up, wide, low angle), balance and negative space.
            3. Scene — background environment, lighting (natural, neon, fog), atmosphere, special details (smoke, water droplets).
            4. Style — overall art style (photorealistic, illustration, minimalist), color palette, material and texture quality.
            5. Lens — lens details (e.g. 50mm f/1.8) and depth-of-field control.
            \(family == "seedream" ? "Seedream renders in-image text well — put any text to render inside double quotes. It excels at dense, structured layouts." : "")
            """
        case "seedance":
            return """
            Seedance 2.0 official guidance: describe the character's actions and how their expression changes over the shot; dynamic elements in the environment (wind, rain, crowds, flickering light); explicit camera movement (dolly-in, pan, orbit, handheld, static). Put spoken dialogue in double quotes for lip-synced audio. Mention desired sound design briefly (it generates audio). For multi-beat shots, a short timed structure works: [0–3s] …, [3–6s] ….
            """
        case "minimax":
            return """
            MiniMax H3 official guidance: write a timed shot list ([0–2s] overhead shot… [2–4s] push in…); use precise cinematography vocabulary (rack focus, handheld shake, fine grain, lens choice); art-direct the audio explicitly (e.g. deep sub-bass, restrained hit); state negative constraints (no soft dissolves, no garbled text); lock character identity with specific feature lists; describe transitions as physical events (whip movement with motion blur) rather than effect names; favor composition instructions over story narration.
            """
        case "kling":
            return """
            Kling v3 Pro guidance: cinematic scene description with fluid motion verbs; specify camera movement and shot progression (it supports multi-shot); describe lighting and mood filmically; keep one clear subject action per beat; mention audio ambience briefly (it generates native audio); avoid abstract or contradictory instructions.
            """
        default:
            return spec.kind == .video
                ? "General video prompting: one clear subject action arc, explicit camera movement, environment dynamics, lighting/mood, and brief audio notes."
                : "General image prompting: subject detail, composition and camera angle, scene and lighting, art style and palette, lens/depth of field."
        }
    }

    private static func jsonGuidance(kind: MediaKind) -> String {
        if kind == .video {
            return """
            Output the prompt as a single JSON object (no markdown fences) with exactly these keys:
            {"subject": "...", "action": "...", "scene": "...", "camera": "...", "lighting": "...", "style": "...", "audio": "...", "timeline": [{"time": "0-3s", "beat": "..."}]}
            Fill every field with concrete, filmable detail. Keep values in the language chosen above.
            """
        }
        return """
        Output the prompt as a single JSON object (no markdown fences) with exactly these keys:
        {"subject": "...", "composition": "...", "scene": "...", "style": "...", "lens": "...", "quality": "..."}
        Fill every field with concrete visual detail. Keep values in the language chosen above.
        """
    }
}
