import SwiftUI
import Vision
import NaturalLanguage
import AVFoundation

// MARK: - WordRegion

private struct WordRegion: Identifiable {
    let id   = UUID()
    let text: String
    let rect: CGRect   // Vision normalized coords: (0,0) = bottom-left
}

// MARK: - System dictionary wrapper

private struct DictionaryView: UIViewControllerRepresentable {
    let word: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: word)
    }

    func updateUIViewController(_ vc: UIReferenceLibraryViewController, context: Context) {}
}

// MARK: - LiveTextView

struct LiveTextView: View {

    @AppStorage("defaultSourceLanguage") private var defaultSourceLanguage = "zh-Hans"

    @State private var selectedImage:   UIImage?
    @State private var wordRegions:     [WordRegion] = []
    @State private var recognizedText:  String = ""
    @State private var isProcessing:    Bool   = false
    @State private var showImagePicker: Bool   = false

    @State private var selectedWord:   String = ""
    @State private var aiDefinition:   String = ""
    @State private var showDefinition: Bool   = false

    // Zoom & pan
    @State private var imageScale:  CGFloat = 1.0
    @State private var lastScale:   CGFloat = 1.0
    @State private var imageOffset: CGSize  = .zero
    @State private var lastOffset:  CGSize  = .zero

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
                        pickerButton
                        if let img = selectedImage {
                            tappableImageCard(img)
                        } else {
                            emptyPlaceholder
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("识图")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { applyTransparentNavBar() }
        }
        .sheet(isPresented: $showImagePicker) {
            LiveImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showDefinition) {
            definitionSheet
        }
        .onChange(of: selectedImage) { _, image in
            guard let image else { return }
            wordRegions = []; recognizedText = ""
            imageScale  = 1.0; lastScale  = 1.0
            imageOffset = .zero; lastOffset = .zero
            Task { await analyzeImage(image) }
        }
    }

    // MARK: - Picker button

    private var pickerButton: some View {
        Button { showImagePicker = true } label: {
            Label("从相册选择", systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Tappable image card

    private func tappableImageCard(_ image: UIImage) -> some View {
        let ratio = image.size.width / max(image.size.height, 1)
        return VStack(spacing: 8) {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay(
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: geo.size.width, height: geo.size.height)

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

                            if isProcessing {
                                Color.black.opacity(0.2)
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            if !wordRegions.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("轻点文字即可查询")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 10)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageScale = max(1.0, min(lastScale * value, 5.0))
                                }
                                .onEnded { _ in
                                    imageScale = max(1.0, min(imageScale, 5.0))
                                    lastScale  = imageScale
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            imageOffset = CGSize(
                                                width:  lastOffset.width  + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = imageOffset
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                imageScale  = 1.0
                                lastScale   = 1.0
                                imageOffset = .zero
                                lastOffset  = .zero
                            }
                        }
                    }
                    .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1))
                .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)

            Text("双指缩放 · 双击还原")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// Vision normalized rect (origin bottom-left) → SwiftUI view coordinates.
    private func viewRect(_ r: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: r.minX * size.width,
            y: (1 - r.maxY) * size.height,
            width:  r.width  * size.width,
            height: r.height * size.height
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44)).foregroundColor(accentBlue.opacity(0.45))
            Text("选取图片，单击文字即可查询释义")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
    }

    // MARK: - Definition sheet

    private var definitionSheet: some View {
        VStack(spacing: 0) {

            // Word + speaker
            HStack(alignment: .center) {
                Text(selectedWord)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Spacer()
                Button { speak(selectedWord) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundColor(accentBlue)
                        .padding(8)
                        .background(accentBlue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Divider().padding(.vertical, 8)

            // System dictionary (main content)
            DictionaryView(word: selectedWord)
                .id(selectedWord)      // recreate VC when word changes
                .frame(minHeight: 200)

            Divider().padding(.vertical, 8)

            // AI context (auxiliary)
            VStack(alignment: .leading, spacing: 6) {
                Label("AI 语境解释", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Group {
                    if aiDefinition.isEmpty {
                        Text("分析中…")
                            .foregroundColor(.secondary.opacity(0.4))
                    } else {
                        Text(aiDefinition)
                            .foregroundColor(.secondary)
                            .transition(.opacity.animation(.easeIn(duration: 0.2)))
                    }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Image analysis

    private func analyzeImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        let languages = ocrLanguages
        isProcessing = true
        defer { isProcessing = false }

        let tokenizer = NLTokenizer(unit: .word)

        let (text, regions): (String, [WordRegion]) = await withCheckedContinuation { continuation in
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

    // MARK: - Tap handling

    private func handleTap(_ word: String) {
        withAnimation(.easeInOut(duration: 0.15)) { selectedWord = word }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        aiDefinition = ""
        showDefinition = true
        fetchAIDefinition(for: word)
    }

    private func fetchAIDefinition(for word: String) {
        let sentence = extractSentence(containing: word, from: recognizedText)
        Task {
            let result = await DeepSeekService.shared.complete(
                system: "一句话用中文解释词汇在当前语境下的含义，格式：在本文中：[解释]",
                user:   "原句：\(sentence)\n查询词：\(word)"
            )
            await MainActor.run { withAnimation { aiDefinition = result } }
        }
    }

    private func extractSentence(containing word: String, from text: String) -> String {
        let sep = CharacterSet(charactersIn: "。！？.!?\n")
        return text.components(separatedBy: sep).first { $0.contains(word) } ?? text
    }

    // MARK: - TTS with language detection

    private func speak(_ word: String) {
        let u = AVSpeechUtterance(string: word)
        u.voice = AVSpeechSynthesisVoice(language: detectedLocale(for: word))
        u.rate  = 0.4
        LiveTextView.synthesizer.speak(u)
    }

    /// Uses NLLanguageRecognizer so Japanese words get a Japanese voice, English get English, etc.
    private func detectedLocale(for text: String) -> String {
        let rec = NLLanguageRecognizer()
        rec.processString(text)
        switch rec.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese: return "zh-CN"
        case .japanese:  return "ja-JP"
        case .korean:    return "ko-KR"
        case .french:    return "fr-FR"
        case .german:    return "de-DE"
        case .spanish:   return "es-ES"
        default:         return "en-US"
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

// MARK: - Image Picker

private struct LiveImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LiveImagePicker
        init(_ parent: LiveImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
