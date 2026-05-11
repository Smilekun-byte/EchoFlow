import SwiftUI
@preconcurrency import Vision

// MARK: - WordRegion

private struct WordRegion: Identifiable {
    let id   = UUID()
    let text: String
    let rect: CGRect   // Vision normalized coords: (0,0) = bottom-left
}

// MARK: - LiveTextView

struct LiveTextView: View {

    @AppStorage("defaultSourceLanguage") private var defaultSourceLanguage = "zh-Hans"

    @State private var selectedImage:   UIImage?
    @State private var wordRegions:     [WordRegion] = []
    @State private var isProcessing:    Bool   = false
    @State private var showPhotoPicker: Bool   = false
    @State private var showCamera:      Bool   = false

    @State private var scale:      CGFloat  = 1.0
    @State private var lastScale:  CGFloat  = 1.0
    @State private var offset:     CGSize   = .zero
    @State private var lastOffset: CGSize   = .zero

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
        .onChange(of: selectedImage) { _, image in
            scale = 1.0; lastScale = 1.0
            offset = .zero; lastOffset = .zero
            wordRegions = []
            guard let image else { return }
            Task { await analyzeImage(image) }
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

    // MARK: - Image card with bounding boxes + zoom/pan

    private func imageCard(_ image: UIImage) -> some View {
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
                                let r = convertRect(region.rect, in: geo.size)
                                Rectangle()
                                    .stroke(Color.blue, lineWidth: 1.5)
                                    .frame(width: r.width, height: r.height)
                                    .position(x: r.midX, y: r.midY)
                            }

                            if isProcessing {
                                Color.black.opacity(0.2)
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    scale = min(max(scale, 1.0), 5.0)
                                    lastScale = scale
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width:  lastOffset.width  + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                scale = 1.0;  lastScale  = 1.0
                                offset = .zero; lastOffset = .zero
                            }
                        }
                    }
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

    /// Vision 归一化坐标（左下原点）→ SwiftUI 视图坐标（左上原点）
    private func convertRect(_ r: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x:      r.minX * size.width,
            y:      (1 - r.maxY) * size.height,
            width:  r.width  * size.width,
            height: r.height * size.height
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44)).foregroundColor(accentBlue.opacity(0.45))
            Text("选取图片，识别文字区域")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1))
    }

    // MARK: - OCR（observation 级别，保留行/块坐标）

    private func analyzeImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        isProcessing = true
        defer { isProcessing = false }

        let languages = ocrLanguages

        let regions: [WordRegion] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let result = observations.map { obs in
                    WordRegion(
                        text: obs.topCandidates(1).first?.string ?? "",
                        rect: obs.boundingBox
                    )
                }
                continuation.resume(returning: result)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages   = languages

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do    { try handler.perform([request]) }
                catch { continuation.resume(returning: []) }
            }
        }

        wordRegions = regions
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
