import SwiftUI
import VisionKit

// MARK: - LiveTextView

struct LiveTextView: View {

    @State private var selectedImage:   UIImage?
    @State private var isAnalyzing:     Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera:      Bool = false

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
                        pickerRow
                        if let img = selectedImage {
                            imageCard(img)
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
        .sheet(isPresented: $showPhotoPicker) {
            LiveImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            LiveImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
    }

    // MARK: - Picker row

    private var pickerRow: some View {
        HStack(spacing: 12) {
            Button { showPhotoPicker = true } label: {
                Label("从相册选择", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button { showCamera = true } label: {
                Label("拍照", systemImage: "camera.fill")
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
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
        }
    }

    // MARK: - Image card（VisionKit Live Text）

    private func imageCard(_ image: UIImage) -> some View {
        let ratio = image.size.width / max(image.size.height, 1)
        return VStack(spacing: 8) {
            LiveTextImageView(image: image, isAnalyzing: $isAnalyzing)
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if isAnalyzing {
                        ZStack {
                            Color.black.opacity(0.25)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: deepBlue.opacity(0.1), radius: 12, x: 0, y: 4)

            Text("长按文字可选择、复制、翻译")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty placeholder

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44))
                .foregroundColor(accentBlue.opacity(0.45))
            Text("选取图片，识别文字区域")
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

// MARK: - VisionKit UIViewRepresentable

private struct LiveTextImageView: UIViewRepresentable {

    let image: UIImage
    @Binding var isAnalyzing: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        // 让 SwiftUI 的 layout 系统决定尺寸，不依赖 intrinsicContentSize
        iv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iv.setContentHuggingPriority(.defaultLow, for: .vertical)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let interaction = ImageAnalysisInteraction()
        iv.addInteraction(interaction)
        context.coordinator.interaction = interaction

        return iv
    }

    func updateUIView(_ iv: UIImageView, context: Context) {
        iv.image = image
        context.coordinator.analyzeIfNeeded(image: image, isAnalyzing: $isAnalyzing)
    }

    // MARK: Coordinator

    class Coordinator {
        let analyzer = ImageAnalyzer()
        var interaction: ImageAnalysisInteraction?
        private var lastAnalyzedImage: UIImage?

        func analyzeIfNeeded(image: UIImage, isAnalyzing: Binding<Bool>) {
            guard image !== lastAnalyzedImage else { return }
            lastAnalyzedImage = image
            interaction?.analysis = nil
            interaction?.preferredInteractionTypes = []

            Task { @MainActor in
                isAnalyzing.wrappedValue = true
                defer { isAnalyzing.wrappedValue = false }
                let config = ImageAnalyzer.Configuration([.text])
                do {
                    let analysis = try await analyzer.analyze(image, configuration: config)
                    interaction?.analysis = analysis
                    interaction?.preferredInteractionTypes = .textSelection
                } catch {
                    print("❌ Live Text 分析失败: \(error)")
                }
            }
        }
    }
}

// MARK: - Image Picker

private struct LiveImagePicker: UIViewControllerRepresentable {
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
