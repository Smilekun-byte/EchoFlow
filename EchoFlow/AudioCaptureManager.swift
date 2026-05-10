//
//  AudioRecorder.swift
//  共鳴
//
//  Created by 漆咚 on 2026/04/04.
//
import AVFoundation
import Combine
import CoreHaptics

class AudioCaptureManager: ObservableObject {

    private let audioEngine    = AVAudioEngine()
    private var chunkTimer:    Timer?
    private var accumulatedBuffer: [Float] = []
    private let bufferLock     = NSLock()

    var onChunkReady:  (([Float], Double) -> Void)?
    var onBufferReady: ((AVAudioPCMBuffer) -> Void)?

    // 对外暴露的采样率始终是转换后的 16000 Hz
    private(set) var actualSampleRate: Double = 16000
    private static let targetSampleRate: Double = 16000

    @Published var currentRMS: Float = 0.0

    private var hapticEngine:    CHHapticEngine?
    private var lastHapticTime:  TimeInterval = 0

    private let chunkInterval: TimeInterval = 0.5

    // MARK: - Init

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        hapticEngine?.stoppedHandler = { [weak self] _ in self?.hapticEngine = nil }
        hapticEngine?.resetHandler   = { [weak self] in
            self?.hapticEngine = try? CHHapticEngine()
            try? self?.hapticEngine?.start()
        }
        try? hapticEngine?.start()
    }

    // MARK: - 启动录音

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode     = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)   // 永远用硬件原生格式

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   AudioCaptureManager.targetSampleRate,
            channels:     1,
            interleaved:  false
        ) else {
            throw makeError("无法创建目标音频格式")
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw makeError("无法创建音频转换器 (\(Int(hardwareFormat.sampleRate)) Hz → 16000 Hz)")
        }

        print("🎙️ 硬件: \(Int(hardwareFormat.sampleRate)) Hz \(hardwareFormat.channelCount)ch → 重采样至 16000 Hz")

        // tap 使用硬件原生格式，绝不自定义格式
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer,
                                hardwareFormat: hardwareFormat,
                                targetFormat:   targetFormat,
                                converter:      converter)
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
        bufferLock.lock(); accumulatedBuffer.removeAll(); bufferLock.unlock()
        print("🛑 录音已停止")
    }

    // MARK: - 触感

    func playRippleHaptic(intensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player  = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: 0)
    }

    func suspendHaptics() { hapticEngine?.stop() }
    func resumeHaptics()  { try? hapticEngine?.start() }

    // MARK: - 核心处理（后台线程）

    private func processBuffer(
        _ buffer:        AVAudioPCMBuffer,
        hardwareFormat:  AVAudioFormat,
        targetFormat:    AVAudioFormat,
        converter:       AVAudioConverter
    ) {
        // 1. 应用增益 + 计算 RMS（直接在硬件 buffer 上操作）
        let savedGain = UserDefaults.standard.double(forKey: "microphoneGain")
        let gain      = Float(savedGain < 1.0 ? 2.0 : savedGain)
        var sumSquares: Float = 0

        if let ch = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            for i in 0..<frames {
                ch[i] = max(-1.0, min(1.0, ch[i] * gain))
                sumSquares += ch[i] * ch[i]
            }
            let normalized = min(sqrt(sumSquares / Float(frames)) * 20, 1.0)
            let now = Date().timeIntervalSince1970
            if normalized > 0.1, now - lastHapticTime > 0.1 {
                lastHapticTime = now
                playRippleHaptic(intensity: normalized)
            }
            DispatchQueue.main.async { self.currentRMS = normalized }
        }

        // 2. 软件重采样：硬件格式 → 16000 Hz Float32
        let ratio            = AudioCaptureManager.targetSampleRate / hardwareFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: outputFrameCount) else { return }

        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed { outStatus.pointee = .noDataNow; return nil }
            inputConsumed         = true
            outStatus.pointee     = .haveData
            return buffer
        }

        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)
        if let err = convError {
            print("⚠️ 重采样失败: \(err.localizedDescription)")
            return
        }

        onBufferReady?(outputBuffer)
        appendBuffer(outputBuffer)
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        bufferLock.lock(); accumulatedBuffer.append(contentsOf: samples); bufferLock.unlock()
    }

    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            self?.flushChunk()
        }
    }

    private func flushChunk() {
        bufferLock.lock(); let chunk = accumulatedBuffer; accumulatedBuffer.removeAll(); bufferLock.unlock()
        guard !chunk.isEmpty else { return }
        let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
        print("📦 Chunk | 采样点数: \(chunk.count) | RMS: \(String(format: "%.4f", rms))")
        onChunkReady?(chunk, Double(chunk.count))
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "AudioCaptureManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
