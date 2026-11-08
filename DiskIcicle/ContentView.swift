import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ContentView: View {
    @StateObject private var viewModel = DiskUsageViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Panel State
    // Initial height 320, used to control the bottom panel
    @State private var panelHeight: CGFloat = 320
    @State private var isDraggingPanel: Bool = false
    @State private var isSidebarPresented = true
    @State private var showingRescanConfirmation = false
    #if os(macOS)
    @State private var isCanvasDropTargeted = false
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            if horizontalSizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
            #endif
        }
        #if !os(macOS)
        .background {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
        }
        #endif
        .alert("Error", isPresented: Binding(
            get: {
                viewModel.errorMessage != nil && horizontalSizeClass != .compact
            },
            set: { isPresented in
                guard !isPresented else { return }
                Task { @MainActor in
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert("Confirm Rescan", isPresented: Binding(
            get: {
                showingRescanConfirmation && horizontalSizeClass != .compact
            },
            set: { isPresented in
                if !isPresented {
                    showingRescanConfirmation = false
                }
            }
        )) {
            Button("Rescan", role: .destructive) {
                startRescan()
            }
            Button("Cancel", role: .cancel) {
                showingRescanConfirmation = false
            }
        } message: {
            Text("Scanning the disk may take a significant amount of time. Do you want to rescan?")
        }
    }

    private func startRescan() {
        #if os(macOS)
        if let url = viewModel.rootNode?.url {
            viewModel.startScan(rootURL: url)
        }
        #else
        viewModel.startScan()
        #endif
    }

    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        NavigationView {
            sidebarList
                .navigationTitle(String(localized: "Disk Usage"))
                .frame(minWidth: 200, idealWidth: 230)
            VStack(spacing: 0) {
                if viewModel.currentRoot != nil {
                    breadcrumbBar
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.bar)
                    Divider()
                }
                macOSDropCanvas
            }
            .navigationTitle(viewModel.currentRoot?.name ?? String(localized: "Icicle View"))
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help(String(localized: "Toggle Sidebar"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Scan") {
                    selectFolderAndScan()
                }
                .disabled(viewModel.isScanning)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showingRescanConfirmation = true
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan Directory")
                .disabled(viewModel.isScanning || viewModel.rootNode == nil)
            }
        }
    }

    private var macOSDropCanvas: some View {
        mapPanel(showBreadcrumbOverlay: false)
            .overlay {
                if isCanvasDropTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor.opacity(0.08))
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [14, 10])
                            )
                        Text("Drop to Scan")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isCanvasDropTargeted) { providers in
                isCanvasDropTargeted = false
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        var isDirectory: ObjCBool = false
                        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                        if exists {
                            if isDirectory.boolValue {
                                viewModel.startScan(rootURL: url)
                            } else if url.pathExtension.lowercased() == "txt" {
                                viewModel.startScan(rootURL: url)
                            } else {
                                viewModel.errorMessage = String(localized: "Only folders and .txt files are supported for drag and drop.")
                            }
                        }
                    }
                }
                return true
            }
    }

    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    private func selectFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.folder, .plainText]
        } else {
            panel.allowedFileTypes = ["public.folder", "public.plain-text", "txt"]
        }
        panel.message = String(localized: "Select a folder to scan or import from a txt file")
        
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.startScan(rootURL: url)
        }
    }
    #else

    // MARK: - Phone Layout (Bottom Sheet Style)
    @ViewBuilder
    private var phoneLayout: some View {
        if #available(iOS 16.0, *) {
            nativePhoneLayout
        } else {
            legacyPhoneLayout
        }
    }

    @available(iOS 16.0, *)
    private var nativePhoneLayout: some View {
        mapPanel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $isSidebarPresented) {
                nativeSidebarPanel
            }
            .onAppear {
                isSidebarPresented = true
            }
    }

    @available(iOS 16.0, *)
    @ViewBuilder
    private var nativeSidebarPanel: some View {
        if #available(iOS 16.4, *) {
            sidebarPanel
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            sidebarPanel
        }
    }

    @available(iOS 16.0, *)
    private var sidebarPanel: some View {
        NavigationStack {
            sidebar(showingHeader: false)
                .navigationTitle("Disk Usage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.stepUp()
                        } label: {
                            Label("Upper Level", systemImage: "chevron.backward")
                        }
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(viewModel.breadcrumb.count <= 1)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Scan") {
                            showingRescanConfirmation = true
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(viewModel.isScanning)
                    }
                }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                guard !isPresented else { return }
                Task { @MainActor in
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert("Confirm Rescan", isPresented: $showingRescanConfirmation) {
            Button("Rescan", role: .destructive) {
                startRescan()
            }
            Button("Cancel", role: .cancel) {
                showingRescanConfirmation = false
            }
        } message: {
            Text("Scanning the disk may take a significant amount of time. Do you want to rescan?")
        }
        .presentationDetents([.height(96), .fraction(0.35), .medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    private var legacyPhoneLayout: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // 1. Chart area (automatically takes up remaining space)
                mapPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Only allow the chart area to receive taps when not dragging, to avoid accidental touches
                    .allowsHitTesting(!isDraggingPanel)

                // 2. Drag handle
                resizeHandle
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingPanel = true
                                // Pulling down is positive (decreases height), pulling up is negative (increases height)
                                let newHeight = panelHeight - value.translation.height
                                // Restrict height range: minimum 100, maximum 85% of screen height
                                let clampedHeight = min(max(100, newHeight), proxy.size.height * 0.85)
                                panelHeight = clampedHeight
                            }
                            .onEnded { _ in
                                isDraggingPanel = false
                            }
                    )

                // 3. Bottom list (variable height)
                sidebar()
                    .frame(height: panelHeight)
            }
        }
        .edgesIgnoringSafeArea(.bottom) // Extend bottom background to Home indicator area
    }
    
    // MARK: - Resize Handle View
    private var resizeHandle: some View {
        ZStack(alignment: .center) {
            // Background bar to expand the touch area and make it easier to grab
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .frame(height: 30)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: -2)
            
            // Visual "capsule" handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.vertical, 10)
        }
        .background(Color(UIColor.systemBackground)) // Block the underlying layer
    }

    // MARK: - iPad Layout
    private var ipadLayout: some View {
        NavigationView {
            sidebarList
                .navigationTitle(String(localized: "Disk Usage"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Scan") {
                            showingRescanConfirmation = true
                        }
                        .disabled(viewModel.isScanning)
                    }
                }
            VStack(spacing: 0) {
                if viewModel.currentRoot != nil {
                    breadcrumbBar
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.bar)
                    Divider()
                }
                mapPanel(showBreadcrumbOverlay: false)
                    .ignoresSafeArea(.container, edges: [.trailing, .bottom])
            }
            .navigationTitle(viewModel.currentRoot?.name ?? String(localized: "Icicle View"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
    #endif

    // MARK: - Components
    private func mapPanel(showBreadcrumbOverlay: Bool = true) -> some View {
        ZStack {
            if let current = viewModel.currentRoot {
                IcicleChartView(
                    root: current,
                    selectedNode: viewModel.selectedNode,
                    allowContextMenu: viewModel.isLiveScan,
                    onSelect: { node in
                        if node.type == .folder {
                            viewModel.zoomIn(to: node)
                        } else {
                            viewModel.select(node: node)
                        }
                    }
                )
                .onTapGesture(count: 2) {
                    if let selected = viewModel.selectedNode {
                        viewModel.zoomIn(to: selected)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showBreadcrumbOverlay {
                        breadcrumbBar
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(8)
                    }
                }
            } else {
                #if os(macOS)
                VStack(spacing: 16) {
                    Text("No folder selected")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Select Object to Scan") {
                        selectFolderAndScan()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .disabled(viewModel.isScanning)
                }
                #else
                Text("Scan to view")
                    .foregroundStyle(.secondary)
                #endif
            }

            if viewModel.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning files…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    
                    Button {
                        viewModel.cancelScan()
                    } label: {
                        Text("Cancel")
                            .frame(width: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor)) // Chart background color
        #else
        .background(Color(UIColor.systemGroupedBackground))
        #endif
        .clipShape(Rectangle()) // Ensure content does not overflow
    }

    private func sidebar(showingHeader: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingHeader {
                HStack {
                    Text("Disk Usage")
                        .font(.headline)
                    Spacer()
                    Button("Upper Level") {
                        viewModel.stepUp()
                    }
                    .disabled(viewModel.breadcrumb.count <= 1)

                    Button("Scan") {
                        showingRescanConfirmation = true
                    }
                    .padding(.leading, 8)
                    .disabled(viewModel.isScanning)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            // Selected node details
            if let selected = viewModel.selectedNode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(selected.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                    Text(byteString(selected.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            } else {
                Text("Tap item to view info")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            Divider()
                .padding(.horizontal, 16)

            // File list
            List {
                if let current = viewModel.currentRoot, let children = current.children {
                    // Children are pre-sorted by size during scanning
                    ForEach(children) { node in
                        Button {
                            viewModel.zoomIn(to: node)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(node.color)
                                    .frame(width: 10, height: 10)
                                Text(node.name)
                                    .lineLimit(1)
                                Spacer()
                                Text(byteString(node.size))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if node.type == .folder {
                                    Image(systemName: "chevron.forward")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("Nothing to display")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor)) // List background
        #else
        .background(Color(UIColor.systemBackground)) // List background
        #endif
    }

    private var sidebarList: some View {
        List {
            Section(header: Text("Info")) {
                if let selected = viewModel.selectedNode {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: selected.type == .folder ? "folder.fill" : fileIcon(for: selected.name))
                                .foregroundStyle(.primary)
                                .font(.title3)
                            Text(selected.name)
                                .font(.headline)
                        }
                        Text(selected.path)
                            .font(.caption)
                            .lineLimit(nil)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            Text(byteString(selected.size))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let parent = viewModel.currentRoot, parent.size > 0 {
                                let pct = Double(selected.size) / Double(parent.size)
                                Text(pct.formatted(.percent.precision(.fractionLength(1))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Select an item to view details")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }

            Section(header: Text("Contents")) {
                // Back / Up button
                Button {
                    viewModel.stepUp()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.gray)
                        if let breadcrumb = viewModel.breadcrumb.dropLast().last {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(breadcrumb.name)
                                .lineLimit(1)
                        } else {
                            Text("Upper directory")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .disabled(viewModel.breadcrumb.count <= 1)

                if let current = viewModel.currentRoot, let children = current.children {
                    ForEach(children) { node in
                        Button {
                            viewModel.zoomIn(to: node)
                        } label: {
                            HStack(spacing: 8) {
                                // Color dot
                                Circle()
                                    .fill(node.color)
                                    .frame(width: 10, height: 10)
                                // Type icon
                                Image(systemName: node.type == .folder ? "folder.fill" : fileIcon(for: node.name))
                                    .font(.caption)
                                    .foregroundStyle(node.type == .folder ? .gray : .secondary)
                                    .frame(width: 16)
                                // Name
                                Text(node.name)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Spacer()
                                // Size
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(byteString(node.size))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                // Chevron for folders
                                if node.type == .folder {
                                    Image(systemName: "chevron.forward")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        #else
                        .tint(.primary)
                        #endif
                    }
                } else {
                    Label("Empty directory", systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    /// Returns an appropriate SF Symbol name based on file extension
    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "m4v":
            return "film"
        case "mp3", "aac", "wav", "flac", "m4a", "ogg", "wma":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz", "dmg":
            return "doc.zipper"
        case "txt", "md", "rtf", "log", "csv":
            return "doc.text"
        case "swift", "py", "js", "ts", "c", "cpp", "h", "java", "rb", "go", "rs", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css", "xml", "json", "yaml", "yml":
            return "globe"
        case "app", "exe", "bin":
            return "app"
        case "framework", "dylib", "so":
            return "shippingbox"
        default:
            return "doc"
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { // Slightly increased spacing
                ForEach(viewModel.breadcrumb) { node in
                    Button {
                        viewModel.zoomIn(to: node)
                    } label: {
                        HStack(spacing: 4) {
                            if node.id == viewModel.rootNode?.id {
                                Image(systemName: "externaldrive.fill")
                                    .font(.caption)
                            } else {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                            }
                            Text(node.name)
                                .font(.subheadline) // Slightly larger font
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                        .contentShape(Rectangle()) // Ensure entire area is tappable
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    #else
                    .tint(.primary)
                    #endif
                }
            }
            .padding(.horizontal, 4) // Add some padding inside the scroll view
        }
        .frame(height: 44) // Ensure minimum touch target height
        .zIndex(1) // Ensure it stays on top
    }

    private func byteString(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

#Preview("中文") {
    ContentView()
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("English") {
    ContentView()
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("日本語") {
    ContentView()
        .environment(\.locale, Locale(identifier: "ja"))
}
