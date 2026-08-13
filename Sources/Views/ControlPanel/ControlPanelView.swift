import SwiftUI

struct ControlPanelView: View {
    @Environment(GenerationDraft.self) private var draft
    @Environment(GenerationManager.self) private var generator

    var body: some View {
        // Observe the language so the panel re-renders on switch.
        let _ = Lang.shared.code
        VStack(spacing: 0) {
            ModeTabBar(draft: draft)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modelPicker

                    if draft.spec.refImages != .none {
                        ReferenceImageDropZone(draft: draft)
                    }

                    promptEditor

                    ParameterChipsView(draft: draft)
                }
                .padding(16)
            }

            Divider()
            GenerateBar(draft: draft)
                .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Model", "模型"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(tr("Model", "模型"), selection: Binding(
                get: { draft.modelID },
                set: { draft.selectModel($0) }
            )) {
                ForEach(ModelStore.shared.models(for: draft.mode)) { spec in
                    Text(spec.displayName).tag(spec.id)
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("Prompt", "提示詞"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                improveControls
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { draft.prompt },
                    set: { draft.prompt = $0 }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96, maxHeight: 180)
                if draft.prompt.isEmpty {
                    Text(draft.mode == .image
                         ? tr("Describe the image you want…", "描述你想生成的圖片…")
                         : tr("Describe the video you want…", "描述你想生成的影片…"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            if let error = draft.improveError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// ✨ Improve (per-model official guidance) · {} JSON mode · ↩ revert
    private var improveControls: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { draft.jsonMode }, set: { draft.jsonMode = $0 })) {
                Text("{ }")
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(tr("Improve as a structured JSON prompt", "以結構化 JSON 格式優化提示詞"))

            if draft.promptBackup != nil {
                Button {
                    draft.revertImproved()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(tr("Revert to your original prompt", "還原原始提示詞"))
            }

            Button {
                improve()
            } label: {
                if draft.isImproving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(tr("Improve", "優化"), systemImage: "wand.and.stars")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(draft.isImproving
                      || draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || (!generator.mockMode && !generator.hasAPIKey))
            .help(tr("Rewrite the prompt per this model's official prompting guide",
                     "依此模型官方提示詞指南優化"))
        }
    }

    private func improve() {
        let original = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        draft.isImproving = true
        draft.improveError = nil
        let spec = draft.spec
        let json = draft.jsonMode
        Task {
            do {
                let improved = try await generator.improve(prompt: original, spec: spec, jsonMode: json)
                draft.applyImproved(improved)
            } catch {
                draft.improveError = error.localizedDescription
            }
            draft.isImproving = false
        }
    }
}

// MARK: - Mode tabs

struct ModeTabBar: View {
    @Bindable var draft: GenerationDraft

    var body: some View {
        HStack(spacing: 4) {
            tab(tr("Image", "圖片"), systemImage: "photo", kind: .image)
            tab(tr("Video", "影片"), systemImage: "film", kind: .video)
        }
        .padding(4)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1))
    }

    private func tab(_ title: String, systemImage: String, kind: MediaKind) -> some View {
        let selected = draft.mode == kind
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                draft.selectMode(kind)
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.18) : .clear)
                )
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Parameter chips

struct ParameterChipsView: View {
    @Bindable var draft: GenerationDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Settings", "設定"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if draft.spec.parameters.isEmpty {
                Text(tr("This model uses its endpoint defaults (edit in Settings → Models).",
                        "此模型使用端點預設值（可在設定 → 模型中編輯）。"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(draft.spec.parameters) { param in
                        chip(for: param)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func chip(for param: ParameterSpec) -> some View {
        switch param.kind {
        case .choice(let options, _):
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        draft.setValue(.string(option), for: param.key)
                    } label: {
                        let selected = draft.value(for: param).stringValue == option
                        if param.key == "aspect_ratio" {
                            // Shape glyph shows the output orientation at a glance.
                            Label {
                                Text(selected ? "\(option) ✓" : option)
                            } icon: {
                                Image(nsImage: AspectGlyph.image(for: option))
                            }
                        } else if selected {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                chipLabel("\(trParam(param.label)) · \(draft.value(for: param).stringValue ?? "?")",
                          highlighted: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

        case .toggle:
            let isOn = draft.value(for: param).boolValue ?? false
            Button {
                draft.setValue(.bool(!isOn), for: param.key)
            } label: {
                chipLabel("\(trParam(param.label)) \(isOn ? tr("on", "開") : tr("off", "關"))",
                          highlighted: isOn)
            }
            .buttonStyle(.plain)

        case .stepper(let range, _):
            Menu {
                ForEach(Array(range), id: \.self) { n in
                    Button {
                        draft.setValue(.int(n), for: param.key)
                    } label: {
                        if draft.value(for: param).intValue == n {
                            Label(String(n), systemImage: "checkmark")
                        } else {
                            Text(String(n))
                        }
                    }
                }
            } label: {
                chipLabel("\(trParam(param.label)) · \(draft.value(for: param).intValue ?? 1)",
                          highlighted: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func chipLabel(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(highlighted
                               ? Color.accentColor.opacity(0.18)
                               : Color(nsColor: .quaternarySystemFill))
            )
            .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
    }
}

// MARK: - Generate bar

struct GenerateBar: View {
    @Bindable var draft: GenerationDraft
    @Environment(GenerationManager.self) private var generator

    private var blockedReason: String? {
        if !generator.mockMode && !generator.hasAPIKey {
            return tr("Add your FAL key in Settings (⌘,)", "請在設定（⌘,）加入你的 FAL 金鑰")
        }
        if draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("Describe what you want to generate.", "先描述你想生成的內容。")
        }
        switch draft.spec.refImages {
        case .startEnd where draft.refImages.isEmpty:
            return tr("Drop a start-frame image.", "請拖入起始畫格圖片。")
        case .multiple where draft.refImages.isEmpty:
            return tr("Drop at least one reference image.", "請至少拖入一張參考圖。")
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = blockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Estimated cost", "預估費用"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(draft.estimatedCost > 0
                         ? "~$\(draft.estimatedCost, specifier: "%.2f")"
                         : "~$?")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    generator.start(
                        spec: draft.spec,
                        prompt: draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                        values: draft.paramValues,
                        refDatas: draft.refImages.map(\.encoded.data),
                        endRefData: draft.endImage?.encoded.data
                    )
                } label: {
                    Label(tr("Generate", "生成"), systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(blockedReason != nil)
            }
        }
    }
}
