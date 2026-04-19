//
//  AudioRecorder.swift
//  EchoFlow
//
//  Created by 漆咚 on 2026/04/04.
//
import AVFoundation
import Combine

class AudioCaptureManager: ObservableObject {
    
    private let audioEngine = AVAudioEngine()
    private var chunkTimer: Timer?
    private var accumulatedBuffer: [Float] = []
    private let bufferLock = NSLock()
    
    // 每 0.5 秒触发一次，外部可订阅
    var onChunkReady: (([Float], Double) -> Void)?
    
    private let chunkInterval: TimeInterval = 0.5
    
    // MARK: - 启动录音
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ 采样率: \(format.sampleRate) Hz, 声道数: \(format.channelCount)")
        
        // 安装 tap，每次硬件回调都往 buffer 里追加数据
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.appendBuffer(buffer)
        }
        
        try audioEngine.start()
        print("✅ AudioEngine 已启动")
        
        // 启动定时器，每 0.5 秒切一次 chunk
        startChunkTimer()
    }
    
    // MARK: - 停止录音
    func stopRecording() {
        chunkTimer?.invalidate()
        chunkTimer = nil
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        try? AVAudioSession.sharedInstance().setActive(false)
        
        bufferLock.lock()
        accumulatedBuffer.removeAll()
        bufferLock.unlock()
        
        print("🛑 录音已停止")
    }
    
    // MARK: - Private
    
    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        bufferLock.lock()
        accumulatedBuffer.append(contentsOf: samples)
        bufferLock.unlock()
    }
    
    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            self?.flushChunk()
        }
    }
    
    private func flushChunk() {
        bufferLock.lock()
        let chunk = accumulatedBuffer
        accumulatedBuffer.removeAll()
        bufferLock.unlock()
        
        guard !chunk.isEmpty else { return }
        
        // 计算一个简单的 RMS 音量，验证数据是否正常
        let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
        
        print("📦 Chunk | 采样点数: \(chunk.count) | RMS音量: \(String(format: "%.4f", rms))")
        
        // 回调给外部（后续接转文字模块）
        onChunkReady?(chunk, Double(chunk.count))
    }
}
