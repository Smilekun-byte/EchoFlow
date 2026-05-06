//
//  Untitled.swift
//  EchoFlow
//
//  Created by 漆咚 on 2026/04/24.
//
import Foundation
import AVFoundation
import Combine

class DeepgramService: ObservableObject {
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiKey = Secrets.deepgramAPIKey  // ← 从 Secrets 读取
    
    @Published var transcribedText: String = ""
    @Published var isConnected: Bool = false
    
    // MARK: - 连接 Deepgram
    func connect(sampleRate: Double = 48000) {
        let urlString = "wss://api.deepgram.com/v1/listen?" +
            "encoding=linear16" +
            "&sample_rate=\(Int(sampleRate))" +
            "&channels=1" +
            "&language=zh" +
            "&punctuate=true" +
            "&interim_results=true"

        guard let url = URL(string: urlString) else {
            print("❌ Deepgram URL 无效")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        // isConnected 在收到第一条消息后才设为 true，避免握手失败时误判
        print("🔌 Deepgram WebSocket 正在连接（\(Int(sampleRate)) Hz）...")
        receiveMessage()
    }
    
    // MARK: - 发送音频数据
    func sendAudio(_ buffer: AVAudioPCMBuffer) {
        guard isConnected,
              let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameCount = Int(buffer.frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        
        // 计算 RMS 音量用于调试
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))
            int16Samples[i] = Int16(sample * 32767)
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        
        // 每 20 个 buffer 打印一次音量（避免刷屏）
        if Int.random(in: 0..<20) == 0 {
            print("🎤 Deepgram 发送 | 帧数: \(frameCount) | RMS音量: \(String(format: "%.4f", rms))")
        }
        
        let data = int16Samples.withUnsafeBytes { Data($0) }
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("❌ 发送音频失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 接收识别结果
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                // 收到第一条消息才确认连接成功
                if !self.isConnected {
                    DispatchQueue.main.async { self.isConnected = true }
                    print("✅ Deepgram 连接已确认")
                }
                if case .string(let text) = message {
                    self.handleResponse(text)
                }
                self.receiveMessage()

            case .failure(let error):
                print("❌ 接收失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }
    
    // MARK: - 解析返回 JSON
    private func handleResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String,
              !transcript.isEmpty else { return }
        
        let isFinal = json["is_final"] as? Bool ?? false
        
        DispatchQueue.main.async {
            self.transcribedText = transcript
            print("\(isFinal ? "📝 最终" : "⏳ 中间") \(transcript)")
        }
    }
    
    // MARK: - 断开连接
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
        print("🛑 Deepgram 已断开")
    }
}
