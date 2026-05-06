import Foundation
import Translation

class AppleTranslationService: TranslationServiceProtocol {
    
    func translate(
        text: String,
        direction: TranslationDirection
    ) async throws -> String {
        
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: direction.source.rawValue),
            target: Locale.Language(identifier: direction.target.rawValue)
        )
        
        let response = try await session.translate(text)
        return response.targetText
    }
}
