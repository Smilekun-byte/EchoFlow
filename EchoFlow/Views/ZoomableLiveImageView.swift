// ZoomableLiveImageView.swift
//
// 功能：
//   1. 从相册或相机选取图片
//   2. 双指捏合缩放 + 单指平移（UIScrollView 原生缩放，等价于 MagnificationGesture）
//   3. 双击在 1× 和 2.5× 之间切换（同 Apple 照片 App）
//   4. Live Text — 长按可选中 / 复制 / 翻译图片中的文字
//
// 要求：iOS 16+，VisionKit，SwiftUI

import SwiftUI
import UIKit
import Vision
import VisionKit

// MARK: - 1. 入口页面（选图 + 展示） ──────────────────────────────────────────

/// 完整的图片查看页：提供相册 / 相机选图入口，图片选中后显示可缩放的 Live Text 视图。
struct ImageLiveTextViewer: View {

    @State private var image:      UIImage?
    @State private var showPicker  = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    // 核心组件：可缩放 + Live Text
                    ZoomableLiveImageView(image: image)
                } else {
                    emptyState
                }
            }
            .navigationTitle("图片查看器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { pickerMenu }
        }
        .sheet(isPresented: $showPicker) {
            // UIImagePickerController 的 SwiftUI 包装
            ImagePickerController(sourceType: sourceType, image: $image)
                .ignoresSafeArea()
        }
    }

    // ── 尚未选图时的占位视图 ─────────────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("选择或拍摄图片\n即可使用 Live Text 识别文字")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    pickerButton("相机", icon: "camera", source: .camera)
                }
                pickerButton("相册", icon: "photo.on.rectangle", source: .photoLibrary)
            }
        }
        .padding()
    }

    private func pickerButton(_ title: String,
                              icon: String,
                              source: UIImagePickerController.SourceType) -> some View {
        Button { pick(source) } label: {
            Label(title, systemImage: icon).frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
    }

    // ── 导航栏右侧菜单（已有图片时允许换图）────────────────────────────────
    @ToolbarContentBuilder
    private var pickerMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { pick(.camera) } label: {
                        Label("拍照", systemImage: "camera")
                    }
                }
                Button { pick(.photoLibrary) } label: {
                    Label("从相册选取", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "photo.badge.plus")
            }
        }
    }

    private func pick(_ source: UIImagePickerController.SourceType) {
        sourceType = source
        showPicker = true
    }
}

// MARK: - 2. ZoomableLiveImageView（核心可复用组件） ──────────────────────────

/// 可双指捏合缩放 + 单指平移 + Live Text 的图片视图。
/// 图片加载后自动运行 Vision OCR；识别到文字时右下角出现「AI 分析」按钮。
struct ZoomableLiveImageView: View {
    let image: UIImage

    @State private var recognizedText:    String = ""
    @State private var showAnalysisSheet: Bool   = false

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 核心：缩放 + Live Text
            // .ignoresSafeArea() 仅作用于 ScrollView 本身，让图片延伸到全屏（含 Tab Bar 后）
            // 外层 ZStack 保持 safe area 约束，按钮自然落在 Tab Bar 之上
            _ZoomScrollBridge(image: image) { text in
                recognizedText = text
            }
            .ignoresSafeArea()

            // 识别到文字后浮现的 AI 分析按钮
            if !recognizedText.isEmpty {
                Button { showAnalysisSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                        Text("AI 分析")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(accentBlue)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
                }
                .padding(16)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: recognizedText.isEmpty)
        .sheet(isPresented: $showAnalysisSheet) {
            TextAnalysisSheet(initialText: recognizedText)
        }
        // 换图时清空旧识别结果
        .onChange(of: ObjectIdentifier(image)) { _, _ in
            recognizedText = ""
        }
    }
}

// MARK: - 3. UIViewRepresentable 桥接层 ──────────────────────────────────────

private struct _ZoomScrollBridge: UIViewRepresentable {
    let image: UIImage
    var onTextExtracted: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> _LayoutScrollView {
        // ── UIScrollView：负责缩放（≈ MagnificationGesture）和平移 ─────────
        let scrollView = _LayoutScrollView()
        scrollView.delegate                       = context.coordinator
        scrollView.minimumZoomScale               = 1.0   // 最小 1×
        scrollView.maximumZoomScale               = 6.0   // 最大 6×
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator   = false
        scrollView.bouncesZoom                    = true  // 超限后弹回，同原生相册
        scrollView.backgroundColor                = .clear

        // ── UIImageView ──────────────────────────────────────────────────────
        let imageView                      = UIImageView(image: image)
        imageView.contentMode              = .scaleAspectFit
        imageView.isUserInteractionEnabled = true  // Live Text 必须开启
        imageView.clipsToBounds            = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // ── Live Text（VisionKit）───────────────────────────────────────────
        // ImageAnalyzer 仅在 A12 Bionic 及以上芯片的设备上可用
        if ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            // .automatic：自动开启文字选择、电话/网址检测、视觉搜索等所有功能
            interaction.preferredInteractionTypes = .automatic
            imageView.addInteraction(interaction)
            context.coordinator.interaction = interaction
            // 立即异步分析首张图片
            context.coordinator.analyzeForLiveText(image)
        }

