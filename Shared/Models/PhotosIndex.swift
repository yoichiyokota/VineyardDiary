import Foundation

// 共有スキーマ：写真インデックス
struct PhotosIndex: Codable {
    struct Item: Codable {
        var fileName: String
        var caption: String
        var usedInEntryID: String
    }
    var index: [Item]
}
