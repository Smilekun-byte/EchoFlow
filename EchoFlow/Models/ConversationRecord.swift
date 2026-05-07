import Foundation
import SwiftData

@Model
final class ConversationRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var sourceLanguage: String = ""
    var targetLanguage: String = ""
    var originalText: String = ""
    var translatedText: String = ""
    var title: String = ""
    var keywords: [String] = []
    var isFavorite: Bool = false
    var folder: Folder?

    init(sourceLanguage: String, targetLanguage: String, originalText: String, translatedText: String) {
        self.id = UUID()
        self.date = Date()
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.originalText = originalText
        self.translatedText = translatedText
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        self.title = f.string(from: Date())
        self.keywords = []
        self.isFavorite = false
    }
}