        // ── 双击手势：1× ↔ 2.5× ──────────────────────────────────────────
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // ── layoutSubviews 回调：bounds 确定后才能正确布局 imageView ─────────
        // 直接在 updateUIView 里布局时 bounds 可能为 .zero，
        // 通过子类回调确保拿到真实尺寸再执行布局。
        let coordinator = context.coordinator
        scrollView.onLayoutSubviews = { [weak scrollView, weak coordinator] in
            guard let sv = scrollView, let c = coordinator else { return }
            c.layoutImageView(in: sv)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: _LayoutScrollView, context: Context) {
        // 每次 SwiftUI 重渲染时同步最新 closure（防止捕获过期状态）
        context.coordinator.onTextExtracted = onTextExtracted
        context.coordinator.update(image: image, in: scrollView)
    }
}

// MARK: - 4. Coordinator ─────────────────────────────────────────────────────

extension _ZoomScrollBridge {

    final class Coordinator: NSObject, UIScrollViewDelegate {

        weak var imageView:  UIImageView?
        var  interaction:      ImageAnalysisInteraction?
        var  onTextExtracted:  ((String) -> Void)?    // Vision OCR 完成后的回调
        private var analyzedImage: UIImage?           // 避免重复分析同一张图
        // 记录上一次布局时的 scroll view 尺寸；
        // 只有尺寸真正改变（首次出现 / 设备旋转）时才重新布局，
        // 缩放 / 滚动期间 layoutSubviews 也会触发但尺寸不变，直接跳过，
        // 避免覆盖用户正在进行的缩放操作。
        private var lastLayoutSize: CGSize = .zero

        // UIScrollViewDelegate：告诉 scroll view 哪个子视图参与缩放 ──────────
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        // 缩放过程中持续居中 ────────────────────────────────────────────────
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageView(in: scrollView)
        }

        // 图片更新入口（来自 updateUIView）─────────────────────────────────────
        func update(image: UIImage, in scrollView: UIScrollView) {
            guard let imageView else { return }
            if image !== imageView.image {
                // 换了新图：强制重新布局并重置缩放
                imageView.image = image
                lastLayoutSize = .zero          // 让 layoutImageView 无视尺寸缓存
                scrollView.setZoomScale(1.0, animated: false)
                analyzeForLiveText(image)
                layoutImageView(in: scrollView) // 新图必须立即布局
            }
            // 图片未变时不重复布局，防止干扰进行中的缩放
        }

        // 将 imageView 设置为 aspect-fit 尺寸并更新 contentSize。
        // 仅在 scroll view 尺寸发生变化时执行（首次 / 旋转），其余情况直接返回。
        func layoutImageView(in scrollView: UIScrollView) {
            guard let imageView,
                  let uiImage = imageView.image else { return }

            let scrollSize = scrollView.bounds.size
            guard scrollSize.width > 0, scrollSize.height > 0 else { return }
            // 尺寸没变则跳过，避免在缩放/滚动的 layoutSubviews 回调中重置 frame
            guard scrollSize != lastLayoutSize else { return }
            lastLayoutSize = scrollSize

            // 等比缩放，确保图片完整显示在 scroll view 内
            let scale = min(scrollSize.width  / uiImage.size.width,
                            scrollSize.height / uiImage.size.height)
            let fittedSize = CGSize(width:  uiImage.size.width  * scale,
                                    height: uiImage.size.height * scale)
            imageView.frame        = CGRect(origin: .zero, size: fittedSize)
            scrollView.contentSize = fittedSize
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            centerImageView(in: scrollView)
        }

        // 当内容尺寸小于 scroll view 时，用 contentInset 居中 ──────────────
        private func centerImageView(in scrollView: UIScrollView) {
            let sv = scrollView.bounds.size
            let cs = scrollView.contentSize
            scrollView.contentInset = UIEdgeInsets(
                top:    max(0, (sv.height - cs.height) / 2),
                left:   max(0, (sv.width  - cs.width)  / 2),
                bottom: max(0, (sv.height - cs.height) / 2),
                right:  max(0, (sv.width  - cs.width)  / 2)
            )
        }

