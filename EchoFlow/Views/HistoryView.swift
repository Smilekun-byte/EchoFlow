import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationRecord.date, order: .reverse) private var records: [ConversationRecord]
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var showFolderView = false

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

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                if records.isEmpty { emptyState } else { recordList }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFolderView = true
                    } label: {
                        Image(systemName: "folder")
                            .foregroundColor(accentBlue)
                    }
                }
            }
            .sheet(isPresented: $showFolderView) {
                FolderView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 52))
                .foregroundColor(accentBlue.opacity(0.45))
            Text("还没有记录")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("录音停止后会自动保存")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Record List

    private var recordList: some View {
        List {
            ForEach(records) { record in
                recordRow(record)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .contextMenu { contextMenu(for: record) }
            }
            .onDelete(perform: deleteRecords)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Record Row

    private func recordRow(_ record: ConversationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(deepBlue)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(record.sourceLanguage) → \(record.targetLanguage)")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(accentBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(accentBlue.opacity(0.1))
                            .clipShape(Capsule())
                        if let folder = record.folder {
                            Text("\(folder.icon) \(folder.name)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(record.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }

            Text(record.originalText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if !record.keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(record.keywords, id: \.self) { kw in
                            Text(kw)
                                .font(.caption2)
                                .foregroundColor(deepBlue.opacity(0.7))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(deepBlue.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: deepBlue.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for record: ConversationRecord) -> some View {
        Button {
            record.isFavorite.toggle()
        } label: {
            Label(record.isFavorite ? "取消收藏" : "收藏",
                  systemImage: record.isFavorite ? "star.slash" : "star")
        }

        if !folders.isEmpty {
            Menu("移动到文件夹") {
                Button {
                    record.folder = nil
                } label: {
                    Label("无文件夹", systemImage: "xmark.circle")
                }
                ForEach(folders) { folder in
                    Button {
                        record.folder = folder
                    } label: {
                        Text("\(folder.icon) \(folder.name)")
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            modelContext.delete(record)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func deleteRecords(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(records[i]) }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            f.dateFormat = "MM/dd"
        }
        return f.string(from: date)
    }
}
