//
//  Untitled.swift
//  共鳴
//
//  Created by 漆咚 on 2026/04/24.
//
import Foundation
import AVFoundation
import Combine

class DeepgramService: ObservableObject {

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?          // 必须持有 session，否则 task 会被系统回收

    // 优先使用设置页面保存的 key，否则回落到 xcconfig
    private var apiKey: String {
        let stored = UserDefaults.standard.string(forKey: "deepgramAPIKey") ?? ""
        return stored.isEmpty ? Secrets.deepgramAPIKey : stored
    }

    @Published var transcribedText: String = ""
    @Published var isConnected: Bool = false
    
    // MARK: - 连接 Deepgram
    func connect(sampleRate: Double = 48000) {
        let urlString = "wss://api.deepgram.com/v1/listen?" +
            "model=nova-2" +
            "&encoding=linear16" +
            "&sample_rate=\(Int(sampleRate))" +
            "&channels=1" +
            "&language=zh-CN" +
            "&punctuate=true" +
            "&smart_format=true" +
            "&interim_results=true"

        guard let url = URL(string: urlString) else {
            print("❌ Deepgram URL 无效")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()
        // 立即允许发送音频，Deepgram 要求连接后马上收到数据否则会超时关闭
        isConnected = true
        print("🔌 Deepgram WebSocket 正在连接（\(Int(sampleRate)) Hz）...")
        receiveMessage()
    }
    
    // MARK: - 发送音频数据
    func sendAudio(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else {
            // 诊断：每隔一段时间提示 isConnected 为 false
            if Int.random(in: 0..<30) == 0 {
                print("⏳ sendAudio 跳过：isConnected=false，等待握手...")
            }
            return
        }
        guard let channelData = buffer.floatChannelData?[0] else { return }

        // 增益已在 AudioCaptureManager 的 tap 中处理，这里只做 float→int16 转换
        let frameCount = Int(buffer.frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))
            int16Samples[i] = Int16(sample * 32767)
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameCount))

        if Int.random(in: 0..<20) == 0 {
            print("🎤 Deepgram 发送 | 帧数: \(frameCount) | RMS: \(String(format: "%.4f", rms))")
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
        print("📨 收到消息: \(text.prefix(200))")  // 诊断：打印原始 JSON

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ JSON 解析失败")
            return
        }

        guard let channel = json["channel"] as? [String: Any],
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
        session?.invalidateAndCancel()
        session = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.transcribedText = ""
        }
        print("🛑 Deepgram 已断开")
    }
}
