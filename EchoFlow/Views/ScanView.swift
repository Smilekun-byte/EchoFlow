import SwiftUI
import Vision
import Translation
import NaturalLanguage
import AVFoundation

// MARK: - WordRegion

private struct WordRegion: Identifiable {
    let id   = UUID()
    let text: String
    let rect: CGRect   // Vision normalized coords: (0,0) = bottom-left
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.3
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(
                stops: [
                    .init(color: .clear,               location: 0),
                    .init(color: .white.opacity(0.45), location: 0.5),
                    .init(color: .clear,               location: 1),
                ],
                startPoint: UnitPoint(x: phase,       y: 0.5),
                endPoint:   UnitPoint(x: phase + 0.6, y: 0.5)
            ).clipped()
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.3 }
        }
    }
}

private extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Flow layout

private struct FlowLayout: Layout {
    var hSpacing: CGFloat = 6
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + vSpacing; lineH = 0 }
            x += sz.width + hSpacing; lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineH + vSpacing; lineH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + hSpacing; lineH = max(lineH, sz.height)
        }
    }
}

// MARK: - ScanView

struct ScanView: View {

    enum Mode: String, CaseIterable {
        case ocr      = "扫描"
        case liveText = "识图"
    }

    @AppStorage("defaultSourceLanguage") private var defaultSourceLanguage = "zh-Hans"
    @AppStorage("defaultTargetLanguage") private var defaultTargetLanguage = "en"
    @AppStorage("translationEngine")     private var translationEngine     = "apple"

    @State private var mode:            Mode   = .ocr
    @State private var selectedImage:   UIImage?
    @State private var showImagePicker: Bool   = false
    @State private var pickerSource:    UIImagePickerController.SourceType = .camera

    // Shared OCR result
    @State private var recognizedText: String       = ""
    @State private var wordRegions:    [WordRegion] = []
    @State private var isProcessing:   Bool         = false

    // Word definition
    @State private var selectedWord:       String = ""
    @State private var definition:         String = ""
    @State private var showDefinition:     Bool   = false
    @State private var translatedSentence: String = ""
    @State private var isFetchingSentence: Bool   = false
    @State private var showCopiedToast:    Bool   = false

    // Translation
    @State private var translatedText:     String = ""
    @State private var isTranslating:      Bool   = false
    @State private var translationConfig:  TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?

    private static let synthesizer = AVSpeechSynthesizer()

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        modePicker
                        pickerRow

                        if let img = selectedImage {
                            if mode == .ocr {
                                plainImageCard(img)
                            } else {
                                tappableImageCard(img)
                            }
                        } else {
                            emptyPlaceholder
                        }

                        if mode == .ocr, isProcessing || !recognizedText.isEmpty {
                            ocrResultCard
                        }

                        if !translatedText.isEmpty {
                            translationResultCard
                        }

                        if !recognizedText.isEmpty && !isProcessing {
                            translateButton
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }

