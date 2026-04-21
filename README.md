# EchoFlow
iOS audio transcription and translation app
EchoFlow

iOS 实时语音转录 App，面向留学生场景开发

目前进度
✅ 已完成

实时录音（AVAudioEngine）
音频数据流（每0.5秒输出一个chunk）
语音识别转文字（Apple Speech Framework）

🚧 开发中

翻译模块（Apple Translation Framework）

📋 计划中

多语言支持（中/英/日切换）
流媒体接入
UI 优化
Whisper 高精度识别接入

技术栈
模块技术录音AVAudioEngine语音识别Apple Speech Framework翻译Apple Translation Framework（计划）UISwiftUI
项目结构
EchoFlow/
├── Audio/
│   └── AudioCaptureManager.swift
├── Transcription/
│   └── TranscriptionService.swift
├── Translation/
│   └── TranslationService.swift
└── Views/
    └── ContentView.swift
