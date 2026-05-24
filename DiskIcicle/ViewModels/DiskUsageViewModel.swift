import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

@MainActor
final class DiskUsageViewModel: ObservableObject {
    @Published private(set) var rootNode: FileNode?
    @Published var currentRoot: FileNode?
    @Published var selectedNode: FileNode?
    @Published var isScanning: Bool = false
    @Published var isLiveScan: Bool = false
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    func startScan(rootURL: URL? = nil) {
        scanTask?.cancel()
        isScanning = true
        errorMessage = nil

        scanTask = Task {
            do {
                let node: FileNode
                
                #if os(macOS)
                if let url = rootURL {
                    if url.pathExtension.lowercased() == "txt" {
                        node = try await DiskUsageImporter.importFromText(url: url)
                        isLiveScan = false
                    } else {
                        node = await FileScanner.scan(rootURL: url)
                        isLiveScan = true
                    }
                } else {
                    throw NSError(domain: "DiskUsageMap", code: 400, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "error.noFolderSelected")
                    ])
                }
                #elseif targetEnvironment(simulator)
                // Simulator Fallback
                if let bundleURL = Bundle.main.url(forResource: "disk_usage", withExtension: "txt") {
                    node = try await DiskUsageImporter.importFromText(url: bundleURL)
                    isLiveScan = false
                } else {
                    // Simulator: show iOS native file picker
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.main.async {
                            #if canImport(UIKit)
                            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                                  let rootVC = window.rootViewController else {
                                continuation.resume(throwing: NSError(domain: "DiskUsageMap", code: 500, userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to present file picker")]))
                                return
                            }
                            
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
                            picker.title = String(localized: "Select a txt file exported by du")
                            let delegate = DocumentPickerDelegate(continuation: continuation)
                            picker.delegate = delegate
                            
                            // Retain the delegate
                            objc_setAssociatedObject(picker, "DocumentPickerDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            
                            var presenter = rootVC
                            while let presented = presenter.presentedViewController {
                                presenter = presented
                            }
                            presenter.present(picker, animated: true)
                            #else
                            
                            // Use hardcoded sample data if file not found in bundle
                            let sampleData = """
                            10300\t/var/mobile/Photos
                            10200\t/var/mobile/Photos/DCIM
                            10100\t/var/mobile/Photos/DCIM/100APPLE
                            5000\t/var/mobile/Photos/DCIM/100APPLE/IMG_0001.JPG
                            5000\t/var/mobile/Photos/DCIM/100APPLE/IMG_0002.JPG
                            5250\t/var/mobile/Applications
                            5200\t/var/mobile/Applications/MyApp
                            5120\t/var/mobile/Applications/MyApp/MyApp.app
                            """
                            node = try DiskUsageImporter.importFromProcessString(sampleData)
                            #endif
                        }
                    }
                    
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    node = try await DiskUsageImporter.importFromText(url: url)
                    isLiveScan = false
                }
                #else
                // Device: /var/mobile/Documents/disk_usage.txt
                let documentsPath = "/var/mobile/Documents/disk_usage.txt"
                let fileURL = URL(fileURLWithPath: documentsPath)
                
                if FileManager.default.fileExists(atPath: documentsPath) {
                    node = try await DiskUsageImporter.importFromText(url: fileURL)
                    isLiveScan = false
                } else {
                    // Device: show iOS native file picker
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.main.async {
                            #if canImport(UIKit)
                            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                                  let rootVC = window.rootViewController else {
                                continuation.resume(throwing: NSError(domain: "DiskUsageMap", code: 500, userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to present file picker")]))
                                return
                            }
                            
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
                            picker.title = String(localized: "Select a txt file exported by du")
                            let delegate = DocumentPickerDelegate(continuation: continuation)
                            picker.delegate = delegate
                            
                            // Retain the delegate
                            objc_setAssociatedObject(picker, "DocumentPickerDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            
                            var presenter = rootVC
                            while let presented = presenter.presentedViewController {
                                presenter = presented
                            }
                            presenter.present(picker, animated: true)
                            #else
                            continuation.resume(throwing: NSError(domain: "DiskUsageMap", code: 500, userInfo: [NSLocalizedDescriptionKey: "Not supported on this platform"]))
                            #endif
                        }
                    }
                    
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    node = try await DiskUsageImporter.importFromText(url: url)
                    isLiveScan = false
                }
                #endif
                
                if Task.isCancelled { return }
                rootNode = node
                currentRoot = node
                selectedNode = node
                isScanning = false
                
            } catch {
                if Task.isCancelled { return }
                isScanning = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func zoomIn(to node: FileNode) {
        guard node.type == .folder, let children = node.children, !children.isEmpty else {
            selectedNode = node
            return
        }
        currentRoot = node
        selectedNode = node
    }

    func zoomOut() {
        guard let rootNode else { return }
        currentRoot = rootNode
        selectedNode = rootNode
    }

    func stepUp() {
        guard let rootNode, let current = currentRoot else { return }
        if rootNode.url == current.url {
            return
        }
        let pathNodes = path(from: rootNode, to: current)
        guard pathNodes.count >= 2 else { return }
        let parent = pathNodes[pathNodes.count - 2]
        currentRoot = parent
        selectedNode = parent
    }

    func select(node: FileNode) {
        selectedNode = node
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    var breadcrumb: [FileNode] {
        guard let rootNode, let currentRoot else { return [] }
        if rootNode.url == currentRoot.url { return [rootNode] }
        return path(from: rootNode, to: currentRoot)
    }

    private func path(from root: FileNode, to target: FileNode) -> [FileNode] {
        if root.url == target.url { return [root] }
        guard let children = root.children else { return [] }
        for child in children {
            let sub = path(from: child, to: target)
            if !sub.isEmpty {
                return [root] + sub
            }
        }
        return []
    }
}

#if canImport(UIKit)
final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    
    init(continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            continuation?.resume(returning: url)
        } else {
            continuation?.resume(throwing: NSError(domain: "DiskUsageMap", code: 400, userInfo: [NSLocalizedDescriptionKey: String(localized: "No file selected")]))
        }
        continuation = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation?.resume(throwing: NSError(domain: "DiskUsageMap", code: 400, userInfo: [NSLocalizedDescriptionKey: String(localized: "Cancelled by user")]))
        continuation = nil
    }
}
#endif
