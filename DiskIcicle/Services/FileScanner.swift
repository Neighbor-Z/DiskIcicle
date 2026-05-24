import Foundation

struct FileScanner {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isAliasFileKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .isPackageKey,
        .isVolumeKey
    ]

    static func scan(rootURL: URL) async -> FileNode {
        let standardizedRoot = rootURL.standardizedFileURL
        // Use a detached task to avoid blocking the MainActor
        return await Task.detached(priority: .userInitiated) {
            return await scanNodeConcurrent(url: standardizedRoot, rootURL: standardizedRoot, allocateChildren: true)
        }.value
    }

    private static func scanNodeConcurrent(url: URL, rootURL: URL, allocateChildren: Bool) async -> FileNode {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let isAlias = values?.isAliasFile ?? false
        
        // Only treat as directory if it's a real directory, not a link/alias
        let isDirectory = (values?.isDirectory ?? false) && !isSymbolicLink && !isAlias
        
        // Treat packages (e.g., .app) as simple files in the UI, but traverse them to calculate total size
        let isPackage = values?.isPackage ?? false

        if isDirectory {
            let shouldAllocateChildren = allocateChildren && !isPackage
            var children: [FileNode]? = shouldAllocateChildren ? [] : nil
            var totalSize: Int64 = 0
            
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                )
                
                // Scan directories concurrently using TaskGroup for maximum performance on macOS APFS
                await withTaskGroup(of: FileNode.self) { group in
                    for childURL in contents {
                        // Skip crossing volume boundaries (mount points) or specific system folders to avoid double counting.
                        // We follow firmlinks (like /Users) because they aren't mount points.
                        let childValues = try? childURL.resourceValues(forKeys: [.isVolumeKey])
                        let isMount = childValues?.isVolume ?? false
                        
                        let path = childURL.path
                        if (isMount && childURL.path != rootURL.path) || 
                            path == "/Volumes" || path == "/dev" || path == "/Network" || path == "/cores" {
                            continue
                        }

                        group.addTask {
                            return await scanNodeConcurrent(url: childURL, rootURL: rootURL, allocateChildren: shouldAllocateChildren)
                        }
                    }
                    
                    for await childNode in group {
                        if childNode.size > 0 || childNode.children != nil {
                            children?.append(childNode)
                            totalSize += childNode.size
                        }
                    }
                }
                
                let sortedChildren = children?.sorted { $0.size > $1.size }
                return FileNode(
                    name: name,
                    url: url,
                    size: totalSize,
                    children: sortedChildren,
                    type: isPackage ? .file : .folder
                )
            } catch {
                return FileNode(
                    name: name,
                    url: url,
                    size: 0,
                    children: nil,
                    type: isPackage ? .file : .folder
                )
            }
        } else {
            // For files/links, use allocated size (actual disk space) if available
            let fileSize = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            return FileNode(
                name: name,
                url: url,
                size: fileSize,
                children: nil,
                type: .file
            )
        }
    }
}
