import SwiftUI

private extension DateFormatter {
    static let vdDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy/MM/dd (E)"
        return f
    }()
}

struct EntryRow: View {
    @EnvironmentObject var thumbs: ThumbnailStore
    let entry: DiaryEntry
    var showLeadingThumbnail: Bool = true   // ← 追加：行内サムネの有無

    #if os(iOS)
    @State private var thumbImage: UIImage? = nil
    #else
    @State private var thumbImage: NSImage? = nil
    #endif

    var body: some View {
        HStack(spacing: 12) {

            // ← ここをフラグでON/OFF
            if showLeadingThumbnail {
                thumbView()
                    .frame(width: 90, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(DateFormatter.vdDay.string(from: entry.date))
                    .font(.headline)

                Text("区画: \(entry.block.isEmpty ? "未選択" : entry.block)")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 2)

                LabeledLine(title: "品種", text: varietiesText())

                if entry.isSpraying {
                    LabeledLine(title: "防除", text: sprayText(), foreground: .red)
                }
                if !entry.workTimes.isEmpty {
                    LabeledLine(title: "作業時間", text: workTimesText())
                }
                if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledLine(title: "作業内容", text: entry.workNotes)
                }
                if !entry.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledLine(title: "備考", text: entry.memo)
                }
                if !entry.volunteers.isEmpty {
                    LabeledLine(title: "ボランティア", text: volunteersText())
                }
            }
            .padding(.vertical, 6)

            Spacer(minLength: 0)
        }
        .task(loadThumbIfNeeded)
        .onChange(of: entry.photos) { _ in loadThumbIfNeeded() }
    }

    // MARK: - サムネビュー
    @ViewBuilder
    private func thumbView() -> some View {
        if let image = thumbImage {
            #if os(iOS)
            Image(uiImage: image).resizable().scaledToFill()
            #else
            Image(nsImage: image).resizable().scaledToFill()
            #endif
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - サムネ用：サムネ名を広く検出 & 正規化
    private func isThumbnailFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("/thumb/") || lower.contains("/thumbs/") || lower.contains("/.thumbs/") { return true }
        if lower.contains("_thumb.") || lower.contains("-thumb.") || lower.contains(".thumb.") { return true }
        if lower.range(of: #"-\d{2,4}x\d{2,4}\."#, options: .regularExpression) != nil { return true }
        return false
    }
    private func normalizedBase(_ name: String) -> String {
        let lower = name.lowercased()
        let last = lower.split(separator: "/").last.map(String.init) ?? lower
        let noSize = last.replacingOccurrences(of: #"-\d{2,4}x\d{2,4}(?=\.)"#,
                                               with: "", options: .regularExpression)
        var base = noSize
            .replacingOccurrences(of: "_thumb", with: "")
            .replacingOccurrences(of: "-thumb", with: "")
            .replacingOccurrences(of: ".thumb", with: "")
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        return base
    }
    private func primaryPhotoName() -> String? {
        guard !entry.photos.isEmpty else { return nil }
        let groups = Dictionary(grouping: entry.photos, by: normalizedBase)
        guard let firstGroup = groups.values.first else { return entry.photos.first }
        if let original = firstGroup.first(where: { !isThumbnailFilename($0) }) {
            return original
        } else {
            return firstGroup.first
        }
    }

    private func loadThumbIfNeeded() {
        guard let name = primaryPhotoName() else { thumbImage = nil; return }
        if let img = thumbs.thumbnail(for: name) {
            thumbImage = img
        } else {
            thumbImage = nil
        }
    }

    // MARK: - テキスト整形
    private func varietiesText() -> String {
        entry.varieties
            .map { v in
                let name = v.varietyName.isEmpty ? "（未選択）" : v.varietyName
                let st = v.stage.trimmingCharacters(in: .whitespacesAndNewlines)
                return st.isEmpty ? "\(name)" : "\(name)（\(st)）"
            }
            .joined(separator: ", ")
    }
    private func sprayText() -> String {
        let liters = entry.sprayTotalLiters.trimmingCharacters(in: .whitespacesAndNewlines)
        let litersPart = liters.isEmpty ? "" : "液量: \(liters)L"
        let chems = entry.sprays.map { s -> String in
            let name = s.chemicalName.trimmingCharacters(in: .whitespacesAndNewlines)
            let d    = s.dilution.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (name.isEmpty, d.isEmpty) {
            case (false, false): return "\(name)(\(d)倍)"
            case (false, true):  return "\(name)"
            case (true,  false): return "\(d)倍"
            default:             return ""
            }
        }.filter { !$0.isEmpty }.joined(separator: "・")
        let chemPart = chems.isEmpty ? "" : "薬剤: \(chems)"
        return [litersPart, chemPart].filter { !$0.isEmpty }.joined(separator: " / ")
    }
    private func workTimesText() -> String {
        let df = EntryRow.hhmm
        return entry.workTimes.map { "\(df.string(from: $0.start))〜\(df.string(from: $0.end))" }.joined(separator: ", ")
    }
    private func volunteersText() -> String { entry.volunteers.joined(separator: ", ") }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.locale = .init(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// 見出し＋本文
fileprivate struct LabeledLine: View {
    let title: String
    let text: String
    var foreground: Color? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).bold()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(text)
                .foregroundStyle(foreground ?? .primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
    }
}
