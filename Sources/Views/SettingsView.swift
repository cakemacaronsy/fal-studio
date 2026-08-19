import SwiftUI

struct SettingsView: View {
    var body: some View {
        let _ = Lang.shared.code
        TabView {
            GeneralSettingsView()
                .tabItem { Label(tr("General", "一般"), systemImage: "gearshape") }
            ModelsSettingsView()
                .tabItem { Label(tr("Models", "模型"), systemImage: "square.stack.3d.up") }
        }
        .frame(width: 480)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var apiKey: String = KeychainStore.load() ?? ""
    @State private var saveConfirmed = false
    @State private var lang = Lang.shared
    @AppStorage("mockMode") private var mockMode = false
    @AppStorage("improveModel") private var improveModel = PromptImprover.defaultLLM

    var body: some View {
        Form {
            Section {
                Picker(tr("Language", "語言"), selection: Binding(
                    get: { lang.code },
                    set: { lang.code = $0 }
                )) {
                    Text("English").tag("en")
                    Text("繁體中文").tag("zh-Hant")
                }
            }

            Section {
                SecureField(tr("FAL API key", "FAL API 金鑰"), text: $apiKey,
                            prompt: Text("key_id:key_secret"))
                    .onSubmit(save)
                HStack {
                    Button(tr("Save", "儲存"), action: save)
                    if saveConfirmed {
                        Label(tr("Saved", "已儲存"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
            } header: {
                Text(tr("FAL API Key", "FAL API 金鑰"))
            } footer: {
                Text(tr("Stored in a private file only your account can read. Get a key at fal.ai → Dashboard → Keys.",
                        "儲存在僅你的帳號可讀的私有檔案。金鑰請到 fal.ai → Dashboard → Keys 取得。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField(tr("Improve-prompt LLM", "提示詞優化模型"), text: $improveModel,
                          prompt: Text(PromptImprover.defaultLLM))
                    .autocorrectionDisabled()
            } footer: {
                Text(tr("Any model id from fal's openrouter/router (billed to your FAL key). DeepSeek is the cheap default.",
                        "可填 fal openrouter/router 支援的任一模型 id（用你的 FAL 金鑰計費）。預設為便宜的 DeepSeek。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            updatesSection

            Section {
                Toggle(tr("Mock mode", "模擬模式"), isOn: $mockMode)
            } footer: {
                Text(tr("Generates local placeholders instead of calling FAL. No credits are used.",
                        "以本機占位圖代替呼叫 FAL，不會消耗任何額度。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var updatesSection: some View {
        let updater = updaterState
        Section {
            LabeledContent(tr("Version", "版本"),
                           value: "\(updater.currentVersion) (\(updater.currentBuild))")
            TextField(tr("GitHub repo (optional)", "GitHub 儲存庫（選填）"),
                      text: Binding(get: { updater.githubRepo },
                                    set: { updater.githubRepo = $0 }),
                      prompt: Text("owner/repo"))
                .autocorrectionDisabled()
            HStack {
                Button(tr("Check for updates", "檢查更新")) {
                    Task { await updater.check() }
                }
                if updater.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    switch updater.availability {
                    case .upToDate:
                        Label(tr("Up to date", "已是最新"), systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .localBuild(let version, let build):
                        Button(tr("Install \(version) (\(build)) & relaunch",
                                  "安裝 \(version)（\(build)）並重新啟動")) {
                            updater.applyLocalUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    case .remoteRelease(let tag, _):
                        Button(tr("Download \(tag)", "下載 \(tag)")) {
                            updater.openRemoteUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    case .unknown:
                        EmptyView()
                    }
                }
            }
            if let error = updater.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(tr("Updates", "更新"))
        } footer: {
            Text(tr("Checks your local build folder first, then GitHub Releases if a repo is set.",
                    "先檢查本機建置資料夾，若有設定儲存庫再檢查 GitHub Releases。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var updaterState: Updater { Updater.shared }

    private func save() {
        KeychainStore.save(apiKey)
        saveConfirmed = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            saveConfirmed = false
        }
    }
}

// MARK: - Models

struct ModelsSettingsView: View {
    @State private var store = ModelStore.shared
    @State private var editing: CustomModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.customModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.badge.a")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text(tr("No custom models yet", "還沒有自訂模型"))
                        .foregroundStyle(.secondary)
                    Text(tr("Add any fal.ai endpoint — it appears in the model dropdown\nand uses your same FAL key.",
                            "加入任一 fal.ai 端點——會出現在模型選單，\n使用同一組 FAL 金鑰。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List {
                    ForEach(store.customModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName.isEmpty ? model.endpoint : model.displayName)
                                    .font(.body.weight(.medium))
                                Text(model.endpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.kind == .video ? "Video" : "Image")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                            Button {
                                store.delete(model)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = model }
                    }
                }
                .frame(minHeight: 200)
            }

            Divider()
            HStack {
                Button {
                    editing = CustomModel()
                } label: {
                    Label(tr("Add model", "新增模型"), systemImage: "plus")
                }
                Spacer()
                Text(tr("Custom endpoints run on your FAL key and billing.",
                        "自訂端點使用你的 FAL 金鑰與帳單。"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .sheet(item: $editing) { model in
            CustomModelEditor(model: model) { saved in
                store.upsert(saved)
            }
        }
    }
}

// MARK: - Custom model editor

struct CustomModelEditor: View {
    @State var model: CustomModel
    let onSave: (CustomModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Model") {
                    TextField("Name", text: $model.displayName,
                              prompt: Text("e.g. Seedance 2.5"))
                    Picker("Type", selection: $model.kind) {
                        Text("Image").tag(MediaKind.image)
                        Text("Video").tag(MediaKind.video)
                    }
                    .onChange(of: model.kind) { _, newKind in
                        model.queued = (newKind == .video)
                    }
                    TextField("Endpoint", text: $model.endpoint,
                              prompt: Text("bytedance/seedance-2.5/text-to-video"))
                        .autocorrectionDisabled()
                        .onChange(of: model.endpoint) { _, raw in
                            let normalized = CustomModel.normalizeEndpoint(raw)
                            if normalized != raw { model.endpoint = normalized }
                        }
                    Toggle("Queue API (long-running jobs)", isOn: $model.queued)
                }

                Section("Input images") {
                    Picker("Accepts", selection: $model.refMode) {
                        Text("Text only").tag(CustomModel.RefMode.none)
                        Text("Start (+ end) frame").tag(CustomModel.RefMode.startEnd)
                        Text("Multiple references").tag(CustomModel.RefMode.multiple)
                    }
                    if model.refMode != .none {
                        Picker("Payload field", selection: $model.refPayloadKey) {
                            ForEach(CustomModel.refKeyOptions, id: \.self) { Text($0) }
                        }
                    }
                    if model.refMode == .multiple {
                        Stepper("Max images: \(model.refMax)", value: $model.refMax, in: 1...10)
                    }
                    if model.refMode == .startEnd {
                        Toggle("Supports end frame (end_image_url)", isOn: $model.acceptsEndImage)
                    }
                }

                Section {
                    TextEditor(text: $model.fixedParamsJSON)
                        .font(.system(.callout, design: .monospaced))
                        .frame(height: 70)
                } header: {
                    Text("Extra parameters (JSON, optional)")
                } footer: {
                    Text(#"Merged into every request, e.g. {"resolution": "720p", "duration": "5"}"#)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Estimated cost per generation (USD)",
                              value: $model.estCost, format: .number)
                } footer: {
                    Text("Only used for the ~$ display next to Generate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(tr("Cancel", "取消")) { dismiss() }
                Spacer()
                Button(tr("Save", "儲存")) { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
    }

    private func save() {
        model.endpoint = CustomModel.normalizeEndpoint(model.endpoint)
        if model.endpoint.isEmpty {
            validationError = "Endpoint is required, e.g. bytedance/seedance-2.5/text-to-video"
            return
        }
        if model.fixedPayload == nil {
            validationError = "Extra parameters must be a valid JSON object like {\"resolution\": \"720p\"}"
            return
        }
        onSave(model)
        dismiss()
    }
}
