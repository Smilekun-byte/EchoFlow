import SwiftUI
import Translation

struct OCRView: View {

    @AppStorage("defaultSourceLanguage") private var defaultSourceLanguage = "zh-Hans"
    @AppStorage("defaultTargetLanguage") private var defaultTargetLanguage = "en"
    @AppStorage("translationEngine")     private var translationEngine     = "apple"

    @State private var selectedImage:   UIImage?
    @State private var recognizedText:  String = ""
    @State private var translatedText:  String = ""
    @State private var isProcessing:    Bool   = false
    @State private var isTranslating:   Bool   = false
    @State private var showImagePicker: Bool   = false
    @State private var pickerSource:    UIImagePickerController.SourceType = .camera

    @State private var translationConfig:  TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?

    private let ocrService = OCRService()
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        pickerRow
                        if let img = selectedImage {
                            imageCard(img)
                        } else {
                            emptyPlaceholder
                        }
                        if isProcessing || !recognizedText.isEmpty {
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
            }
            .navigationTitle("扫描")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                setupTranslationConfig()
                applyTransparentNavBar()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: pickerSource, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, image in
            guard let image else { return }
            performOCR(image: image)
        }
        .translationTask(translationConfig) { session in
            translationSession = session
        }
    }

    // MARK: - Picker row

    private var pickerRow: some View {
        HStack(spacing: 12) {
            Button {
                pickerSource = .camera
                showImagePicker = true
            } label: {
                Label("拍照", systemImage: "camera.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Button {
                pickerSource = .photoLibrary
                showImagePicker = true
            } label: {
                Label("相册", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accentBlue.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Image cards

    private func imageCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundColor(accentBlue.opacity(0.45))
            Text("拍照或从相册选取图片")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - OCR result card

    private var ocrResultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7).tint(accentBlue)
                        Text("识别中…")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(accentBlue)
                    }
                } else {
                    Text("Vision OCR")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if !recognizedText.isEmpty {
                SelectableTextView(text: recognizedText)
                    .frame(minHeight: 100)
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Translation result card

    private var translationResultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("译文")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            Text(translatedText)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: deepBlue.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Translate button

    private var translateButton: some View {
        Button {
            Task { await translateAll() }
        } label: {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: "globe")
                }
                Text(isTranslating ? "翻译中…" : "翻译全文")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isTranslating ? accentBlue.opacity(0.6) : accentBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: accentBlue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isTranslating)
        .animation(.easeInOut(duration: 0.2), value: isTranslating)
    }

    // MARK: - Logic

    private func performOCR(image: UIImage) {
        recognizedText = ""
        translatedText = ""
        isProcessing = true
        ocrService.recognize(image: image, languages: ocrLanguages) { texts in
            self.recognizedText = texts.joined(separator: "\n")
            self.isProcessing = false
        }
    }

    private var ocrLanguages: [String] {
        switch defaultSourceLanguage {
        case "zh-Hans": return ["zh-Hans", "en-US"]
        case "ja":      return ["ja", "en-US"]
        case "ko":      return ["ko", "en-US"]
        case "fr":      return ["fr-FR", "en-US"]
        case "de":      return ["de-DE", "en-US"]
        case "es":      return ["es-ES", "en-US"]
        default:        return ["en-US"]
        }
    }

    private func translateAll() async {
        guard !recognizedText.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }

        if translationEngine == "deepseek" {
            let result = await DeepSeekService.shared.translateText(
                text: recognizedText,
                from: displayName(defaultSourceLanguage),
                to:   displayName(defaultTargetLanguage)
            )
            translatedText = result
        } else {
            guard let session = translationSession else { return }
            do {
                let response = try await session.translate(recognizedText)
                translatedText = response.targetText
            } catch {
                print("❌ OCR翻译错误: \(error.localizedDescription)")
            }
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
        case "zh-Hans": return "中文"
        case "en":      return "英语"
        case "ja":      return "日语"
        case "ko":      return "韩语"
        case "fr":      return "法语"
        case "es":      return "西班牙语"
        case "de":      return "德语"
        default:        return code
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

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable   = false
        tv.isSelectable = true
        tv.font         = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.dataDetectorTypes = []
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 64
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(100, size.height))
    }
}

// MARK: - Image Picker

private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
