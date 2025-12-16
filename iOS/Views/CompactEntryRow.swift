//
//  Created by yoichi_yokota on 2025/12/16.
//


#if os(iOS)
import SwiftUI

// MARK: - Compact Entry Row (iOS List用)

/// iOS List用のコンパクトなエントリ行
/// - サムネイル + 日付/区画 + 作業メモ + 気象情報を1行に表示
struct CompactEntryRow: View {
    let entry: DiaryEntry
    @ObservedObject var weather: DailyWeatherStore
    @EnvironmentObject var thumbs: ThumbnailStore
    
    // レイアウト定数
    private let thumbSize = CGSize(width: 56, height: 42)
    
    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            entryInfo
            Spacer(minLength: 8)
            weatherInfo
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Thumbnail
    
    private var thumbnailView: some View {
        Group {
            if let name = primaryPhotoName(),
               let img = thumbs.thumbnail(for: name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let name = primaryPhotoName() {
                // フォールバック：サムネ未生成の場合、元画像を直接読み込み
                fallbackOriginalImage(name: name)
            } else {
                placeholderView
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func fallbackOriginalImage(name: String) -> some View {
        Group {
            let originalURL = URL.documentsDirectory.appendingPathComponent(name)
            if let raw = UIImage(contentsOfFile: originalURL.path) {
                Image(uiImage: raw)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
            Image(systemName: "photo")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Entry Info
    
    private var entryInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            headerLine
            
            if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.workNotes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    private var headerLine: some View {
        HStack(spacing: 8) {
            Text(DateFormatters.dayWithWeekday.string(from: entry.date))
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if !entry.block.isEmpty {
                Text("· \(entry.block)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
    
    // MARK: - Weather Info
    
    private var weatherInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let temp = temperatureLabel {
                Text(temp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let sun = sunshineLabel {
                Text(sun)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let rain = rainLabel {
                Text(rain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 90, alignment: .trailing)
    }
    
    // MARK: - Weather Labels
    
    private var temperatureLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let tmax = w.tMax,
              let tmin = w.tMin else {
            return nil
        }
        return String(format: "%.0f/%.0f℃", tmax, tmin)
    }
    
    private var sunshineLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let sun = w.sunshineHours else {
            return nil
        }
        return String(format: "☀︎ %.1fh", sun)
    }
    
    private var rainLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let r = w.precipitationMm else {
            return nil
        }
        return String(format: "☂︎ %.0fmm", r)
    }
    
    // MARK: - Photo Name Logic
    
    /// 元画像名を抽出（サムネ名を除外）
    private func primaryPhotoName() -> String? {
        guard !entry.photos.isEmpty else { return nil }
        
        // サムネっぽいものを除外して最初の1枚を選ぶ
        if let original = entry.photos.first(where: { !isThumbName($0) }) {
            return original
        }
        
        // 全部サムネ名しかない場合は先頭を採用
        return entry.photos.first
    }
    
    /// サムネイル名かどうか判定
    private func isThumbName(_ name: String) -> Bool {
        let lower = name.lowercased()
        
        // フォルダ名にthumbが含まれる
        if lower.contains("/thumb/") || 
           lower.contains("/thumbs/") || 
           lower.contains("/.thumbs/") {
            return true
        }
        
        // ファイル名に_thumb等が含まれる
        if lower.contains("_thumb.") || 
           lower.contains("-thumb.") || 
           lower.contains(".thumb.") {
            return true
        }
        
        // サイズサフィックス（-150x150等）
        if lower.range(of: #"-\d{2,4}x\d{2,4}\."#, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
}

// MARK: - Date Formatters

private enum DateFormatters {
    static let dayWithWeekday: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy/MM/dd (EEE)"
        return df
    }()
}

// MARK: - Preview

#if DEBUG
struct CompactEntryRow_Previews: PreviewProvider {
    static var previews: some View {
        let entry = DiaryEntry(
            date: Date(),
            block: "深沢(630m)",
            varieties: [
                VarietyStageItem(varietyName: "シャルドネ", stage: "23: 満開期")
            ],
            isSpraying: true,
            workNotes: "摘房作業を実施",
            memo: "順調に生育中",
            photos: ["IMG_0001.jpg"]
        )
        
        List {
            CompactEntryRow(
                entry: entry,
                weather: DailyWeatherStore()
            )
            .environmentObject(ThumbnailStore())
        }
        .listStyle(.plain)
    }
}
#endif

#endif
