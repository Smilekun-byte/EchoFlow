import SwiftUI
import SwiftData

struct SettingsView: View {

    // MARK: - AppStorage

    @AppStorage("defaultEngine")          private var defaultEngine          = "deepgram"
    @AppStorage("deepgramAPIKey")         private var deepgramAPIKey         = ""
    @AppStorage("defaultSourceLanguage")  private var defaultSourceLanguage  = "zh-Hans"
    @AppStorage("defaultTargetLanguage")  private var defaultTargetLanguage  = "en"
    @AppStorage("autoTranslate")          private var autoTranslate          = true
    @AppStorage("translationEngine")      private var translationEngine      = "apple"
    @AppStorage("deepseekAPIKey")         private var deepseekAPIKey         = ""
    @AppStorage("microphoneGain")         private var microphoneGain         = 2.0
    @AppStorage("sampleRate")             private var sampleRate             = "16000"
    @AppStorage("autoSaveRecords")        private var autoSaveRecords        = true
    @AppStorage("autoGenerateTitle")      private var autoGenerateTitle      = true
    @AppStorage("recordRetention")        private var recordRetention        = "forever"
    @AppStorage("appearanceMode")         private var appearanceMode         = "system"
    @AppStorage("interfaceLanguage")      private var interfaceLanguage      = "system"

    // MARK: - State

    @State private var showClearAlert = false
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecords: [ConversationRecord]

    // MARK: - Design

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    @Environment(\.colorScheme) private var colorScheme

