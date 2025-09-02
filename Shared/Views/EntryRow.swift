import SwiftUI

private extension DateFormatter {
    static let vdDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy/MM/dd (E)"   // 例: 2025/09/01 (月)
        return f
    }()
}

struct EntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 復活: 日付ヘッダー（太字）
            Text(DateFormatter.vdDay.string(from: entry.date))
                   .font(.headline)
            Text("区画: \(entry.block.isEmpty ? "未選択" : entry.block)")
                .font(.body)                  // ← 他と同じサイズに変更
                .foregroundStyle(.primary)    // ← 標準テキストカラーに変更
                .padding(.vertical, 2)        // ← 行間をそろえるために軽く余白を追加（任意）
            // 品種
            LabeledLine(title: "品種", text: varietiesText())
            
            // 防除（ある時だけ・赤）
            if entry.isSpraying {
                LabeledLine(
                    title: "防除",
                    text: sprayText(),
                    foreground: .red
                )
            }
            
            // 作業時間（1行で）
            if !entry.workTimes.isEmpty {
                LabeledLine(title: "作業時間", text: workTimesText())
            }
            
            // 作業内容（全表示）
            if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledLine(title: "作業内容", text: entry.workNotes)
            }
            
            // 備考（全表示）
            if !entry.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledLine(title: "備考", text: entry.memo)
            }
            
            // ボランティア（1行で）
            if !entry.volunteers.isEmpty {
                LabeledLine(title: "ボランティア", text: volunteersText())
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: テキスト整形

    private func varietiesText() -> String {
        // 「品種名(ステージ)」をカンマ区切り
        entry.varieties
            .map { v in
                let name = v.varietyName.isEmpty ? "（未選択）" : v.varietyName
                if v.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "\(name)"
                } else {
                    return "\(name)（\(v.stage)）"
                }
            }
            .joined(separator: ", ")
    }

    private func sprayText() -> String {
        // 例：「液量: 200L / 薬剤: ボルドー(1000倍)・スコア(2000倍)」
        let liters = entry.sprayTotalLiters.trimmingCharacters(in: .whitespacesAndNewlines)
        let litersPart = liters.isEmpty ? "" : "液量: \(liters)L"

        let chems = entry.sprays
            .map { s -> String in
                let name = s.chemicalName.trimmingCharacters(in: .whitespacesAndNewlines)
                let d    = s.dilution.trimmingCharacters(in: .whitespacesAndNewlines)
                switch (name.isEmpty, d.isEmpty) {
                case (false, false): return "\(name)(\(d)倍)"  // ← 倍表記
                case (false, true):  return "\(name)"
                case (true,  false): return "\(d)倍"          // 名前なしなら倍率のみ（必要なければ "" に）
                default:             return ""
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "・") // カンマにしたい場合は ", " に

        let chemPart = chems.isEmpty ? "" : "薬剤: \(chems)"

        return [litersPart, chemPart]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private func workTimesText() -> String {
        // 例：「08:30〜10:00, 14:15〜15:20」
        let df = EntryRow.hhmm
        return entry.workTimes
            .map { "\(df.string(from: $0.start))〜\(df.string(from: $0.end))" }
            .joined(separator: ", ")
    }

    private func volunteersText() -> String {
        entry.volunteers.joined(separator: ", ")
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// 見出し＋本文を1行/複数行で共通表示
fileprivate struct LabeledLine: View {
    let title: String
    let text: String
    var foreground: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(text)
                .foregroundStyle(foreground ?? .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true) // 折り返して全表示
                .multilineTextAlignment(.leading)
        }
    }
}
