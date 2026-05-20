// TextAnalysisSheet.swift
//
// 智能分流：
//   短文本（≤2词 / ≤6字）→ Apple 本地词典（UIReferenceLibraryViewController，0 流量、离线可用）
//   长文本（句子/段落）   → DeepSeek AI 深度解析（含义 + 翻译 + 关键信息）

import SwiftUI
import UIKit

// MARK: - 1. 分流器 ──────────────────────────────────────────────────────────

/// 根据选中文本的长度和结构决定去向。
struct TextActionEvaluator {

    enum Destination: Equatable {
        case nativeLookUp   // Apple 本地词典
        case deepSeekAI     // DeepSeek AI 分析
        case ignore         // 空文本，不处理
    }

    static func evaluate(_ text: String) -> Destination {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .ignore }

        // 英文按空格切词，中文按字符数
        let wordCount = cleaned.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.count
        let charCount = cleaned.count

        // ≤2 个英文词 且 ≤6 个字符 → 视为单词/短语，走本地词典
        return (wordCount <= 2 && charCount <= 6) ? .nativeLookUp : .deepSeekAI
    }
}

// MARK: - 2. 分析半屏 ─────────────────────────────────────────────────────────

struct TextAnalysisSheet: View {

    let initialText: String

    @State private var inputText:    String = ""
    @State private var aiResult:     String = ""
    @State private var isAnalyzing:  Bool   = false
    @State private var lookUpTerm:   String?        // 非 nil 时弹出本地词典

    @Environment(\.dismiss) private var dismiss

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 路由提示 chip ──────────────────────────────────────
                    routingHint

                    // ── 可编辑文本框：用户可裁剪后再分析 ─────────────────
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("粘贴或输入要分析的文本…")
                                .foregroundStyle(.secondary.opacity(0.6))
                                .font(.body)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .font(.body)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )

                    // ── 分析按钮 ─────────────────────────────────────────
                    Button { analyze() } label: {
                        HStack(spacing: 8) {
                            if isAnalyzing {
                                ProgressView().scaleEffect(0.8).tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isAnalyzing ? "分析中…" : "开始分析")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canAnalyze ? accentBlue : accentBlue.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!canAnalyze)
                    .animation(.easeInOut(duration: 0.15), value: canAnalyze)

                    // ── AI 结果卡片 ──────────────────────────────────────
                    if isAnalyzing || !aiResult.isEmpty {
                        aiResultCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: aiResult.isEmpty)
            }
            .navigationTitle("文本分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { inputText = initialText }
        // 原生词典 sheet
        .sheet(item: $lookUpTerm) { term in
            ReferenceLibraryController(term: term)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .ignoresSafeArea()
        }
    }

    // ── 路由方向提示（随输入内容动态变化）────────────────────────────────────
    private var routingHint: some View {
        let dest = TextActionEvaluator.evaluate(inputText)
        let isShort = (dest == .nativeLookUp || dest == .ignore)
        return HStack(spacing: 6) {
            Image(systemName: isShort ? "character.book.closed.fill" : "sparkles")
                .font(.caption2.weight(.semibold))
            Text(isShort ? "短文本  →  Apple 本地词典" : "长文本  →  AI 深度分析")
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(isShort ? .secondary : accentBlue)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((isShort ? Color.secondary : accentBlue).opacity(0.1))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: isShort)
    }

    private var canAnalyze: Bool {
        !isAnalyzing && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // ── AI 结果卡片 ──────────────────────────────────────────────────────────
    private var aiResultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(accentBlue)
                    .font(.caption2.weight(.semibold))
                Text("AI 分析结果")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if isAnalyzing {
                    ProgressView().scaleEffect(0.75)
                }
            }

            Text(isAnalyzing && aiResult.isEmpty ? "正在分析中，请稍候…" : aiResult)
                .font(.body)
                .foregroundColor(isAnalyzing && aiResult.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - 分析逻辑

    private func analyze() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch TextActionEvaluator.evaluate(text) {
        case .nativeLookUp:
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: text) {
                lookUpTerm = text
            } else {
                // 本地词典无结果时自动降级到 DeepSeek
                callDeepSeek(text)
            }
        case .deepSeekAI:
            callDeepSeek(text)
        case .ignore:
            break
        }
    }

    private func callDeepSeek(_ text: String) {
        isAnalyzing = true
        aiResult    = ""
        Task {
            let result = await DeepSeekService.shared.complete(
                system: """
                你是一个专业的语言与内容分析助手。根据用户提供的文本，视内容性质提供：
                1. 核心含义或词义解释（中文，简洁）
                2. 翻译（若为外文）
                3. 关键信息提取（若为长段落）
                用中文回复，简洁有力，不超过 200 字。
                """,
                user: text
            )
            await MainActor.run {
                aiResult    = result
                isAnalyzing = false
            }
        }
    }
}

// MARK: - 3. 让 String 用于 .sheet(item:) ──────────────────────────────────────

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - 4. UIReferenceLibraryViewController 包装 ─────────────────────────────

/// 将 Apple 官方本地词典卡片包装为 SwiftUI View。
struct ReferenceLibraryController: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ vc: UIReferenceLibraryViewController, context: Context) {}
}
