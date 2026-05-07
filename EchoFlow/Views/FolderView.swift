import SwiftUI
import SwiftData

// MARK: - Virtual Folder Type

enum VirtualFolderType: CaseIterable {
    case all, today, favorites

    var name: String {
        switch self {
        case .all:       return "全部"
        case .today:     return "今天"
        case .favorites: return "收藏"
        }
    }

    var icon: String {
        switch self {
        case .all:       return "📋"
        case .today:     return "📅"
        case .favorites: return "⭐️"
        }
    }

    var color: Color {
        switch self {
        case .all:       return Color(red: 0.231, green: 0.510, blue: 0.965)
        case .today:     return .green
        case .favorites: return .yellow
        }
    }
}

// MARK: - Folder View

struct FolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var allRecords: [ConversationRecord]

    @State private var showCreate = false
    @State private var selectedVirtual: VirtualFolderType?
    @State private var selectedFolder: Folder?

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let columns    = [GridItem(.flexible()), GridItem(.flexible())]
    @Environment(\.colorScheme) private var colorScheme

    private var background: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22),
                                      Color(red: 0.04, green: 0.07, blue: 0.14)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.910, green: 0.957, blue: 0.992),
                                      Color(red: 0.722, green: 0.831, blue: 0.929)],
                             startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        virtualGrid
                        if !folders.isEmpty { customGrid }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("文件夹")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .foregroundColor(accentBlue)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateFolderSheet { name, icon, colorHex in
                    let folder = Folder(name: name, icon: icon, colorHex: colorHex)
                    modelContext.insert(folder)
                }
            }
            // Navigation to virtual folder detail
            .navigationDestination(item: $selectedVirtual) { type in
                VirtualFolderDetailView(type: type)
            }
            // Navigation to custom folder detail
            .navigationDestination(item: $selectedFolder) { folder in
                CustomFolderDetailView(folder: folder)
            }
        }
    }

    // MARK: - Virtual Grid

    private var virtualGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(VirtualFolderType.allCases, id: \.self) { type in
                let count = virtualCount(type)
                Button { selectedVirtual = type } label: {
                    folderCard(icon: type.icon, name: type.name,
                               count: count, color: type.color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Custom Grid

    private var customGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我的文件夹")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(folders) { folder in
                    Button { selectedFolder = folder } label: {
                        folderCard(icon: folder.icon, name: folder.name,
                                   count: folder.records.count,
                                   color: Color(hex: folder.colorHex))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(folder)
                        } label: {
                            Label("删除文件夹", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Folder Card

    private func folderCard(icon: String, name: String, count: Int, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(icon)
                    .font(.system(size: 26))
            }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(deepBlue)
                .lineLimit(1)
            Text("\(count) 条")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: deepBlue.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - Count Helpers

    private func virtualCount(_ type: VirtualFolderType) -> Int {
        switch type {
        case .all:       return allRecords.count
        case .today:     return allRecords.filter { Calendar.current.isDateInToday($0.date) }.count
        case .favorites: return allRecords.filter { $0.isFavorite }.count
        }
    }
}

// MARK: - Virtual Folder Detail View

struct VirtualFolderDetailView: View {
    let type: VirtualFolderType
    @Query private var records: [ConversationRecord]
    @Environment(\.modelContext) private var modelContext

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    @Environment(\.colorScheme) private var colorScheme

    private var background: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22),
                                      Color(red: 0.04, green: 0.07, blue: 0.14)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.910, green: 0.957, blue: 0.992),
                                      Color(red: 0.722, green: 0.831, blue: 0.929)],
                             startPoint: .top, endPoint: .bottom)
    }

    init(type: VirtualFolderType) {
        self.type = type
        switch type {
        case .all:
            _records = Query(sort: \ConversationRecord.date, order: .reverse)
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            _records = Query(
                filter: #Predicate<ConversationRecord> { $0.date >= start },
                sort: \ConversationRecord.date, order: .reverse
            )
        case .favorites:
            _records = Query(
                filter: #Predicate<ConversationRecord> { $0.isFavorite },
                sort: \ConversationRecord.date, order: .reverse
            )
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if records.isEmpty {
                VStack(spacing: 12) {
                    Text(type.icon).font(.system(size: 48))
                    Text("暂无记录").font(.headline).foregroundColor(.secondary)
                }
            } else {
                RecordListContent(records: records, deepBlue: deepBlue, accentBlue: accentBlue)
            }
        }
        .navigationTitle("\(type.icon) \(type.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Custom Folder Detail View

struct CustomFolderDetailView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    @Environment(\.colorScheme) private var colorScheme

    private var background: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22),
                                      Color(red: 0.04, green: 0.07, blue: 0.14)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.910, green: 0.957, blue: 0.992),
                                      Color(red: 0.722, green: 0.831, blue: 0.929)],
                             startPoint: .top, endPoint: .bottom)
    }

    private var sortedRecords: [ConversationRecord] {
        folder.records.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if sortedRecords.isEmpty {
                VStack(spacing: 12) {
                    Text(folder.icon).font(.system(size: 48))
                    Text("文件夹为空").font(.headline).foregroundColor(.secondary)
                }
            } else {
                RecordListContent(records: sortedRecords, deepBlue: deepBlue, accentBlue: accentBlue)
            }
        }
        .navigationTitle("\(folder.icon) \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Shared Record List Content

struct RecordListContent: View {
    let records: [ConversationRecord]
    let deepBlue: Color
    let accentBlue: Color
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(records) { record in
                FolderRecordRow(record: record, deepBlue: deepBlue, accentBlue: accentBlue)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(records[i]) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct FolderRecordRow: View {
    let record: ConversationRecord
    let deepBlue: Color
    let accentBlue: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(deepBlue)
                    .lineLimit(1)
                Spacer()
                if record.isFavorite {
                    Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                }
                Text(record.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("\(record.sourceLanguage) → \(record.targetLanguage)")
                .font(.caption2.weight(.medium))
                .foregroundColor(accentBlue)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(accentBlue.opacity(0.1))
                .clipShape(Capsule())
            Text(record.originalText)
                .font(.caption).foregroundColor(.secondary).lineLimit(2)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.5), lineWidth: 1))
        .shadow(color: deepBlue.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Create Folder Sheet

struct CreateFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String) -> Void

    @State private var name = ""
    @State private var selectedEmoji = "📁"
    @State private var selectedColor = "#3B82F6"

    private let deepBlue   = Color(red: 0.172, green: 0.373, blue: 0.541)
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    private let emojis = ["📁","📝","⭐️","💡","🎯","💼","📚","🔖","💬","🌟","🎤","🌍","🎵","📸","✈️","🏠"]
    private let colors: [(hex: String, color: Color)] = [
        ("#3B82F6", .blue), ("#10B981", .green), ("#F59E0B", .yellow),
        ("#EF4444", .red),  ("#8B5CF6", .purple),("#EC4899", .pink),
        ("#14B8A6", .teal), ("#F97316", .orange)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("文件夹名称") {
                    TextField("输入名称", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojis, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .padding(6)
                                .background(selectedEmoji == emoji
                                    ? accentBlue.opacity(0.2)
                                    : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { selectedEmoji = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("颜色") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.hex) { preset in
                            Circle()
                                .fill(preset.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColor == preset.hex ? 3 : 0)
                                        .padding(2)
                                )
                                .shadow(color: preset.color.opacity(0.4), radius: 4)
                                .onTapGesture { selectedColor = preset.hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新建文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onCreate(name.trimmingCharacters(in: .whitespaces), selectedEmoji, selectedColor)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - VirtualFolderType: Hashable (for navigationDestination)

extension VirtualFolderType: Hashable {}
