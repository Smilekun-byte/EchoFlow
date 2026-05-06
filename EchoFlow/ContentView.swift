import SwiftUI

struct ContentView: View {
    
    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var appleTranscription = TranscriptionService()
    @StateObject private var deepgramService = DeepgramService()
    
    @State private var useDeepgram: Bool = true
    @State private var isRecording = false
    @State private var translatedText: String = ""
    @State private var sourceLanguage: SupportedLanguage = .chinese
    @State private var targetLanguage: SupportedLanguage = .english
    @State private var errorMessage: String?
    
    // 当前显示的转录文字
    var currentTranscript: String {
        useDeepgram ? deepgramService.transcribedText : appleTranscription.transcribedText
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("EchoFlow")
                .font(.title).bold()
            
            // 引擎切换
            Picker("引擎", selection: $useDeepgram) {
                Text("Deepgram").tag(true)
                Text("Apple").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // 语言选择
            HStack(spacing: 12) {
                Menu {
                    ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                        Button(lang.displayName) {
                            sourceLanguage = lang
                            appleTranscription.setLanguage(lang)
                        }
                    }
                } label: {
                    HStack {
                        Text(sourceLanguage.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                
                Menu {
                    ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                        Button(lang.displayName) {
                            targetLanguage = lang
                        }
                    }
                } label: {
                    HStack {
                        Text(targetLanguage.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
                }
            }
            
            // 原文
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("原文").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    // 显示当前用哪个引擎
                    Text(useDeepgram ? "Deepgram" : "Apple")
                        .font(.caption2)
                        .foregroundColor(useDeepgram ? .green : .blue)
                }
                ScrollView {
                    Text(currentTranscript.isEmpty ? "开始说话..." : currentTranscript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // 译文
            VStack(alignment: .leading, spacing: 4) {
                Text("译文").font(.caption).foregroundColor(.secondary)
                ScrollView {
                    Text(translatedText.isEmpty ? "翻译结果..." : translatedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // 录音按钮
            Circle()
                .fill(isRecording ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                )
                .onTapGesture {
                    toggleRecording()
                }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .onAppear {
            print("🟢 VIEW APPEARED")
            appleTranscription.requestPermission { granted in
                print(granted ? "✅ 语音识别权限已获取" : "❌ 权限被拒绝")
            }
            audioManager.onBufferReady = { buffer in
                if self.useDeepgram {
                    self.deepgramService.sendAudio(buffer)
                } else {
                    self.appleTranscription.appendBuffer(buffer)
                }
            }
        }
        .onChange(of: currentTranscript) { _, newText in
            guard !newText.isEmpty else { return }
            Task {
                do {
                    translatedText = try await AppleTranslationService().translate(
                        text: newText,
                        direction: TranslationDirection(
                            source: sourceLanguage,
                            target: targetLanguage
                        )
                    )
                } catch {
                    print("❌ 翻译错误: \(error.localizedDescription)")
                }
            }
        }
    }
    private func toggleRecording() {
        if isRecording {
            audioManager.stopRecording()
            if useDeepgram {
                deepgramService.disconnect()
            } else {
                appleTranscription.stopTranscription()
            }
            isRecording = false
        } else {
            do {
                // 先启动录音，拿到设备真实采样率后再连接 Deepgram
                try audioManager.startRecording()
                if useDeepgram {
                    deepgramService.connect(sampleRate: audioManager.actualSampleRate)
                } else {
                    appleTranscription.startTranscription()
                }
                isRecording = true
                errorMessage = nil
            } catch {
                errorMessage = "启动失败: \(error.localizedDescription)"
            }
        }
    }
}
