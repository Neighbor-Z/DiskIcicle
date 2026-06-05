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

    /// Maximum number of concurrent child-directory scans to limit peak memory.
    private static let maxConcurrentScans = 8

    static func scan(rootURL: URL) async -> FileNode {
        let standardizedRoot = rootURL.standardizedFileURL
        let excludedPaths = UserDefaults.standard.stringArray(forKey: "userExcludedPaths") ?? []

        // Use a detached task so the heavy I/O runs off the MainActor,
        // but bridge cancellation so that cancelling the parent task
        // also cancels the detached work.
        let detachedTask = Task.detached(priority: .userInitiated) {
            return await scanNodeConcurrent(
                url: standardizedRoot,
                rootURL: standardizedRoot,
                allocateChildren: true,
                excludedPaths: excludedPaths
            )
        }

        return await withTaskCancellationHandler {
            return await detachedTask.value
        } onCancel: {
            detachedTask.cancel()
        }
    }

    private static func scanNodeConcurrent(url: URL, rootURL: URL, allocateChildren: Bool, excludedPaths: [String]) async -> FileNode {
        // Cooperative cancellation: bail out early if the task was cancelled
        if Task.isCancelled {
            return FileNode(name: url.lastPathComponent, path: url.path, size: 0, children: nil, type: .file)
        }

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
            var totalSize: Int64 = 0
            
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                )
                
                // Pre-filter to avoid keeping the full `contents` array alive.
                // Extract only the URLs we actually need, so the large URL array
                // returned by contentsOfDirectory can be freed immediately.
                var childURLs: [URL] = []
                childURLs.reserveCapacity(contents.count)
                for childURL in contents {
                    let childValues = try? childURL.resourceValues(forKeys: [.isVolumeKey])
                    let isMount = childValues?.isVolume ?? false
                    let path = childURL.path
                    
                    if (isMount && childURL.path != rootURL.path) ||
                        path == "/Volumes" || path == "/dev" || path == "/Network" || path == "/cores" || path == "/.nofollow" {
                        continue
                    }
                    
                    if excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                        continue
                    }
                    
                    childURLs.append(childURL)
                }
                // `contents` goes out of scope here and can be freed

                // Pre-allocate children array with exact capacity (no over-allocation)
                var children: [FileNode]? = shouldAllocateChildren ? {
                    var arr = [FileNode]()
                    arr.reserveCapacity(childURLs.count)
                    return arr
                }() : nil

                // Process children in batches to limit peak memory from concurrent scans.
                let batchSize = maxConcurrentScans
                for batchStart in stride(from: 0, to: childURLs.count, by: batchSize) {
                    if Task.isCancelled { break }
                    
                    let batchEnd = min(batchStart + batchSize, childURLs.count)
                    let batch = childURLs[batchStart..<batchEnd]
                    
                    await withTaskGroup(of: FileNode.self) { group in
                        for childURL in batch {
                            group.addTask {
                                guard !Task.isCancelled else {
                                    return FileNode(name: childURL.lastPathComponent, path: childURL.path, size: 0, children: nil, type: .file)
                                }
                                return await scanNodeConcurrent(
                                    url: childURL,
                                    rootURL: rootURL,
                                    allocateChildren: shouldAllocateChildren,
                                    excludedPaths: excludedPaths
                                )
                            }
                        }
                        
                        for await childNode in group {
                            if Task.isCancelled {
                                group.cancelAll()
                                break
                            }
                            if childNode.size > 0 || childNode.children != nil {
                                children?.append(childNode)
                                totalSize += childNode.size
                            }
                        }
                    }
                }
                
                children?.sort { $0.size > $1.size }
                return FileNode(
                    name: name,
                    path: url.path,
                    size: totalSize,
                    children: children,
                    type: isPackage ? .file : .folder
                )
            } catch {
                return FileNode(
                    name: name,
                    path: url.path,
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
                path: url.path,
                size: fileSize,
                children: nil,
                type: .file
            )
        }
    }
}
