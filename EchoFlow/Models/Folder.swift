import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "📁"
    var colorHex: String = "#3B82F6"
    @Relationship(deleteRule: .nullify, inverse: \ConversationRecord.folder)
    var records: [ConversationRecord] = []

    init(name: String, icon: String, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.records = []
    }
}