                if showCopiedToast { copiedToast }
            }
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                setupTranslationConfig()
                applyTransparentNavBar()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ScanImagePicker(sourceType: pickerSource, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showDefinition) {
            definitionSheet
        }
        .onChange(of: selectedImage) { _, image in
            guard let image else { return }
            recognizedText = ""
            wordRegions    = []
            translatedText = ""
            selectedWord   = ""
            Task { await analyzeImage(image) }
        }
        .onChange(of: mode) { _, _ in
            translatedText = ""
        }
        .translationTask(translationConfig) { session in
            translationSession = session
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Image picker row

    private var pickerRow: some View {
        HStack(spacing: 12) {
            Button {
                pickerSource = .camera; showImagePicker = true
            } label: {
                Label("拍照", systemImage: "camera.fill")
                    .font(.subheadline.weight(.medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Button {
                pickerSource = .photoLibrary; showImagePicker = true
            } label: {
                Label("相册", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium)).foregroundColor(accentBlue)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accentBlue.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Plain image card (扫描 mode)

    private func plainImageCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    // MARK: - Tappable image card (识图 mode)

    private func tappableImageCard(_ image: UIImage) -> some View {
        let ratio = image.size.width / max(image.size.height, 1)
        return Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: geo.size.width, height: geo.size.height)

                        // Tappable word overlays
                        ForEach(wordRegions) { region in
                            let vr = viewRect(region.rect, in: geo.size)
                            Color.clear
                                .frame(width: max(vr.width, 24), height: max(vr.height, 24))
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(selectedWord == region.text
                                              ? accentBlue.opacity(0.3)
                                              : Color.clear)
                                )
                                .position(x: vr.midX, y: vr.midY)
                                .onTapGesture { handleTap(region.text) }
                        }

                        // Loading overlay
                        if isProcessing {
                            Color.black.opacity(0.25)
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // Hint label
                        if !wordRegions.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("轻点文字即可查询")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    /// Convert Vision normalized rect (origin bottom-left) → SwiftUI view coordinates.
    /// Because the image fills the view exactly (matching aspect ratio), no letterbox offset needed.
    private func viewRect(_ r: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: r.minX * size.width,
            y: (1 - r.maxY) * size.height,      // flip Y axis
            width:  r.width  * size.width,
            height: r.height * size.height
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: mode == .ocr ? "camera.viewfinder" : "text.viewfinder")
                .font(.system(size: 44)).foregroundColor(accentBlue.opacity(0.45))
            Text(mode == .ocr ? "拍照或从相册选取图片" : "选取图片，单击文字即可查询释义")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
    }

    // MARK: - OCR result card (扫描 mode)

    private var ocrResultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果").font(.caption.weight(.medium)).foregroundColor(.secondary)
                Spacer()
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7).tint(accentBlue)
                        Text("识别中…").font(.caption2.weight(.semibold)).foregroundColor(accentBlue)
                    }
                } else {
                    Text("Vision OCR")
                        .font(.caption2.weight(.semibold)).foregroundColor(accentBlue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accentBlue.opacity(0.12)).clipShape(Capsule())
                }
            }
            if !recognizedText.isEmpty {
                ScanSelectableTextView(text: recognizedText).frame(minHeight: 100)
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .padding(16).background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Translation result card

    private var translationResultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("译文").font(.caption.weight(.medium)).foregroundColor(.secondary)
            Text(translatedText).font(.body).foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .padding(16).background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Translate button

    private var translateButton: some View {
        Button { Task { await translateAll() } } label: {
            HStack(spacing: 8) {
                if isTranslating { ProgressView().scaleEffect(0.8).tint(.white) }
                else { Image(systemName: "globe") }
                Text(isTranslating ? "翻译中…" : "翻译全文").font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isTranslating ? accentBlue.opacity(0.6) : accentBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: accentBlue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isTranslating)
        .animation(.easeInOut(duration: 0.2), value: isTranslating)
    }

    // MARK: - Definition sheet

    private var definitionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selectedWord).font(.title2.weight(.semibold)).foregroundColor(.primary)
            Divider()
            if definition.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.18))
                            .frame(maxWidth: i == 2 ? 180 : .infinity).frame(height: 15)
                            .shimmer()
                    }
                }
            } else {
                Text(definition).font(.body).foregroundColor(.primary)
                    .transition(.opacity.animation(.easeIn(duration: 0.25)))
            }
            if !translatedSentence.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("例句译文").font(.caption.weight(.medium)).foregroundColor(.secondary)
                    Text(translatedSentence).font(.callout).foregroundColor(.secondary).textSelection(.enabled)
                }
                .transition(.opacity.animation(.easeIn(duration: 0.2)))
            }
            Divider()
            HStack(spacing: 24) {
                Button { speak(selectedWord) } label: { Label("朗读", systemImage: "speaker.wave.2") }
                Button {
                    UIPasteboard.general.string = selectedWord
                    showDefinition = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation { showCopiedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showCopiedToast = false }
                        }
                    }
                } label: { Label("复制", systemImage: "doc.on.doc") }
                Button { Task { await translateSentence() } } label: {
                    if isFetchingSentence { ProgressView().scaleEffect(0.75) }
                    else { Label("翻译全句", systemImage: "globe") }
                }
                .disabled(isFetchingSentence)
            }
            .font(.caption.weight(.medium)).foregroundColor(accentBlue)
            Spacer()
        }
        .padding(24)
        .presentationDetents([.fraction(0.42), .medium])
        .presentationDragIndicator(.visible)
        .background(.ultraThinMaterial)
    }

    private var copiedToast: some View {
        VStack {
            Spacer()
            Text("已复制").font(.caption.weight(.semibold)).foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Color.black.opacity(0.72)).clipShape(Capsule())
            Spacer().frame(height: 110)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
    }

    // MARK: - Image analysis (single Vision pass for both modes)

    private func analyzeImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        let languages = ocrLanguages
        isProcessing = true
        defer { isProcessing = false }

        let (text, regions): (String, [WordRegion]) = await withCheckedContinuation { continuation in
            let tokenizer = NLTokenizer(unit: .word)
            var lines:   [String]     = []
            var regions: [WordRegion] = []

            let request = VNRecognizeTextRequest { req, _ in
                defer { continuation.resume(returning: (lines.joined(separator: "\n"), regions)) }
                guard let observations = req.results as? [VNRecognizedTextObservation] else { return }

                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let line = candidate.string
                    lines.append(line)

                    tokenizer.string = line
                    tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
                        let word = String(line[range])
                        if let box = try? candidate.boundingBox(for: range) {
                            regions.append(WordRegion(text: word, rect: box.boundingBox))
                        }
                        return true
                    }
                }
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages   = languages

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do    { try handler.perform([request]) }
                catch { continuation.resume(returning: ("", [])) }
            }
        }

        recognizedText = text
        wordRegions    = regions
    }

    private var ocrLanguages: [String] {
        switch defaultSourceLanguage {
        case "zh-Hans": return ["zh-Hans", "en-US"]
        case "ja":      return ["ja",       "en-US"]
        case "ko":      return ["ko",       "en-US"]
        case "fr":      return ["fr-FR",    "en-US"]
        case "de":      return ["de-DE",    "en-US"]
        case "es":      return ["es-ES",    "en-US"]
        default:        return ["en-US"]
        }
    }

    // MARK: - Word tap logic

    private func handleTap(_ word: String) {
        withAnimation(.easeInOut(duration: 0.15)) { selectedWord = word }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        definition = ""; translatedSentence = ""
        showDefinition = true
        fetchDefinition(for: word)
    }

    private func fetchDefinition(for word: String) {
        let sentence = extractSentence(containing: word, from: recognizedText)
        Task {
            let result = await DeepSeekService.shared.complete(
                system: "一句话用中文解释词汇在当前语境下的含义。",
                user:   "原句：\(sentence)\n查询词：\(word)"
            )
            await MainActor.run { withAnimation { definition = result } }
        }
    }

    private func extractSentence(containing word: String, from text: String) -> String {
        let sep = CharacterSet(charactersIn: "。！？.!?\n")
        return text.components(separatedBy: sep).first { $0.contains(word) } ?? text
    }

    private func speak(_ word: String) {
        let u = AVSpeechUtterance(string: word)
        u.voice = AVSpeechSynthesisVoice(language: ttsLocale)
        u.rate = 0.4
        ScanView.synthesizer.speak(u)
    }

    private var ttsLocale: String {
        switch defaultSourceLanguage {
        case "zh-Hans": return "zh-CN"; case "ja": return "ja-JP"
        case "ko":      return "ko-KR"; case "fr": return "fr-FR"
        case "de":      return "de-DE"; case "es": return "es-ES"
        default:        return "en-US"
        }
    }

    private func translateSentence() async {
        let sentence = extractSentence(containing: selectedWord, from: recognizedText)
            .trimmingCharacters(in: .whitespaces)
        guard !sentence.isEmpty else { return }
        isFetchingSentence = true; defer { isFetchingSentence = false }
        if translationEngine == "deepseek" {
            let r = await DeepSeekService.shared.translateText(
                text: sentence,
                from: displayName(defaultSourceLanguage),
                to:   displayName(defaultTargetLanguage)
            )
            withAnimation { translatedSentence = r }
        } else {
            guard let session = translationSession else { return }
            if let r = try? await session.translate(sentence) {
                withAnimation { translatedSentence = r.targetText }
            }
        }
    }

    // MARK: - Full translation

    private func translateAll() async {
        guard !recognizedText.isEmpty else { return }
        isTranslating = true; defer { isTranslating = false }
        if translationEngine == "deepseek" {
            translatedText = await DeepSeekService.shared.translateText(
                text: recognizedText,
                from: displayName(defaultSourceLanguage),
                to:   displayName(defaultTargetLanguage)
            )
        } else {
            guard let session = translationSession else { return }
            if let r = try? await session.translate(recognizedText) { translatedText = r.targetText }
        }
    }

    private func setupTranslationConfig() {
        guard defaultSourceLanguage != defaultTargetLanguage else { return }
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: defaultSourceLanguage),
            target: Locale.Language(identifier: defaultTargetLanguage)
        )
    }

    private func displayName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "中文"; case "en": return "英语"; case "ja": return "日语"
        case "ko":      return "韩语"; case "fr": return "法语"; case "es": return "西班牙语"
        case "de":      return "德语"; default: return code
        }
    }

    private func applyTransparentNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        let blue = UIColor(red: 0.172, green: 0.373, blue: 0.541, alpha: 1)
        appearance.largeTitleTextAttributes = [.foregroundColor: blue]
        appearance.titleTextAttributes      = [.foregroundColor: blue]
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Selectable UITextView

private struct ScanSelectableTextView: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false; tv.isSelectable = true
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear; tv.isScrollEnabled = false
        tv.dataDetectorTypes = []; tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }
    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 64
        let sz = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: max(100, sz.height))
    }
}

// MARK: - Image Picker

private struct ScanImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = sourceType; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ScanImagePicker
        init(_ parent: ScanImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.selectedImage = info[.originalImage] as? UIImage; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
