import Foundation
import Speech
import AVFoundation
import Combine

class TranscriptionService: ObservableObject {

    // 三种语言的 recognizer 预先创建，切换语言时无需重建
    private let zhRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let jaRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let enRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var currentLanguage: SupportedLanguage = .chinese
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?

    @Published var transcribedText: String = ""

    // MARK: - 语言切换

    private func currentRecognizer() -> SFSpeechRecognizer? {
        switch currentLanguage {
        case .chinese:  return zhRecognizer
        case .japanese: return jaRecognizer
        case .english:  return enRecognizer
        }
    }

    func setLanguage(_ language: SupportedLanguage) {
        stopTranscription()
        currentLanguage = language
        print("🌐 已切换语言至: \(language.displayName)")
    }

    // MARK: - 权限

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    // MARK: - 开始识别

    func startTranscription() {
        guard let recognizer = currentRecognizer(), recognizer.isAvailable else {
            print("❌ 识别器不可用")
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // 允许联网，标点更准

        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if result.isFinal {
                        // 最终结果：补充标点后更新
                        self.transcribedText = self.applyPunctuation(text)
                    } else {
                        // 中间结果：直接显示，不加标点
                        self.transcribedText = text
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    print("ℹ️ 识别正常结束")
                } else {
                    print("❌ 识别错误: \(error.localizedDescription)")
                }
                self.stopTranscription()
            }
        }
    }

    // MARK: - 接收 Buffer

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    // MARK: - 停止识别

    func stopTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - 标点处理

    private func applyPunctuation(_ text: String) -> String {
        switch currentLanguage {
        case .chinese:  return addChinesePunctuation(text)
        case .japanese: return text   // Apple 日语识别自带全角标点
        case .english:  return text   // Apple 英语识别自带标点
        }
    }

    private func addChinesePunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let endings: Set<Character> = ["。", "！", "？", "…", ".", "!", "?"]
        if let last = text.last, !endings.contains(last) {
            return text + "。"
        }
        return text
    }
}
