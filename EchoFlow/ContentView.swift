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

    @State private var waves: [WaveRing] = []
    @State private var waveTimer: Timer?

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
        .translationTask(translationConfig) { session in
            translationSession = session
        }
        .onAppear {
            appleTranscription.requestPermission { granted in
                print(granted ? "✅ 语音识别权限已获取" : "❌ 权限被拒绝")
            }
            audioManager.onBufferReady = { [weak deepgramService, weak appleTranscription] buffer in
                deepgramService?.sendAudio(buffer)
                appleTranscription?.appendBuffer(buffer)
            }
            updateTranslationConfig()
        }
        .onChange(of: sourceLanguage) { _, _ in updateTranslationConfig() }
        .onChange(of: targetLanguage) { _, _ in updateTranslationConfig() }
        .onChange(of: currentTranscript) { _, newText in
            guard !newText.isEmpty, sourceLanguage != targetLanguage else { return }
            Task {
                guard let session = translationSession else { return }
                do {
                    let response = try await session.translate(newText)
                    translatedText = response.targetText
                } catch {
                    print("❌ 翻译错误: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Subviews

    private var title: some View {
        Text("EchoFlow")
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
                HStack {
                    Text("原文")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(useDeepgram ? "Deepgram" : "Apple")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(Capsule())
                }
                ScrollView {
                    Text(currentTranscript.isEmpty ? "开始说话..." : currentTranscript)
                        .font(.body)
                        .foregroundColor(currentTranscript.isEmpty ? .secondary.opacity(0.6) : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 100)
            }
        }
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
            ForEach(waves) { ring in
                Circle()
                    .stroke(accentBlue.opacity(ring.opacity), lineWidth: 2.0 / ring.scale)
                    .frame(width: 72 * ring.scale, height: 72 * ring.scale)
            }

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
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRecording {
                            startRecording()
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        stopRecording()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
        }
        .frame(height: 130)
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

    private func startRecording() {
        do {
            try audioManager.startRecording()
            if useDeepgram {
                deepgramService.connect(sampleRate: audioManager.actualSampleRate)
            } else {
                appleTranscription.startTranscription()
            }
            isRecording = true
            errorMessage = nil
            startWaveTimer()
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
        stopWaveTimer()

        let original = currentTranscript
        let translated = translatedText
        guard !original.isEmpty, !translated.isEmpty else { return }
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

        Task {
            if let meta = await ClaudeMetadataService.shared.generateMetadata(
                original: original, translated: translated
            ) {
                record.title = meta.title
                record.keywords = meta.keywords
            }
        }
    }

    private func startWaveTimer() {
        waveTimer?.invalidate()
        spawnWave()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            spawnWave()
        }
    }

    private func stopWaveTimer() {
        waveTimer?.invalidate()
        waveTimer = nil
        // existing waves finish their own animations naturally
    }

    private func spawnWave() {
        let ring = WaveRing()
        waves.append(ring)
        let id = ring.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 1.6)) {
                if let idx = waves.firstIndex(where: { $0.id == id }) {
                    waves[idx].scale = 2.5
                    waves[idx].opacity = 0.0
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            waves.removeAll { $0.id == id }
        }
    }
}

// MARK: - Wave Ring

private struct WaveRing: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1.0
    var opacity: Double = 0.5
}
