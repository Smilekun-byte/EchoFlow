import SwiftUI
import VisionKit
import Translation

struct LiveTextView: View {

    @AppStorage("defaultSourceLanguage") private var defaultSourceLanguage = "zh-Hans"
    @AppStorage("defaultTargetLanguage") private var defaultTargetLanguage = "en"
    @AppStorage("translationEngine")     private var translationEngine     = "apple"

    @State private var selectedImage:   UIImage?
    @State private var detectedText:    String = ""
    @State private var translatedText:  String = ""
    @State private var isTranslating:   Bool   = false
    @State private var showImagePicker: Bool   = false

    @State private var translationConfig:  TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?

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
                            imageCard(img)
                        } else {
                            emptyPlaceholder
                        }
                        if !translatedText.isEmpty {
                            translationResultCard
                        }
                        if !detectedText.isEmpty {
                            translateButton
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("识图")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                setupTranslationConfig()
                applyTransparentNavBar()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            LiveImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, _ in
            detectedText = ""
            translatedText = ""
        }
        .translationTask(translationConfig) { session in
            translationSession = session
        }
    }

    // MARK: - Picker button

    private var pickerButton: some View {
        Button {
            showImagePicker = true
        } label: {
            Label("从相册选择", systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Image card

    private func imageCard(_ image: UIImage) -> some View {
        LiveTextImageView(image: image) { text in
            detectedText = text
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44))
                .foregroundColor(accentBlue.opacity(0.45))
            Text("从相册选取图片，长按可选取文字")
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

    private func translateAll() async {
        guard !detectedText.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }

        if translationEngine == "deepseek" {
            let result = await DeepSeekService.shared.translateText(
                text: detectedText,
                from: displayName(defaultSourceLanguage),
                to:   displayName(defaultTargetLanguage)
            )
            translatedText = result
        } else {
            guard let session = translationSession else { return }
            do {
                let response = try await session.translate(detectedText)
                translatedText = response.targetText
            } catch {
                print("❌ Live Text翻译错误: \(error.localizedDescription)")
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

// MARK: - Live Text UIImageView wrapper

private struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    var onAnalysisComplete: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true

        if ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            iv.addInteraction(interaction)
            context.coordinator.interaction = interaction
        }

        return iv
    }

    func updateUIView(_ iv: UIImageView, context: Context) {
        guard context.coordinator.lastImage !== image else { return }
        context.coordinator.lastImage = image
        iv.image = image

        guard ImageAnalyzer.isSupported,
              let interaction = context.coordinator.interaction else { return }
        interaction.analysis = nil

        Task {
            let analyzer = ImageAnalyzer()
            let config = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            if let analysis = try? await analyzer.analyze(image, configuration: config) {
                await MainActor.run {
                    interaction.analysis = analysis
                    interaction.preferredInteractionTypes = .textSelection
                    onAnalysisComplete(analysis.transcript)
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 48
        guard image.size.width > 0 else { return CGSize(width: w, height: w) }
        return CGSize(width: w, height: w * image.size.height / image.size.width)
    }

    class Coordinator {
        var interaction: ImageAnalysisInteraction?
        var lastImage: UIImage?
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

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
