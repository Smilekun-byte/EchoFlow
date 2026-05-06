import Foundation
import Speech
import AVFoundation
import Combine

class TranscriptionService: ObservableObject {
    
    // 明确指定 Locale，防止跟随系统语言变动导致不可控
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var transcribedText: String = ""
    
    func setLanguage(_ language: SupportedLanguage) {
        stopTranscription()
        switch language {
        case .chinese:
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        case .english:
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        case .japanese:
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        }
        print("🌐 已切换语言至: \(language.displayName)")
    }
    // MARK: - 请求权限
    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    // MARK: - 开始识别
    func startTranscription() {
        // 安全检查：如果识别器不可用（比如不支持该语言或无网络）
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ 识别器不可用")
            return
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // 建议：增加真机判断，部分老旧机型不支持 On-Device 识别
        if #available(iOS 13.0, *), recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if let error = error {
                // 如果是正常的结束（用户手动停止），不需要报错
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
        // 关键点：如果 request 已经被置 nil 却还在往里塞数据，会崩溃
        recognitionRequest?.append(buffer)
    }
    
    // MARK: - 停止识别
    func stopTranscription() {
        recognitionRequest?.endAudio() // 优雅结束
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        // 注意：如果你希望保留屏幕上的文字，不要在这里清空 transcribedText
    }
}
