import Foundation
import SwiftUI

// Use a class for intermediate construction to allow reference sharing
private class IntermediateNode {
    let name: String
    let path: String
    var size: Int64
    var children: [IntermediateNode] = []
    var type: FileNodeType
    
    init(name: String, path: String, size: Int64, type: FileNodeType) {
        self.name = name
        self.path = path
        self.size = size
        self.type = type
    }
    
    func toFileNode() -> FileNode {
        let childNodes = children.sorted { $0.size > $1.size }.map { $0.toFileNode() }
        
        // Recalculate size for implicit folders if needed (optional, but valid)
        // If type is folder and size is 0 (implicit), we might want to sum children?
        // For now, trust the size passed in or 0.
        // Actually, for implicit nodes, size starts at 0. We should sum it up.
        var finalSize = size
        if type == .folder && size == 0 && !children.isEmpty {
           finalSize = children.reduce(0) { $0 + $1.size }
        }

        return FileNode(
            name: name,
            path: path,
            size: finalSize,
            children: childNodes.isEmpty ? nil : childNodes,
            type: childNodes.isEmpty ? .file : .folder 
            // Note: If original type was file but it has children, it forces to folder? 
            // In du output, a file shouldn't have children.
        )
    }
}

struct DiskUsageImporter {
    
    static func importFromText(url: URL) async throws -> FileNode {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.fileReadFailed(url: url, error: error)
        }
        
        return try parse(content: content)
    }
    
    static func importFromProcessString(_ content: String) throws -> FileNode {
        return try parse(content: content)
    }
    
    private static func parse(content: String) throws -> FileNode {
        var nodesByPath: [String: IntermediateNode] = [:]
        
        // Helper to get or create node
        func getOrCreateNode(path: String, isExplicit: Bool = false, size: Int64 = 0) -> IntermediateNode {
            if let existing = nodesByPath[path] {
                if isExplicit {
                    existing.size = size // Update size if we found the explicit line
                }
                return existing
            }
            
            let name = URL(fileURLWithPath: path).lastPathComponent
            let node = IntermediateNode(
                name: name.isEmpty ? path : name, 
                path: path, 
                size: size, 
                type: .folder // Default to folder for intermediate/implicit
            )
            nodesByPath[path] = node
            return node
        }
        
        // 1. Parsing Pass
        var isCancelled = false
        content.enumerateLines { line, stop in
            if Task.isCancelled {
                stop = true
                isCancelled = true
                return
            }
            
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let sizeKB = Int64(parts[0]) else { return }
            
            let path = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty { return }
            
            let sizeBytes = sizeKB * 1024
            
            // Register explicit node
            let node = getOrCreateNode(path: path, isExplicit: true, size: sizeBytes)
            // set it to .file by default if created explicitly, and upgrade to .folder if children are added.
            if node.children.isEmpty { 
                node.type = .file 
            }
        }
        
        if isCancelled { throw CancellationError() }
        try Task.checkCancellation()
        
        // 2. Icicle Building Pass
        // We need to iterate over all values to attach them to parents.
        
        let allPaths = Array(nodesByPath.keys)
        
        // for path in allPaths {
        for (index, path) in allPaths.enumerated() {
            // Check cancellation periodically to avoid overhead
            if index % 100 == 0 {
                try Task.checkCancellation()
            }
            
            guard let node = nodesByPath[path] else { continue }
            
            // Find parent
            let parentPath = (path as NSString).deletingLastPathComponent
            if parentPath == path || path == "/" || path == "/var/mobile" || path == "/storage/emulated/0" { 
                // It's a root candidate
                continue 
            }
            
            // Ensure parent exists (Implicit creation)
            // We are iterating a fixed array `allPaths`. Newly created nodes won't be processed in this loop.
            // So we need a recursive "ensureParent" or a loop that handles new nodes.
            
            var currentPath = path
            var currentNode = node
            
            while true {
                 let pPath = (currentPath as NSString).deletingLastPathComponent
                 if pPath == currentPath { break } // Root reached
                 
                 if let parent = nodesByPath[pPath] {
                     // Parent exists, attach and stop
                     if !parent.children.contains(where: { $0 === currentNode }) {
                         parent.children.append(currentNode)
                         parent.type = .folder // Parent must be a folder
                     }
                     break
                 } else {
                     // Parent missing, create implicit parent
                     let pName = URL(fileURLWithPath: pPath).lastPathComponent
                     let parent = IntermediateNode(
                        name: pName.isEmpty ? pPath : pName, 
                        path: pPath, 
                        size: 0, 
                        type: .folder
                     )
                     nodesByPath[pPath] = parent
                     parent.children.append(currentNode)
                     
                     // Continue up the chain with the new parent
                     currentNode = parent
                     currentPath = pPath
                 }
            }
        }
        
        // 3. Find Root
        // We look for the node with the shortest path
        let sortedNodes = nodesByPath.values.sorted { $0.path.count < $1.path.count }
        
        guard let root = sortedNodes.first else {
             throw ImportError.emptyContent
        }
        
        return root.toFileNode()
    }
}

enum ImportError: Error, LocalizedError {
    case fileReadFailed(url: URL, error: Error)
    case emptyContent
    
    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url, let error):
            return String(
                format: NSLocalizedString(
                    "error.fileReadFailed",
                    comment: "Error when failing to read a file at a path with the underlying error"
                ),
                url.path,
                error.localizedDescription
            )
        case .emptyContent:
            return String(localized: "error.emptyContent")
        }
    }
}
