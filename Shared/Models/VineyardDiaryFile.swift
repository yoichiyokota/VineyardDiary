import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let vineyardDiary = UTType(exportedAs: "com.collduno.vineyarddiary.json", conformingTo: .json)
}

struct VineyardDiaryFile: Codable {
    var entries: [DiaryEntry]
}