    private var background: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22),
                                      Color(red: 0.04, green: 0.07, blue: 0.14)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.910, green: 0.957, blue: 0.992),
                                      Color(red: 0.722, green: 0.831, blue: 0.929)],
                             startPoint: .top, endPoint: .bottom)
    }

    private let languages: [(name: String, code: String)] = [
        ("中文", "zh-Hans"), ("英语", "en"),  ("日语", "ja"),
        ("韩语", "ko"),      ("法语", "fr"),  ("西班牙语", "es"), ("德语", "de")
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        engineSection
                        translationSection
                        audioSection
                        historySection
                        appearanceSection
                        aboutSection
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                let deepBlueUI = UIColor(red: 0.172, green: 0.373, blue: 0.541, alpha: 1)
                appearance.largeTitleTextAttributes = [.foregroundColor: deepBlueUI]
                appearance.titleTextAttributes = [.foregroundColor: deepBlueUI]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }

    // MARK: - Sections

    private var engineSection: some View {
        section(header: "🎙️ 识别引擎") {
            row(icon: "cpu", label: "默认引擎") {
                Picker("", selection: $defaultEngine) {
                    Text("Deepgram").tag("deepgram")
                    Text("Apple").tag("apple")
                }
                .pickerStyle(.menu)
                .tint(accentBlue)
            }

            if defaultEngine == "deepgram" {
                divider()
                apiKeyField(
                    icon: "key.fill",
                    label: "Deepgram API Key",
                    key: $deepgramAPIKey
                )
            }
        }
    }

    private var translationSection: some View {
        section(header: "🌐 翻译") {
            row(icon: "textformat", label: "源语言") {
                languagePicker(selection: $defaultSourceLanguage)
            }
            divider()
            row(icon: "arrow.right", label: "目标语言") {
                languagePicker(selection: $defaultTargetLanguage)
            }
            divider()
            row(icon: "bolt.fill", label: "自动翻译") {
                Toggle("", isOn: $autoTranslate).tint(accentBlue)
            }
            divider()
            row(icon: "gearshape", label: "翻译引擎") {
                Picker("", selection: $translationEngine) {
                    Text("Apple").tag("apple")
                    Text("DeepSeek").tag("deepseek")
                }
                .pickerStyle(.menu)
                .tint(accentBlue)
            }

            if translationEngine == "deepseek" {
                divider()
                apiKeyField(
                    icon: "key.fill",
                    label: "DeepSeek API Key",
                    key: $deepseekAPIKey
                )
            }
        }
    }

    private var audioSection: some View {
        section(header: "🔊 音频") {
            // Gain slider
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(accentBlue)
                        .frame(width: 22)
                    Text("增益：\(microphoneGain, specifier: "%.1f")x")
                        .foregroundColor(deepBlue)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("1x").font(.caption2).foregroundColor(.secondary).frame(width: 22, alignment: .leading)
                    Slider(value: $microphoneGain, in: 1.0...8.0, step: 0.5)
                        .tint(accentBlue)
                    Text("8x").font(.caption2).foregroundColor(.secondary).frame(width: 22, alignment: .trailing)
                }
                .padding(.leading, 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

        }
    }

    private var historySection: some View {
        section(header: "📁 历史记录") {
            row(icon: "square.and.arrow.down", label: "自动保存") {
                Toggle("", isOn: $autoSaveRecords).tint(accentBlue)
            }
            divider()
            row(icon: "sparkles", label: "AI 自动生成标题") {
                Toggle("", isOn: $autoGenerateTitle).tint(accentBlue)
            }
            divider()
            row(icon: "clock", label: "保存时长") {
                Picker("", selection: $recordRetention) {
                    Text("7 天").tag("7")
                    Text("30 天").tag("30")
                    Text("永久").tag("forever")
                }
                .pickerStyle(.menu)
                .tint(accentBlue)
            }
            divider()
            Button(role: .destructive) {
                showClearAlert = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash").foregroundColor(.red).frame(width: 22)
                    Text("清空所有记录").foregroundColor(.red)
                    Spacer()
                    Text("\(allRecords.count) 条").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .alert("确认清空", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    allRecords.forEach { modelContext.delete($0) }
                }
            } message: {
                Text("确定要清空所有记录吗？此操作不可撤销")
            }
        }
    }

    private var appearanceSection: some View {
        section(header: "🎨 界面") {
            row(icon: "circle.lefthalf.filled", label: "外观") {
                Picker("", selection: $appearanceMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.menu)
                .tint(accentBlue)
            }
            divider()
            row(icon: "globe", label: "界面语言") {
                Picker("", selection: $interfaceLanguage) {
                    Text("跟随系统").tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
                .tint(accentBlue)
            }
        }
    }

    private var aboutSection: some View {
        section(header: "ℹ️ 关于") {
            // App icon + name + version
            HStack(spacing: 14) {
                Group {
                    if let uiImg = UIImage(named: "AppIcon") {
                        Image(uiImage: uiImg).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accentBlue.opacity(0.2))
                            .overlay(Text("EF").font(.headline.bold()).foregroundColor(accentBlue))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text("EchoFlow")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundColor(deepBlue)
                    Text("版本 \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            divider()

            Link(destination: URL(string: "mailto:feedback@example.com")!) {
                row(icon: "envelope", label: "意见反馈") {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(deepBlue)

            divider()

            Link(destination: URL(string: "https://example.com/privacy")!) {
                row(icon: "hand.raised", label: "隐私政策") {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(deepBlue)

            divider()

            HStack {
                Spacer()
                Text("Made with ❤️ in China")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(icon: String, label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(accentBlue)
                .frame(width: 22)
            Text(label)
                .foregroundColor(deepBlue)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func divider() -> some View {
        Divider().padding(.leading, 50)
    }

    private func languagePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(languages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
        .pickerStyle(.menu)
        .tint(accentBlue)
    }

    private func apiKeyField(icon: String, label: String, key: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(accentBlue)
                    .frame(width: 22)
                Text(label)
                    .foregroundColor(deepBlue)
                Spacer()
                Text(key.wrappedValue.isEmpty ? "未设置" : "已设置")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(key.wrappedValue.isEmpty ? .red : .green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((key.wrappedValue.isEmpty ? Color.red : Color.green).opacity(0.1))
                    .clipShape(Capsule())
            }
            SecureField("输入 API Key", text: key)
                .font(.caption.monospaced())
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
