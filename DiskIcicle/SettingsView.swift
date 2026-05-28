import SwiftUI
import UniformTypeIdentifiers

class SettingsViewModel: ObservableObject {
    @Published var excludedPaths: [String] {
        didSet {
            UserDefaults.standard.set(excludedPaths, forKey: "userExcludedPaths")
        }
    }
    init() {
        self.excludedPaths = UserDefaults.standard.stringArray(forKey: "userExcludedPaths") ?? []
    }
    
    func remove(at offsets: IndexSet) {
        excludedPaths.remove(atOffsets: offsets)
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingFileImporter = false
    
    var body: some View {
        #if os(macOS)
        Form {
            Section(header: Text("Excluded Directories").font(.headline)) {
                Text("Select directories to exclude from disk scans. (Live scan only)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(viewModel.excludedPaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(action: {
                                if let idx = viewModel.excludedPaths.firstIndex(of: path) {
                                    viewModel.excludedPaths.remove(at: idx)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: viewModel.remove)
                }
                .frame(minHeight: 150)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                HStack {
                    Spacer()
                    Button("Add Directory...") {
                        showingFileImporter = true
                    }
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: true
                    ) { result in
                        switch result {
                        case .success(let urls):
                            for url in urls {
                                let path = url.path
                                if !viewModel.excludedPaths.contains(path) {
                                    viewModel.excludedPaths.append(path)
                                }
                            }
                        case .failure(let error):
                            print("Error selecting folder: \(error.localizedDescription)")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        #endif
    }
}