        // 双击切换缩放：已放大 → 恢复 1×；未放大 → 以点击点为中心放大到 2.5× ──
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let tapPoint   = gesture.location(in: imageView)
                let targetScale = CGFloat(2.5)
                let w = scrollView.frame.width  / targetScale
                let h = scrollView.frame.height / targetScale
                let zoomRect = CGRect(x: tapPoint.x - w / 2,
                                      y: tapPoint.y - h / 2,
                                      width: w, height: h)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        // 串行分析：先让 ImageAnalyzer 跑完，确认有文字后再起 Vision OCR
        func analyzeForLiveText(_ image: UIImage) {
            guard image !== analyzedImage else { return }
            analyzedImage = image

            Task {
                // ── 阶段 1：ImageAnalyzer → Live Text 交互层 ──────────────────
                if ImageAnalyzer.isSupported, let interaction {
                    let analyzer = ImageAnalyzer()
                    let config   = ImageAnalyzer.Configuration([.text, .machineReadableCode])
                    do {
                        let analysis = try await analyzer.analyze(image, configuration: config)
                        await MainActor.run { interaction.analysis = analysis }
                        guard analysis.hasResults(for: .text) else { return }
                    } catch {
                        print("⚠️ Live Text 分析失败: \(error.localizedDescription)")
                    }
                }

                // ── 阶段 2：Vision OCR → 提取全文供 AI 分析 ──────────────────
                guard let cgImage = image.cgImage else { return }
                let request = VNRecognizeTextRequest { [weak self] req, _ in
                    guard let self else { return }
                    let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                    guard !obs.isEmpty else { return }

                    // Vision 坐标系：原点左下角，Y 向上。midY 越大越靠图片顶部。
                    // Step 1：按 midY 降序初排（上→下）
                    let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

                    // Step 2：将 midY 相近的 observation 合并为同一视觉行
                    var lines: [[VNRecognizedTextObservation]] = []
                    for o in sorted {
                        let h = max(o.boundingBox.height, 0.02)
                        if let last = lines.last?.first,
                           abs(last.boundingBox.midY - o.boundingBox.midY) < h * 0.7 {
                            lines[lines.count - 1].append(o)
                        } else {
                            lines.append([o])
                        }
                    }

                    // Step 3：同行内按 minX 从左到右排序
                    lines = lines.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }

                    // Step 4：合并行文字；根据内容判断 CJK / Latin 决定是否加空格
                    func isCJKDominant(_ s: String) -> Bool {
                        let cjk = s.unicodeScalars.filter {
                            ($0.value >= 0x4E00 && $0.value <= 0x9FFF) ||
                            ($0.value >= 0x3040 && $0.value <= 0x30FF) ||
                            ($0.value >= 0xAC00 && $0.value <= 0xD7AF)
                        }.count
                        return cjk > s.unicodeScalars.count / 3
                    }

                    struct Line { let text: String; let minY: CGFloat; let maxY: CGFloat }
                    let lineTexts: [Line] = lines.compactMap { group in
                        let parts = group.compactMap { $0.topCandidates(1).first?.string }
                                         .filter { !$0.isEmpty }
                        guard !parts.isEmpty else { return nil }
                        let joined = parts.joined()
                        let sep    = isCJKDominant(joined) ? "" : " "
                        let minY   = group.map { $0.boundingBox.minY }.min() ?? 0
                        let maxY   = group.map { $0.boundingBox.maxY }.max() ?? 0
                        return Line(text: parts.joined(separator: sep), minY: minY, maxY: maxY)
                    }

                    // Step 5：按行间距分段——间距 > 行高 2 倍才算新段落
                    var paragraphs: [[String]] = [[]]
                    var prevMinY: CGFloat = -1
                    var prevHeight: CGFloat = 0.04
                    for line in lineTexts {
                        let lineH = max(line.maxY - line.minY, 0.02)
                        if prevMinY >= 0 {
                            // prevMinY 是上一行底边；line.maxY 是本行顶边
                            let gap = prevMinY - line.maxY
                            if gap > prevHeight * 2.0 { paragraphs.append([]) }
                        }
                        paragraphs[paragraphs.count - 1].append(line.text)
                        prevMinY   = line.minY
                        prevHeight = lineH
                    }

                    let text = paragraphs
                        .compactMap { $0.isEmpty ? nil : $0.joined(separator: "\n") }
                        .joined(separator: "\n\n")
                    guard !text.isEmpty else { return }
                    DispatchQueue.main.async { self.onTextExtracted?(text) }
                }
                request.recognitionLevel       = .accurate
                request.usesLanguageCorrection = true
                request.minimumTextHeight      = 0.015   // 低于默认值，捕获小字号
                if #available(iOS 16, *) {
                    // 自动检测语言，混排文档识别更准确
                    request.automaticallyDetectsLanguage = true
                }
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "ja", "ko", "en-US"]

                DispatchQueue.global(qos: .userInitiated).async {
                    try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                }
            }
        }
    }
}

// MARK: - 5. _LayoutScrollView ────────────────────────────────────────────────

/// UIScrollView 的轻量子类，暴露 layoutSubviews 时机。
///
/// SwiftUI 的 UIViewRepresentable 在首次渲染时 bounds 可能为 .zero；
/// 通过拦截 layoutSubviews（bounds 变化后自动触发）来完成正确的首次布局，
/// 避免图片在 bounds 未知时出现尺寸异常。
private final class _LayoutScrollView: UIScrollView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

// MARK: - 6. ImagePickerController ────────────────────────────────────────────

/// 将 UIImagePickerController 包装为 SwiftUI View，支持相机和相册。
struct ImagePickerController: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker        = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject,
                              UIImagePickerControllerDelegate,
                              UINavigationControllerDelegate {
        let parent: ImagePickerController
        init(_ parent: ImagePickerController) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
