import Foundation
import SwiftUI

enum FileNodeType: String, Codable {
    case file
    case folder
}

struct FileNode: Identifiable, Hashable {
    var id: URL { url }

    let name: String
    let url: URL
    var size: Int64
    var children: [FileNode]?
    let type: FileNodeType

    init(name: String, url: URL, size: Int64, children: [FileNode]? = nil, type: FileNodeType) {
        self.name = name
        self.url = url
        self.size = size
        self.children = children
        self.type = type
    }

    var color: Color {
        let palette: [Color] = [
            Color(red: 0.91, green: 0.84, blue: 0.77), // warm beige
            Color(red: 0.74, green: 0.86, blue: 0.85), // misty teal
            Color(red: 0.67, green: 0.78, blue: 0.92), // soft blue
            Color(red: 0.93, green: 0.73, blue: 0.76), // rose
            Color(red: 0.78, green: 0.86, blue: 0.70), // sage
            Color(red: 0.88, green: 0.80, blue: 0.92), // lilac
            Color(red: 0.96, green: 0.86, blue: 0.70), // peach
            Color(red: 0.78, green: 0.73, blue: 0.67)  // taupe
        ]

        let key = type == .folder ? url.path : url.pathExtension.lowercased()
        let hash = abs(key.hashValue)
        return palette[hash % palette.count]
    }
}
