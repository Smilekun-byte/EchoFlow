import SwiftUI

struct ContentView: View {
    
    @StateObject private var audioManager = AudioCaptureManager()
    @State private var isRecording = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 32) {
            Text("音频数据流测试")
                .font(.title2).bold()
            
            Circle()
                .fill(isRecording ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
            
            Button(isRecording ? "停止录音" : "开始录音") {
                toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .blue)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            Text("查看 Xcode Console 观察 chunk 输出")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func toggleRecording() {
        if isRecording {
            audioManager.stopRecording()
            isRecording = false
        } else {
            do {
                try audioManager.startRecording()
                isRecording = true
                errorMessage = nil
            } catch {
                errorMessage = "启动失败: \(error.localizedDescription)"
            }
        }
    }
}
