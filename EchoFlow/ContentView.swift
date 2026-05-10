import SwiftUI
import SwiftData
import Translation
import UIKit

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var appleTranscription = TranscriptionService()
    @StateObject private var deepgramService = DeepgramService()

    @State private var useDeepgram: Bool = true
    @State private var isRecording = false
    @State private var translatedText: String = ""
    @State private var sourceLanguage: SupportedLanguage = .chinese
    @State private var targetLanguage: SupportedLanguage = .english
    @State private var errorMessage: String?

    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?

    @State private var particles: [Particle] = []
    @State private var waves: [WaveRing] = []
    @State private var waveTimer: Timer?

    @State private var correctedText: String = ""
    @State private var isCorrectingText: Bool = false

    @State private var editedTranscript: String = ""
    @FocusState private var isEditorFocused: Bool
    @State private var translationDebounceTask: Task<Void, Never>?
    @State private var showRetranslated: Bool = false

    @AppStorage("defaultEngine")      private var defaultEngine      = "deepgram"
    @AppStorage("autoSaveRecords")    private var autoSaveRecords    = true
    @AppStorage("autoGenerateTitle")  private var autoGenerateTitle  = true
    @AppStorage("autoTranslate")      private var autoTranslate      = true
    @AppStorage("translationEngine")  private var translationEngine  = "apple"

    @Namespace private var engineNS
    @Environment(\.colorScheme) private var colorScheme

    var currentTranscript: String {
        useDeepgram ? deepgramService.transcribedText : appleTranscription.transcribedText
    }

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541) // #2C5F8A
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965) // #3B82F6

    private var background: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(red: 0.08, green: 0.13, blue: 0.22),
                         Color(red: 0.04, green: 0.07, blue: 0.14)],
                startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [Color(red: 0.910, green: 0.957, blue: 0.992),
                         Color(red: 0.722, green: 0.831, blue: 0.929)],
                startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    title
                    enginePicker
                    languageSelector
                    transcriptCard
                    translationCard
                    recordButton
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .translationTask(translationConfig) { session in
            translationSession = session
        }
        .onAppear {
            useDeepgram = defaultEngine == "deepgram"
            appleTranscription.requestPermission { granted in
                print(granted ? "✅ 语音识别权限已获取" : "❌ 权限被拒绝")
            }
            audioManager.onBufferReady = { [weak deepgramService, weak appleTranscription] buffer in
                deepgramService?.sendAudio(buffer)
                appleTranscription?.appendBuffer(buffer)
            }
            updateTranslationConfig()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if isRecording {
                audioManager.stopRecording()
                deepgramService.disconnect()
                appleTranscription.stopTranscription()
                isRecording = false
                stopRecordingAnimation()
            }
            audioManager.suspendHaptics()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            deepgramService.transcribedText = ""
            appleTranscription.transcribedText = ""
            translatedText = ""
            correctedText = ""
            editedTranscript = ""
            audioManager.resumeHaptics()
        }
        .onChange(of: defaultEngine) { _, newValue in useDeepgram = newValue == "deepgram" }
        .onChange(of: sourceLanguage) { _, _ in updateTranslationConfig() }
        .onChange(of: targetLanguage) { _, _ in updateTranslationConfig() }
        .onChange(of: currentTranscript) { _, newText in
            // 录音时同步到可编辑字段，并立即翻译
            editedTranscript = newText
            guard !newText.isEmpty, sourceLanguage != targetLanguage, autoTranslate, isRecording else { return }
            Task { await performTranslation(newText) }
        }
        .onChange(of: editedTranscript) { _, newText in
            // 用户手动编辑时防抖 0.8s 后翻译
            guard !isRecording else { return }
            translationDebounceTask?.cancel()
            guard !newText.isEmpty, sourceLanguage != targetLanguage, autoTranslate else { return }
            translationDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                await performTranslation(newText)
                showRetranslated = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showRetranslated = false
            }
        }
    }

    // MARK: - Subviews

    private var title: some View {
        Text("共鳴")
            .font(.system(.title, design: .rounded, weight: .semibold))
            .foregroundColor(deepBlue)
    }

    private var enginePicker: some View {
        HStack(spacing: 0) {
            engineTab("Deepgram", selected: useDeepgram)  { useDeepgram = true  }
            engineTab("Apple",    selected: !useDeepgram) { useDeepgram = false }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func engineTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { action() }
        }) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(selected ? deepBlue : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .matchedGeometryEffect(id: "engineSlider", in: engineNS)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var languageSelector: some View {
        HStack(spacing: 16) {
            Menu {
                ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                    Button(lang.displayName) {
                        sourceLanguage = lang
                        appleTranscription.setLanguage(lang)
                    }
                }
            } label: {
                languagePill(sourceLanguage.displayName)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentBlue)

            Menu {
                ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                    Button(lang.displayName) { targetLanguage = lang }
                }
            } label: {
                languagePill(targetLanguage.displayName)
            }
        }
    }

    private func languagePill(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundColor(deepBlue)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(deepBlue.opacity(0.6))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var transcriptCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text("原文")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    // 纠错按钮
                    if !editedTranscript.isEmpty {
                        Button {
                            correctCurrentTranscript()
                        } label: {
                            HStack(spacing: 4) {
                                if isCorrectingText {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                        .tint(accentBlue)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.caption2.weight(.semibold))
                                }
                                Text(isCorrectingText ? "纠错中" : "纠错")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentBlue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .disabled(isCorrectingText)
                        .animation(.easeInOut(duration: 0.2), value: isCorrectingText)
                    }
                    // 状态标签：编辑中 / 已重新翻译 / 引擎名
                    Group {
                        if isEditorFocused {
                            Label("编辑中", systemImage: "pencil")
                        } else if showRetranslated {
                            Label("已重新翻译", systemImage: "arrow.counterclockwise")
                        } else {
                            Text(useDeepgram ? "Deepgram" : "Apple")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(isEditorFocused ? accentBlue : (showRetranslated ? .green : accentBlue))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isEditorFocused ? accentBlue : (showRetranslated ? Color.green : accentBlue)).opacity(0.12))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.2), value: isEditorFocused)
                    .animation(.easeInOut(duration: 0.2), value: showRetranslated)
                }

                // 可编辑原文区域
                ZStack(alignment: .topLeading) {
                    if editedTranscript.isEmpty && !isEditorFocused {
                        Text("开始说话...")
                            .font(.body)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $editedTranscript)
                        .font(.body)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 100)
                        .focused($isEditorFocused)
                }

                // 纠错结果区块
                if !correctedText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundColor(accentBlue)
                            Text("纠错结果")
                                .font(.caption.weight(.medium))
                                .foregroundColor(accentBlue)
                            Spacer()
                            Button {
                                correctedText = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(correctedText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(deepBlue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentBlue.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: correctedText.isEmpty)
        }
        // 编辑时蓝色边框
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accentBlue.opacity(isEditorFocused ? 0.6 : 0), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isEditorFocused)
    }

    private var translationCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("译文")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(translatedText.isEmpty ? "翻译结果..." : translatedText)
                        .font(.body)
                        .foregroundColor(translatedText.isEmpty ? .secondary.opacity(0.6) : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 100)
            }
        }
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var recordButton: some View {
        ZStack {
            // 粒子层
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .offset(x: p.x, y: p.y)
                    .opacity(p.opacity)
            }

            // 波纹层
            ForEach(waves) { wave in
                Circle()
                    .stroke(
                        Color(
                            red:   0.2 + Double(wave.scale) * 0.1,
                            green: 0.5 + Double(wave.scale) * 0.1,
                            blue:  0.9
                        ),
                        lineWidth: max(0.3, 2.5 - wave.scale * 0.5)
                    )
                    .frame(width: 72 * wave.scale, height: 72 * wave.scale)
                    .opacity(wave.opacity)
            }

            // 麦克风按钮
            ZStack {
                Circle()
                    .fill(isRecording ? AnyShapeStyle(accentBlue) : AnyShapeStyle(.ultraThinMaterial))
                    .frame(width: 72, height: 72)
                    .shadow(
                        color: isRecording ? accentBlue.opacity(0.45) : accentBlue.opacity(0.15),
                        radius: isRecording ? 16 : 10
                    )

                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isRecording ? .white : accentBlue)
            }
            .scaleEffect(isRecording ? 1.0 + CGFloat(audioManager.currentRMS) * 0.15 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: audioManager.currentRMS)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRecording {
                            startRecording()
                            triggerParticleBurst()
                        }
                    }
                    .onEnded { _ in
                        stopRecording()
                    }
            )
        }
        .frame(height: 160)
    }

    // MARK: - Logic

    private func updateTranslationConfig() {
        guard sourceLanguage != targetLanguage else {
            translationConfig = nil
            translationSession = nil
            translatedText = ""
            return
        }
        translationSession = nil
        translatedText = ""
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguage.rawValue),
            target: Locale.Language(identifier: targetLanguage.rawValue)
        )
    }

    @MainActor
    private func performTranslation(_ text: String) async {
        if translationEngine == "deepseek" {
            let result = await DeepSeekService.shared.translateText(
                text: text,
                from: sourceLanguage.displayName,
                to: targetLanguage.displayName
            )
            translatedText = result
        } else {
            guard let session = translationSession else { return }
            do {
                let response = try await session.translate(text)
                translatedText = response.targetText
            } catch {
                print("❌ 翻译错误: \(error.localizedDescription)")
            }
        }
    }

    private func correctCurrentTranscript() {
        let text = editedTranscript
        guard !text.isEmpty, !isCorrectingText else { return }
        isCorrectingText = true
        correctedText = ""
        Task {
            let result = await DeepSeekService.shared.correctTranscript(
                text: text,
                language: sourceLanguage.displayName
            )
            correctedText = result == text ? "" : result
            isCorrectingText = false
        }
    }

    private func startRecording() {
        correctedText = ""
        do {
            try audioManager.startRecording()
            if useDeepgram {
                deepgramService.connect(sampleRate: audioManager.actualSampleRate)
            } else {
                appleTranscription.startTranscription()
            }
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = "启动失败: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioManager.stopRecording()
        if useDeepgram {
            deepgramService.disconnect()
        } else {
            appleTranscription.stopTranscription()
        }
        isRecording = false
        stopRecordingAnimation()

        let original = editedTranscript
        let translated = translatedText
        guard !original.isEmpty, !translated.isEmpty, autoSaveRecords else { return }
        autoSave(original: original, translated: translated)
    }

    private func autoSave(original: String, translated: String) {
        let record = ConversationRecord(
            sourceLanguage: sourceLanguage.displayName,
            targetLanguage: targetLanguage.displayName,
            originalText: original,
            translatedText: translated
        )
        modelContext.insert(record)

        guard autoGenerateTitle else { return }
        Task {
            if let meta = await DeepSeekService.shared.generateMetadata(
                original: original, translated: translated
            ) {
                record.title = meta.title
                record.keywords = meta.keywords
            }
        }
    }

    // MARK: - 粒子爆发（按下瞬间）

    private func triggerParticleBurst() {
        let colors: [Color] = [
            Color(red: 0.2, green: 0.5, blue: 0.9),
            Color(red: 0.4, green: 0.7, blue: 1.0),
            Color(red: 0.6, green: 0.85, blue: 1.0)
        ]
        particles = (0..<40).map { _ in
            Particle(
                angle:  Double.random(in: 0..<360),
                speed:  Double.random(in: 0.8...2.0),
                size:   CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.6...1.0),
                color:  colors.randomElement()!
            )
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        withAnimation(.easeOut(duration: 0.8)) {
            for i in particles.indices {
                let rad = particles[i].angle * .pi / 180
                let dist = CGFloat(particles[i].speed * 80)
                particles[i].x = cos(rad) * dist
                particles[i].y = sin(rad) * dist
                particles[i].opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.particles = []
            self.startWaveAnimation()
        }
    }

    // MARK: - 水波持续动画（粒子消失后）

    private func startWaveAnimation() {
        guard isRecording else { return }
        let interval = max(0.15, 0.4 - Double(audioManager.currentRMS) * 0.25)
        waveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.addWave()
        }
    }

    private func addWave() {
        let rms = audioManager.currentRMS
        let maxScale = CGFloat(1.2 + Double(rms) * 3.0)
        let wave = WaveRing()
        waves.append(wave)
        let id = wave.id

        withAnimation(.easeOut(duration: 1.6)) {
            if let idx = self.waves.firstIndex(where: { $0.id == id }) {
                self.waves[idx].scale = maxScale
                self.waves[idx].opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            self.waves.removeAll { $0.id == id }
        }
    }

    // MARK: - 停止录音动画

    private func stopRecordingAnimation() {
        waveTimer?.invalidate()
        waveTimer = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 已有波纹继续播放直到自然消失
    }
}

// MARK: - Wave Ring

private struct WaveRing: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1.0
    var opacity: Double = 0.6
}

// MARK: - Particle

private struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat = 0
    var y: CGFloat = 0
    var angle: Double
    var speed: Double
    var size: CGFloat
    var opacity: Double
    var color: Color
}
