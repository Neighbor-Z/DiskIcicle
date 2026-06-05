import SwiftUI

#if os(macOS)
import AppKit
#endif

struct IcicleChartView: View {
    let root: FileNode
    let selectedNode: FileNode?
    let allowContextMenu: Bool
    let onSelect: (FileNode) -> Void

    private let columnWidth: CGFloat = 140
    private let minLabelHeight: CGFloat = 14
    private let minScale: CGFloat = 0.4
    /// Minimum pixel height for a child item to be individually drawn (not collapsed into gray placeholder)
    private let minChildPixelHeight: CGFloat = 2.0
    /// Target pixel height for the smallest child at maximum zoom
    private let targetSmallestChildHeight: CGFloat = 80.0

    @Environment(\.colorScheme) private var colorScheme

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var contentSize: CGSize = .zero
    @State private var viewportHeight: CGFloat = 600
    @State private var contextMenuNode: FileNode?

    /// Dynamically computed max scale based on the root's children.
    /// At max scale, the smallest child should have `targetSmallestChildHeight` pixel height.
    private var dynamicMaxScale: CGFloat {
        guard let children = root.children, !children.isEmpty else { return 16.0 }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return 16.0 }

        let smallestSize = children.map(\.size).min() ?? 1
        let smallestRatio = CGFloat(smallestSize) / CGFloat(total)
        // At scale S: smallestPixelHeight = viewportHeight * smallestRatio * S
        // We want: viewportHeight * smallestRatio * S = targetSmallestChildHeight
        // So: S = targetSmallestChildHeight / (viewportHeight * smallestRatio)
        let computed = targetSmallestChildHeight / (viewportHeight * smallestRatio)
        // Clamp to a reasonable range
        return max(1.0, min(computed, 2000.0))
    }

    var body: some View {
        GeometryReader { proxy in
            let viewport = CGRect(origin: .zero, size: proxy.size)
            let maxScale = dynamicMaxScale

            ZStack(alignment: .topLeading) {
                IcicleCanvasLayer(
                    root: root,
                    selectedNodeID: selectedNode?.id,
                    offset: offset,
                    scale: scale,
                    minChildPixelHeight: minChildPixelHeight,
                    isDarkMode: colorScheme == .dark
                )
                .equatable()
                .drawingGroup()

                PanZoomGestureView(
                    onPan: { translation in
                        offset = CGSize(
                            width: lastOffset.width + translation.x,
                            height: lastOffset.height + translation.y
                        )
                    },
                    onPanEnded: {
                        adjustOffsetIfNeeded(viewport: viewport)
                        lastOffset = offset
                    },
                    onPinch: { gestureScale, location in
                        let newScale = max(minScale, min(maxScale, lastScale * gestureScale))
                        let scaleRatio = newScale / scale
                        let pivot = CGPoint(x: location.x, y: location.y)
                        // The chart only scales vertically. Horizontal scale is always 1.0.
                        
                        let newOffsetX = offset.width
                        let newOffsetY = pivot.y - (pivot.y - offset.height) * scaleRatio

                        offset = CGSize(width: newOffsetX, height: newOffsetY)
                        scale = newScale
                    },
                    onPinchEnded: {
                        lastScale = scale
                        adjustOffsetIfNeeded(viewport: viewport)
                        lastOffset = offset
                    },
                    onTap: { location in
                        let hit = hitTest(
                            node: root,
                            x: 0,
                            y: 0,
                            height: proxy.size.height,
                            location: location,
                            scale: scale,
                            offset: offset
                        )
                        if let hit {
                            onSelect(hit)
                        }
                    },
                    onSecondaryTap: { location in
                        let hit = hitTest(
                            node: root,
                            x: 0,
                            y: 0,
                            height: proxy.size.height,
                            location: location,
                            scale: scale,
                            offset: offset
                        )
                        contextMenuNode = hit
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .clipped()
            .onAppear {
                viewportHeight = proxy.size.height
                contentSize = CGSize(width: columnWidth * CGFloat(depth(of: root) + 1), height: proxy.size.height)
            }
            .onChange(of: root.id) { _ in
                viewportHeight = proxy.size.height
                contentSize = CGSize(width: columnWidth * CGFloat(depth(of: root) + 1), height: proxy.size.height)
                // Reset scale when switching directories
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
            .onChange(of: proxy.size.height) { newHeight in
                viewportHeight = newHeight
                contentSize = CGSize(width: contentSize.width, height: newHeight)
            }
            .contextMenu {
                if allowContextMenu, let node = contextMenuNode {
                    Button {
                        revealInFinder(url: node.url)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            }
        }
    }

    private func revealInFinder(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        #endif
    }

    private func hitTest(
        node: FileNode,
        x: CGFloat,
        y: CGFloat,
        height: CGFloat,
        location: CGPoint,
        scale: CGFloat,
        offset: CGSize
    ) -> FileNode? {
        let rect = CGRect(
            x: x + offset.width,
            y: y * scale + offset.height,
            width: columnWidth,
            height: height * scale
        )

        // Check vertical bounds first. Children are constrained vertically within parent.
        if location.y < rect.minY || location.y > rect.maxY {
            return nil
        }

        // 1. Try children first (they are drawn on top/next to parent)
        if let children = node.children, !children.isEmpty {
            let total = children.reduce(Int64(0)) { $0 + $1.size }
            if total > 0 {
                var currentY = y
                for child in children {
                    let ratio = CGFloat(child.size) / CGFloat(total)
                    let childHeight = height * ratio

                    let scaledChildHeight = childHeight * scale
                    if scaledChildHeight >= minChildPixelHeight {
                        if let hit = hitTest(
                            node: child,
                            x: x + columnWidth,
                            y: currentY,
                            height: childHeight,
                            location: location,
                            scale: scale,
                            offset: offset
                        ) {
                            return hit
                        }
                    }

                    currentY += childHeight
                }
            }
        }

        // 2. If no child hit, check if we hit this node itself
        if rect.contains(location) {
            return node
        }

        return nil
    }

    private func depth(of node: FileNode) -> Int {
        guard let children = node.children, !children.isEmpty else { return 0 }
        return 1 + (children.map { depth(of: $0) }.max() ?? 0)
    }

    private func adjustOffsetIfNeeded(viewport: CGRect) {
        let contentRect = CGRect(
            x: offset.width,
            y: offset.height,
            width: contentSize.width,
            height: contentSize.height * scale
        )

        let intersection = contentRect.intersection(viewport)
        if intersection.isNull || intersection.width <= 0 || intersection.height <= 0 {
            let viewportArea = viewport.width * viewport.height
            let contentArea = contentRect.width * contentRect.height
            let targetArea = min(viewportArea * 0.75, contentArea)

            let maxOverlapWidth = min(viewport.width, contentRect.width)
            let maxOverlapHeight = min(viewport.height, contentRect.height)
            if maxOverlapWidth <= 0 || maxOverlapHeight <= 0 { return }

            var reqW = maxOverlapWidth
            var reqH = targetArea / reqW
            if reqH > maxOverlapHeight {
                reqH = maxOverlapHeight
                reqW = min(maxOverlapWidth, targetArea / reqH)
            }

            let dx = minimalShift(
                contentMin: contentRect.minX,
                contentMax: contentRect.maxX,
                viewportMin: viewport.minX,
                viewportMax: viewport.maxX,
                requiredOverlap: reqW
            )

            let dy = minimalShift(
                contentMin: contentRect.minY,
                contentMax: contentRect.maxY,
                viewportMin: viewport.minY,
                viewportMax: viewport.maxY,
                requiredOverlap: reqH
            )

            offset = CGSize(width: offset.width + dx, height: offset.height + dy)
        }
    }

    private func minimalShift(
        contentMin: CGFloat,
        contentMax: CGFloat,
        viewportMin: CGFloat,
        viewportMax: CGFloat,
        requiredOverlap: CGFloat
    ) -> CGFloat {
        if contentMax < viewportMin {
            let dReq = viewportMin + requiredOverlap - contentMax
            let dMax = viewportMax - contentMax
            return min(dReq, dMax)
        }
        if contentMin > viewportMax {
            let dReq = viewportMax - requiredOverlap - contentMin
            let dMin = viewportMin - contentMin
            return max(dReq, dMin)
        }
        return 0
    }

    // MARK: - Renderer Layer (Isolated)
    // The renderer is nested and deliberately holds only the data necessary for drawing.
    struct IcicleCanvasLayer: View, Equatable {
        let root: FileNode
        let selectedNodeID: UUID?
        let offset: CGSize
        let scale: CGFloat
        let minChildPixelHeight: CGFloat
        let isDarkMode: Bool

        // These are purely drawing constants and are NOT part of the Equatable state.
        private let columnWidth: CGFloat = 140
        private let minLabelHeight: CGFloat = 14
        /// Color for the placeholder block representing collapsed small items
        private let placeholderColor = Color.gray.opacity(0.35)

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.offset == rhs.offset &&
            lhs.scale == rhs.scale &&
            lhs.root.id == rhs.root.id &&
            lhs.selectedNodeID == rhs.selectedNodeID &&
            lhs.isDarkMode == rhs.isDarkMode
        }

        var body: some View {
            Canvas { context, size in
                let baseRect = CGRect(origin: .zero, size: size)
                let visible = baseRect

                drawNode(
                    node: root,
                    selectedNodeID: selectedNodeID,
                    x: 0,
                    y: 0,
                    height: size.height,
                    scale: scale,
                    offset: offset,
                    visible: visible,
                    isDarkMode: isDarkMode,
                    context: context
                )
            }
            .allowsHitTesting(false)
        }

        private func drawNode(
            node: FileNode,
            selectedNodeID: UUID?,
            x: CGFloat,
            y: CGFloat,
            height: CGFloat,
            scale: CGFloat,
            offset: CGSize,
            visible: CGRect,
            isDarkMode: Bool,
            context: GraphicsContext
        ) {
            let rect = CGRect(
                x: x + offset.width,
                y: y * scale + offset.height,
                width: columnWidth,
                height: height * scale
            )

            // 1. Strict Culling for Performance
            // If the node is completely outside the viewport vertically, we can skip it AND its children
            // because children are vertically constrained within the parent's height in this layout.
            if rect.maxY < visible.minY || rect.minY > visible.maxY {
                return
            }
            
            // If the node is completely to the right of the viewport, skip it and its children (which flow right).
            if rect.minX > visible.maxX {
                return
            }

            // 2. Drawing - Only draw if this specific node is visible
            if rect.intersects(visible) {
                let nodeFill = isDarkMode ? node.color.opacity(0.65) : node.color
                context.fill(Path(rect), with: .color(nodeFill))
                
                if node.id == selectedNodeID {
                    // Thicker highlight border for selected node
                    let strokeColor: Color = isDarkMode ? .white : .black
                    context.stroke(Path(rect), with: .color(strokeColor), lineWidth: 2)
                } else {
                    let strokeColor: Color = isDarkMode ? .white.opacity(0.4) : .black.opacity(0.2)
                    context.stroke(Path(rect), with: .color(strokeColor), lineWidth: 1)
                }

                // 3. Constant Font Size
                let fontSize: CGFloat = 11
                
                let minHeightForText = max(minLabelHeight, fontSize * 1.1)

                if rect.height >= minHeightForText {
                    let sizeText = ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
                    let label = Text("\(node.name)\n\(sizeText)")
                        .font(.system(size: fontSize, weight: .semibold))

                    let textRect = rect.insetBy(dx: 6, dy: 4)
                    context.draw(label, in: textRect)
                }
            }

            // 4. Draw Children
            guard let children = node.children, !children.isEmpty, height > 1 else { return }

            let total = children.reduce(Int64(0)) { $0 + $1.size }
            if total <= 0 { return }

            let childX = x + columnWidth

            // Separate children into visible (drawn individually) and collapsed (too small)
            var currentY = y
            var collapsedRanges: [(startY: CGFloat, endY: CGFloat, totalSize: Int64)] = []
            var currentCollapsedStartY: CGFloat? = nil
            var currentCollapsedSize: Int64 = 0

            for child in children {
                let ratio = CGFloat(child.size) / CGFloat(total)
                let childHeight = height * ratio
                let scaledChildHeight = childHeight * scale

                if scaledChildHeight >= minChildPixelHeight {
                    // If we were accumulating collapsed items, close that range
                    if let collapsedStart = currentCollapsedStartY {
                        collapsedRanges.append((startY: collapsedStart, endY: currentY, totalSize: currentCollapsedSize))
                        currentCollapsedStartY = nil
                        currentCollapsedSize = 0
                    }

                    drawNode(
                        node: child,
                        selectedNodeID: selectedNodeID,
                        x: childX,
                        y: currentY,
                        height: childHeight,
                        scale: scale,
                        offset: offset,
                        visible: visible,
                        isDarkMode: isDarkMode,
                        context: context
                    )
                } else {
                    // This child is too small - start or continue a collapsed range
                    if currentCollapsedStartY == nil {
                        currentCollapsedStartY = currentY
                    }
                    currentCollapsedSize += child.size
                }

                currentY += childHeight
            }

            // Close any trailing collapsed range
            if let collapsedStart = currentCollapsedStartY {
                collapsedRanges.append((startY: collapsedStart, endY: currentY, totalSize: currentCollapsedSize))
            }

            // Draw gray placeholder blocks for collapsed ranges
            let placeholderFontSize: CGFloat = 10
            for range in collapsedRanges {
                let rangeHeight = range.endY - range.startY
                let placeholderRect = CGRect(
                    x: childX + offset.width,
                    y: range.startY * scale + offset.height,
                    width: columnWidth,
                    height: rangeHeight * scale
                )

                if placeholderRect.intersects(visible) && placeholderRect.height >= 1 {
                    let placeholderFill = isDarkMode ? placeholderColor.opacity(0.65) : placeholderColor
                    context.fill(Path(placeholderRect), with: .color(placeholderFill))
                    let strokeColor: Color = isDarkMode ? .white.opacity(0.3) : .black.opacity(0.1)
                    context.stroke(Path(placeholderRect), with: .color(strokeColor), lineWidth: 0.5)

                    // Draw "Other" label with total size if there's enough room
                    if placeholderRect.height >= minLabelHeight {
                        let sizeText = ByteCountFormatter.string(fromByteCount: range.totalSize, countStyle: .file)
                        let label = Text("Other\n\(sizeText)")
                            .font(.system(size: placeholderFontSize, weight: .medium))
                            // .foregroundColor(isDarkMode ? .white : .black.opacity(0.8))
                        let textRect = placeholderRect.insetBy(dx: 6, dy: 2)
                        context.draw(label, in: textRect)
                    }
                }
            }
        }
    }
}
