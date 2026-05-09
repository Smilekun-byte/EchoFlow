//
//  AudioRecorder.swift
//  EchoFlow
//
//  Created by 漆咚 on 2026/04/04.
//
import AVFoundation
import Combine
import CoreHaptics

class AudioCaptureManager: ObservableObject {

    private let audioEngine = AVAudioEngine()
    private var chunkTimer: Timer?
    private var accumulatedBuffer: [Float] = []
    private let bufferLock = NSLock()

    var onChunkReady: (([Float], Double) -> Void)?
    var onBufferReady: ((AVAudioPCMBuffer) -> Void)?
    private(set) var actualSampleRate: Double = 48000

    @Published var currentRMS: Float = 0.0

    private var hapticEngine: CHHapticEngine?
    private var lastHapticTime: TimeInterval = 0

    private let chunkInterval: TimeInterval = 0.5

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        hapticEngine?.stoppedHandler = { [weak self] _ in
            self?.hapticEngine = nil
        }
        hapticEngine?.resetHandler = { [weak self] in
            self?.hapticEngine = try? CHHapticEngine()
            try? self?.hapticEngine?.start()
        }
        try? hapticEngine?.start()
    }

    // MARK: - 启动录音
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        actualSampleRate = format.sampleRate

        print("🎙️ 采样率: \(format.sampleRate) Hz, 声道数: \(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let savedGain = UserDefaults.standard.double(forKey: "microphoneGain")
            let gain = Float(savedGain < 1.0 ? 2.0 : savedGain)
            var sumSquares: Float = 0
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                for i in 0..<frames {
                    channelData[i] = max(-1.0, min(1.0, channelData[i] * gain))
                    sumSquares += channelData[i] * channelData[i]
                }
                let rms = sqrt(sumSquares / Float(frames))
                let normalized = min(rms * 20, 1.0)

                let now = Date().timeIntervalSince1970
                if normalized > 0.1, let self, now - self.lastHapticTime > 0.1 {
                    self.lastHapticTime = now
                    self.playRippleHaptic(intensity: normalized)
                }

                DispatchQueue.main.async { self?.currentRMS = normalized }
            }
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

    // MARK: - 触感

    func playRippleHaptic(intensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        let event = CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [intensityParam, sharpnessParam],
                                  relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: 0)
    }

    func suspendHaptics() {
        hapticEngine?.stop()
    }

    func resumeHaptics() {
        try? hapticEngine?.start()
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
