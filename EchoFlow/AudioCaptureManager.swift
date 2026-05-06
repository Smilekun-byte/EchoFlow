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

    var onChunkReady: (([Float], Double) -> Void)?
    var onBufferReady: ((AVAudioPCMBuffer) -> Void)?
    private(set) var actualSampleRate: Double = 48000

    private let chunkInterval: TimeInterval = 0.5

    // MARK: - 启动录音
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        actualSampleRate = format.sampleRate

        print("🎙️ 采样率: \(format.sampleRate) Hz, 声道数: \(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.appendBuffer(buffer)
            self?.onBufferReady?(buffer)
        }

        try audioEngine.start()
        print("✅ AudioEngine 已启动")

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

        let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
        print("📦 Chunk | 采样点数: \(chunk.count) | RMS音量: \(String(format: "%.4f", rms))")

        onChunkReady?(chunk, Double(chunk.count))
    }
}
