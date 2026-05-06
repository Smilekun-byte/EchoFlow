import Foundation
// 翻译方向改成 源语言+目标语言
struct TranslationDirection {
    let source: SupportedLanguage
    let target: SupportedLanguage
}

// 接口不变
protocol TranslationServiceProtocol {
    func translate(
        text: String,
        direction: TranslationDirection
    ) async throws -> String
}
