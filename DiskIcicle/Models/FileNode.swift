import Foundation
import SwiftUI

enum FileNodeType: String, Codable {
    case file
    case folder
}

final class FileNode: Identifiable, Hashable {
    nonisolated let id = UUID()

    let name: String
    /// Lightweight string path
    let path: String
    var size: Int64
    var children: [FileNode]?
    let type: FileNodeType

    /// Lazily computed URL from the stored string path (only materialised when needed)
    var url: URL { URL(fileURLWithPath: path) }

    init(name: String, path: String, size: Int64, children: [FileNode]? = nil, type: FileNodeType) {
        self.name = name
        self.path = path
        self.size = size
        self.children = children
        self.type = type
    }

    /// Convenience initialiser that accepts a URL (for call-site compatibility during migration)
    convenience init(name: String, url: URL, size: Int64, children: [FileNode]? = nil, type: FileNodeType) {
        self.init(name: name, path: url.path, size: size, children: children, type: type)
    }

    // MARK: - Hashable (identity-based, since this is a reference type)
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    /// Compact memory after the tree is fully built.
    /// Trims excess capacity from children arrays, recursively.
    func compactMemory() {
        guard var kids = children else { return }
        // Array.append() growth strategy can leave up to 2× capacity.
        // After the tree is final, trim to exact size.
        if kids.capacity > kids.count {
            kids = Array(kids)       // re-allocate to exact count
            children = kids
        }
        for child in kids {
            child.compactMemory()
        }
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

        // For files, use extension for color (much cheaper than full path hash)
        let key: String
        if type == .folder {
            key = name  // folder name is stable enough for color
        } else {
            key = (name as NSString).pathExtension.lowercased()
        }
        let hash = abs(key.hashValue)
        return palette[hash % palette.count]
    }
}
