//
//  WorkspaceGridView.swift
//  Nidus
//
//  The 5×2 modular grid substrate (Blueprint §3.2, GUI workspace §6). Fixed 5 columns × 2 rows,
//  never scrolls. In Customize Mode (§8) empty cells become "+" add slots and tiles show a
//  remove control (except Inbox). Resize/reorder are Tramo 3.
//

import SwiftUI

/// A rectangular region of the grid (a tool's footprint, or an empty area).
struct GridArea: Identifiable {
    let col: Int
    let row: Int
    let cols: Int
    let rows: Int
    var id: String { "\(col),\(row)" }
}

struct WorkspaceGridView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    let slots: [ToolSlot]
    let projectRef: ProjectRef
    var isEditing: Bool = false
    var highlightedTool: String?
    var onAdd: (GridArea) -> Void = { _ in }
    var onRemove: (ToolSlot) -> Void = { _ in }
    var onRename: (ToolSlot) -> Void = { _ in }
    /// Called with a new grid when a tile is moved (drag) — to persist.
    var onCommitGrid: ([ToolSlot]) -> Void = { _ in }
    /// Cap on a single cell's height so tall windows don't stretch tiles absurdly long;
    /// the grid then top-aligns, leaving breathing room (bottom padding) below.
    var maxCellHeight: CGFloat = 300

    static let columns = 5
    static let rows = 2
    private let gap: CGFloat = 14

    @State private var dragID: String?
    @State private var dragTranslation: CGSize = .zero
    @State private var swapHintID: String?
    @State private var dragMorphSize: ToolSize?   // target shape the dragged tile is morphing toward
    @State private var reflowGhost: [String: [Int]]?  // id → [col,row] preview origin (neighbors shifting)
    @State private var hoverToken: String?        // current hover target (swap:id / reflow:cc,cr)
    @State private var hoverWork: DispatchWorkItem?
    @State private var lastCell: [Int]?           // last cursor cell (for the magnetic haptic)
    @State private var resizeMenuSlotID: String?
    @State private var levitateKick = 0

    private let space = "nidusGrid"
    /// How far the dragged tile morphs toward the target shape while hovering (a soft hint, not
    /// the final shape). The rest completes on drop.
    private let morphFraction: CGFloat = 0.2
    /// Dwell time before the hover reaction kicks in, so you can sweep over tiles freely.
    private let hoverDelay: TimeInterval = 0.3

    var body: some View {
        GeometryReader { proxy in
            let cellW = (proxy.size.width - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            let rawCellH = (proxy.size.height - gap * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
            let cellH = min(rawCellH, maxCellHeight)
            let folderURL = model.projectFolderURL(projectRef)

            ZStack(alignment: .topLeading) {
                ForEach(emptyAreas) { area in
                    PlaceholderCell(area: area, isEditing: isEditing, onAdd: onAdd)
                        .frame(width: span(cellW, area.cols), height: span(cellH, area.rows))
                        .offset(x: CGFloat(area.col) * (cellW + gap),
                                y: CGFloat(area.row) * (cellH + gap))
                        .animation(.easeOut(duration: 0.2), value: dragID)
                }

                ForEach(visibleSlots) { slot in
                    tile(slot, cellW: cellW, cellH: cellH, folderURL: folderURL)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(.named(space))
        }
    }

    @ViewBuilder
    private func tile(_ slot: ToolSlot, cellW: CGFloat, cellH: CGFloat, folderURL: URL?) -> some View {
        let descriptor = ToolRegistry.descriptor(for: slot.tool)
        let resolved = slot.files ?? descriptor.files
        let fileMap = Dictionary(uniqueKeysWithValues: zip(descriptor.files, resolved))
        let isDragging = dragID == slot.id
        let resizable = descriptor.validSizes.count > 1
        let base = CGSize(width: CGFloat(slot.col) * (cellW + gap),
                          height: CGFloat(slot.row) * (cellH + gap))
        let size = slot.toolSize
        let isSwapHint = swapHintID == slot.id
        // Soft morphism: while dragging over a different-size partner (after the hover delay), the
        // tile interpolates a fraction of the way toward the target shape — a living intermediate,
        // not the final size. It finishes morphing on drop.
        let morphing = isDragging && dragMorphSize != nil
        let target = (isDragging ? dragMorphSize : nil) ?? size
        let f = morphing ? morphFraction : 0
        let w = span(cellW, size.columns) + (span(cellW, target.columns) - span(cellW, size.columns)) * f
        let h = span(cellH, size.rows) + (span(cellH, target.rows) - span(cellH, size.rows)) * f
        // Reflow amago: a neighbour that would shift to make room previews a fraction of the move.
        let ghost: CGSize = {
            guard !isDragging, let g = reflowGhost, let t = g[slot.id] else { return .zero }
            return CGSize(width: CGFloat(t[0] - slot.col) * (cellW + gap) * morphFraction,
                          height: CGFloat(t[1] - slot.row) * (cellH + gap) * morphFraction)
        }()

        ToolTileView(
            slot: slot,
            context: ToolContext(size: size, projectRef: projectRef,
                                 folderURL: folderURL, fileMap: fileMap,
                                 name: slot.name ?? descriptor.defaultName, slotID: slot.id),
            isEditing: isEditing,
            highlighted: slot.tool == highlightedTool,
            levitateKick: levitateKick,
            onRemove: { onRemove(slot) },
            onRename: { onRename(slot) },
            // The header opens the tool's library/expanded: Notebook, or any installed tool with one.
            onTitleTap: titleTapAction(slot)
        )
        .frame(width: w, height: h)
        .overlay(alignment: .bottomTrailing) {
            if isEditing && resizable {
                resizeControl(slot, descriptor: descriptor)
            }
        }
        .scaleEffect(isDragging ? 1.04 : (isSwapHint ? 0.93 : 1))
        .opacity(isSwapHint ? 0.55 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: 18, y: 8)
        .offset(x: base.width + (isDragging ? dragTranslation.width : 0) + ghost.width,
                y: base.height + (isDragging ? dragTranslation.height : 0) + ghost.height)
        .zIndex(isDragging || resizeMenuSlotID == slot.id ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: dragMorphSize)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: ghost)
        .animation(.easeOut(duration: 0.2), value: isSwapHint)
        // Keep the gesture live for the tile currently being dragged even if edit mode is toggled
        // off mid-move — otherwise the drag is cancelled with no `onEnded` and the tile freezes
        // mid-flight. It reverts to `.subviews` once the drag has settled (dragID cleared).
        .gesture(dragGesture(slot, cellW: cellW, cellH: cellH),
                 including: (isEditing || isDragging) ? .all : .subviews)
    }

    /// What the tile's title/icon header does: Notebook opens its library; an installed tool with an
    /// expanded view opens that; others do nothing.
    private func titleTapAction(_ slot: ToolSlot) -> (() -> Void)? {
        if slot.tool == NotebookToolView.descriptor.id { return { openNotebookLibrary(slot) } }
        if let tool = model.installedTools.first(where: { $0.id == slot.tool }), tool.source.contains("expanded") {
            return { openInstalledExpanded(tool, slot: slot) }
        }
        return nil
    }

    private func openInstalledExpanded(_ tool: InstalledTool, slot: ToolSlot) {
        let folder = model.projectFolderURL(projectRef)
        let file = (slot.files?.first ?? tool.manifest.store.first).flatMap { folder?.appendingPathComponent($0) }
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                InstalledToolExpandedView(tool: tool, primaryFile: file, folderURL: folder,
                                          size: slot.toolSize.rawValue) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    /// Opens the Notebook library (browse view) from the tile's header tap.
    private func openNotebookLibrary(_ slot: ToolSlot) {
        let folder = model.projectFolderURL(projectRef)
        let name = slot.name ?? NotebookToolView.descriptor.defaultName
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                NotebookLibraryView(projectFolder: folder, toolName: name) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    // MARK: - Resize via a size picker (no fluid drag — pick from the available shapes)

    @ViewBuilder
    private func resizeControl(_ slot: ToolSlot, descriptor: ToolDescriptor) -> some View {
        let open = resizeMenuSlotID == slot.id
        VStack(alignment: .trailing, spacing: 8) {
            if open { sizeMenu(slot, descriptor: descriptor) }
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    resizeMenuSlotID = open ? nil : slot.id
                }
            } label: {
                Image(systemName: "square.resize")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(open ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .nidusGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .help("Resize")
        }
        .padding(8)
    }

    private func sizeMenu(_ slot: ToolSlot, descriptor: ToolDescriptor) -> some View {
        let available = ToolSize.allCases.filter {
            descriptor.validSizes.contains($0) && resized(slot.id, to: $0) != nil
        }
        return HStack(spacing: 10) {
            ForEach(available, id: \.self) { sizeOption in
                Button { pickSize(slot, sizeOption) } label: {
                    shapeGlyph(sizeOption, selected: sizeOption == slot.toolSize)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .nidusGlass(Capsule())
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
    }

    /// A little shape that represents a size (square / wide / tall / big square).
    private func shapeGlyph(_ size: ToolSize, selected: Bool) -> some View {
        let unit: CGFloat = 9, gap2: CGFloat = 3
        let w = unit * CGFloat(size.columns) + (size.columns > 1 ? gap2 : 0)
        let h = unit * CGFloat(size.rows) + (size.rows > 1 ? gap2 : 0)
        return RoundedRectangle(cornerRadius: 3)
            .fill(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(width: w, height: h)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    private func pickSize(_ slot: ToolSlot, _ size: ToolSize) {
        if let grid = resized(slot.id, to: size) {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { onCommitGrid(grid) }
            levitateKick += 1
        }
        withAnimation(.easeOut(duration: 0.2)) { resizeMenuSlotID = nil }
    }

    /// New grid with `slotID` resized. Grows into contiguous empty space in any direction, with
    /// weights: prefer keeping the origin (grow right/down); shift left/up only if that's the
    /// only space available. Nil if it doesn't fit anywhere.
    private func resized(_ slotID: String, to size: ToolSize) -> [ToolSlot]? {
        guard let i = slots.firstIndex(where: { $0.id == slotID }) else { return nil }
        let s = slots[i]
        let cur = s.toolSize
        let occupied = slots.filter { $0.id != slotID }
            .reduce(into: Set<[Int]>()) { $0.formUnion(cells(for: $1)) }

        let extraCols = size.columns - cur.columns
        let extraRows = size.rows - cur.rows
        // Right edge of the tile if it shrank while keeping its current right side.
        let rightAnchored = s.col + cur.columns - size.columns
        let bottomAnchored = s.row + cur.rows - size.rows

        // GROW: keep origin (grow right/down), fall back to shifting left/up. Left/up weighted.
        // SHRINK: anchor to the tile's NATURAL corner — a tile against the right edge tends right,
        //         against the left edge tends left; interior keeps its left/top origin.
        let colOptions: [Int]
        if extraCols > 0 {
            colOptions = [s.col, s.col - extraCols]
        } else if extraCols < 0 {
            let touchesRight = s.col + cur.columns == Self.columns
            let touchesLeft = s.col == 0
            colOptions = (touchesRight && !touchesLeft) ? [rightAnchored, s.col] : [s.col, rightAnchored]
        } else {
            colOptions = [s.col]
        }

        let rowOptions: [Int]
        if extraRows > 0 {
            rowOptions = [s.row, s.row - extraRows]
        } else if extraRows < 0 {
            let touchesBottom = s.row + cur.rows == Self.rows
            let touchesTop = s.row == 0
            rowOptions = (touchesBottom && !touchesTop) ? [bottomAnchored, s.row] : [s.row, bottomAnchored]
        } else {
            rowOptions = [s.row]
        }

        for c in colOptions {
            for r in rowOptions {
                guard c >= 0, r >= 0,
                      c + size.columns <= Self.columns, r + size.rows <= Self.rows else { continue }
                if cells(col: c, row: r, size: size).isDisjoint(with: occupied) {
                    var grid = slots
                    grid[i].col = c; grid[i].row = r; grid[i].size = size.rawValue
                    return grid
                }
            }
        }
        return nil
    }

    private func dragGesture(_ slot: ToolSlot, cellW: CGFloat, cellH: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .named(space))
            .onChanged { value in
                dragID = slot.id
                dragTranslation = value.translation
                // Detection by the cursor RECTANGLE: any point over the tile counts (fixes the
                // "doesn't register until I reach a part of it" with small→large).
                let (cc, cr) = cursorCell(value.location, cellW: cellW, cellH: cellH)
                let cell = [cc, cr]
                let stepX = cellW + gap, stepY = cellH + gap
                let tc = slot.col + Int((value.translation.width / stepX).rounded())
                let tr = slot.row + Int((value.translation.height / stepY).rounded())
                // Swap wins; otherwise a reflow that opens room for the full size.
                let partner = swapPartnerAt(slot, point: value.location, cellW: cellW, cellH: cellH)
                let reflow = partner == nil ? reflowPlacement(slot, toCol: tc, toRow: tr) : nil

                // Magnetic haptic the moment you enter a NEW valid target cell.
                if cell != lastCell {
                    lastCell = cell
                    let valid = partner != nil || reflow != nil
                        || movePlacement(slot.id, toCol: cc, toRow: cr) != nil
                        || shrinkToFit(slot, toCol: cc, toRow: cr) != nil
                    if valid { Haptics.tap() }
                }

                // Token identifies the current target so we only re-arm when it changes.
                let token: String? = partner.map { "swap:\($0.id)" }
                    ?? reflow.map { "reflow:\($0.origin[0]),\($0.origin[1])" }
                if hoverToken != token {
                    hoverToken = token
                    hoverWork?.cancel()
                    // Nothing happens on mere hover: relax any current reaction while we wait.
                    if swapHintID != nil || dragMorphSize != nil || reflowGhost != nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            swapHintID = nil; dragMorphSize = nil; reflowGhost = nil
                        }
                    }
                    if token != nil {
                        let work = DispatchWorkItem {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                if let p = partner {
                                    swapHintID = p.id
                                    dragMorphSize = p.toolSize != slot.toolSize ? p.toolSize : nil
                                } else if let rf = reflow {
                                    reflowGhost = Dictionary(uniqueKeysWithValues:
                                        rf.moved.compactMap { id in
                                            rf.grid.first { $0.id == id }.map { (id, [$0.col, $0.row]) }
                                        })
                                }
                            }
                        }
                        hoverWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: work)
                    }
                }
            }
            .onEnded { value in
                hoverWork?.cancel()
                hoverToken = nil
                lastCell = nil
                withAnimation(.easeOut(duration: 0.16)) { swapHintID = nil }
                endDrag(slot, translation: value.translation, location: value.location,
                        cellW: cellW, cellH: cellH)
            }
    }

    private func endDrag(_ slot: ToolSlot, translation: CGSize, location: CGPoint,
                         cellW: CGFloat, cellH: CGFloat) {
        let stepX = cellW + gap, stepY = cellH + gap
        let dCol = Int((translation.width / stepX).rounded())
        let dRow = Int((translation.height / stepY).rounded())
        let (cc, cr) = cursorCell(location, cellW: cellW, cellH: cellH)

        // 1. Plain move into empty space (translation-based target keeps the grab feel).
        if (dCol != 0 || dRow != 0),
           let grid = movePlacement(slot.id, toCol: slot.col + dCol, toRow: slot.row + dRow) {
            commitSlide(grid, dx: CGFloat(dCol) * stepX, dy: CGFloat(dRow) * stepY, slotID: slot.id)
            return
        }
        // 2. Swap with the tile under the cursor (sizes swap too when both tools allow it).
        if let b = swapPartnerAt(slot, point: location, cellW: cellW, cellH: cellH),
           let (grid, partner) = swapPlacement(slot, with: b) {
            commitSlide(grid, dx: CGFloat(partner.col - slot.col) * stepX,
                        dy: CGFloat(partner.row - slot.row) * stepY, slotID: slot.id)
            return
        }
        // 3. Reflow (no cascade): slide only the directly-covered neighbour out of the way.
        if let rf = reflowPlacement(slot, toCol: slot.col + dCol, toRow: slot.row + dRow) {
            commitSlide(rf.grid, dx: CGFloat(rf.origin[0] - slot.col) * stepX,
                        dy: CGFloat(rf.origin[1] - slot.row) * stepY, slotID: slot.id)
            return
        }
        // 4. Nearest empty slot — calm fallback, nobody else moves.
        if let (grid, origin) = nearestEmptyPlacement(slot, toCol: slot.col + dCol, toRow: slot.row + dRow) {
            commitSlide(grid, dx: CGFloat(origin[0] - slot.col) * stepX,
                        dy: CGFloat(origin[1] - slot.row) * stepY, slotID: slot.id)
            return
        }
        // 5. Drop onto empty space that's too small for the current size → resize-to-fit the
        //    largest valid size that fits there, and place it (the resize is gradual on commit).
        if let (grid, oc, or) = shrinkToFitDetail(slot, toCol: cc, toRow: cr) {
            commitSlide(grid, dx: CGFloat(oc - slot.col) * stepX,
                        dy: CGFloat(or - slot.row) * stepY, slotID: slot.id)
            return
        }
        // 6. Invalid / no move — settle back smoothly to its original cell.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            dragTranslation = .zero
            dragMorphSize = nil
            reflowGhost = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if dragID == slot.id { dragID = nil }
        }
    }

    /// Slide the dragged tile to its final cell, then commit. On commit, base→new and
    /// translation→0 animate in sync so the dragged tile stays put, while neighbours (swap
    /// partner / reflowed tiles) spring to their new positions.
    private func commitSlide(_ grid: [ToolSlot], dx: CGFloat, dy: CGFloat, slotID: String) {
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            dragTranslation = CGSize(width: dx, height: dy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                onCommitGrid(grid)
                dragTranslation = .zero
                dragMorphSize = nil
                reflowGhost = nil
            }
            // End the drag once that animation has settled (keep dragID set meanwhile so the
            // translation term still applies and the tile doesn't jump).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if dragID == slotID { dragID = nil }
                levitateKick += 1
            }
        }
    }

    /// Largest valid size of the tool that fits in empty space covering (toCol,toRow), with the
    /// resulting top-left origin. Used to resize-to-fit on drop. Nil if nothing fits.
    private func shrinkToFitDetail(_ slot: ToolSlot, toCol: Int, toRow: Int)
        -> ([ToolSlot], Int, Int)? {
        guard let ai = slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        let desc = ToolRegistry.descriptor(for: slot.tool)
        let cc = max(0, min(toCol, Self.columns - 1))
        let cr = max(0, min(toRow, Self.rows - 1))
        // Only ever SHRINK to fit (or keep size) — dropping a tile must never grow it.
        let curArea = slot.toolSize.columns * slot.toolSize.rows
        let sizes = ToolSize.allCases
            .filter { desc.validSizes.contains($0) && $0.columns * $0.rows <= curArea }
            .sorted { $0.columns * $0.rows > $1.columns * $1.rows } // largest first
        for size in sizes {
            let oc = min(max(toCol, 0), Self.columns - size.columns)
            let or = min(max(toRow, 0), Self.rows - size.rows)
            let foot = cells(col: oc, row: or, size: size)
            guard foot.contains([cc, cr]) else { continue } // must land where you aimed
            if slots.allSatisfy({ $0.id == slot.id || cells(for: $0).isDisjoint(with: foot) }) {
                var grid = slots
                grid[ai].col = oc; grid[ai].row = or; grid[ai].size = size.rawValue
                return (grid, oc, or)
            }
        }
        return nil
    }

    /// Whether a resize-to-fit drop is possible at (toCol,toRow) — for the magnetic haptic.
    private func shrinkToFit(_ slot: ToolSlot, toCol: Int, toRow: Int) -> [ToolSlot]? {
        shrinkToFitDetail(slot, toCol: toCol, toRow: toRow)?.0
    }

    /// New grid with `slotID` moved into empty space at (toCol,toRow). Nil if it doesn't fit.
    private func movePlacement(_ slotID: String, toCol: Int, toRow: Int) -> [ToolSlot]? {
        guard let a = slots.first(where: { $0.id == slotID }),
              let ai = slots.firstIndex(where: { $0.id == slotID }) else { return nil }
        let sA = a.toolSize
        guard toCol >= 0, toRow >= 0,
              toCol + sA.columns <= Self.columns, toRow + sA.rows <= Self.rows else { return nil }
        let foot = cells(col: toCol, row: toRow, size: sA)
        guard slots.allSatisfy({ $0.id == slotID || cells(for: $0).isDisjoint(with: foot) })
        else { return nil }
        var grid = slots
        grid[ai].col = toCol; grid[ai].row = toRow
        return grid
    }

    /// The grid cell under a point in the grid's coordinate space, clamped to bounds.
    private func cursorCell(_ p: CGPoint, cellW: CGFloat, cellH: CGFloat) -> (Int, Int) {
        let c = Int((p.x / (cellW + gap)).rounded(.down))
        let r = Int((p.y / (cellH + gap)).rounded(.down))
        return (max(0, min(c, Self.columns - 1)), max(0, min(r, Self.rows - 1)))
    }

    /// The tile whose rectangle contains `point` (cursor as the boundary), excluding `id`.
    private func tile(at point: CGPoint, cellW: CGFloat, cellH: CGFloat, excluding id: String?) -> ToolSlot? {
        let stepX = cellW + gap, stepY = cellH + gap
        return slots.first { s in
            guard s.id != id else { return false }
            let x = CGFloat(s.col) * stepX, y = CGFloat(s.row) * stepY
            let w = span(cellW, s.toolSize.columns), h = span(cellH, s.toolSize.rows)
            return point.x >= x && point.x <= x + w && point.y >= y && point.y <= y + h
        }
    }

    /// The tile the cursor is over that `a` would swap with (same size, or different sizes each
    /// tool allows). Cursor-rectangle based — reacts the moment the pointer is over the tile.
    private func swapPartnerAt(_ a: ToolSlot, point: CGPoint, cellW: CGFloat, cellH: CGFloat) -> ToolSlot? {
        guard let b = tile(at: point, cellW: cellW, cellH: cellH, excluding: a.id) else { return nil }
        if a.toolSize == b.toolSize { return b }
        let aAllows = ToolRegistry.descriptor(for: a.tool).validSizes.contains(b.toolSize)
        let bAllows = ToolRegistry.descriptor(for: b.tool).validSizes.contains(a.toolSize)
        return (aAllows && bAllows) ? b : nil
    }

    /// Reflow WITHOUT cascade: drop `a` onto a tile and slide ONLY the directly-covered tiles into
    /// free space — tiles `a` doesn't touch never move, so one drop can't chain-react across the
    /// grid. Among the cells near the drop, picks the one that makes the displaced neighbour travel
    /// the LEAST (then `a` closest to the drop). Returns the new grid, `a`'s origin, moved tiles.
    /// Nil if no overlapping placement can shed its neighbours without a cascade.
    private func reflowPlacement(_ a: ToolSlot, toCol: Int, toRow: Int)
        -> (grid: [ToolSlot], origin: [Int], moved: Set<String>)? {
        let sA = a.toolSize
        let dropC = min(max(toCol, 0), Self.columns - sA.columns)
        let dropR = min(max(toRow, 0), Self.rows - sA.rows)
        let others = slots.filter { $0.id != a.id }

        var best: (origin: [Int], placement: [String: [Int]], cost: Int, move: Int, dist: Int)?
        for oc in 0...(Self.columns - sA.columns) {
            for or in 0...(Self.rows - sA.rows) {
                let aFoot = cells(col: oc, row: or, size: sA)
                let displaced = others.filter { !cells(for: $0).isDisjoint(with: aFoot) }
                guard !displaced.isEmpty else { continue } // must be a real "onto a tile" drop
                let reserved = others.filter { cells(for: $0).isDisjoint(with: aFoot) }
                    .reduce(into: aFoot) { $0.formUnion(cells(for: $1)) }
                guard let placement = relocate(displaced, reserved: reserved) else { continue }
                let move = placement.reduce(0) { acc, kv in
                    guard let t = displaced.first(where: { $0.id == kv.key }) else { return acc }
                    return acc + abs(kv.value[0] - t.col) + abs(kv.value[1] - t.row)
                }
                let dist = abs(oc - dropC) + abs(or - dropR)
                let cost = move + dist // keep `a` near the drop while minimising neighbour travel
                if best == nil || cost < best!.cost
                    || (cost == best!.cost && move < best!.move)
                    || (cost == best!.cost && move == best!.move && dist < best!.dist) {
                    best = ([oc, or], placement, cost, move, dist)
                }
            }
        }
        guard let b = best else { return nil }

        var grid = slots
        var moved = Set<String>()
        if let ai = grid.firstIndex(where: { $0.id == a.id }) {
            grid[ai].col = b.origin[0]; grid[ai].row = b.origin[1]
        }
        for (id, pos) in b.placement {
            if let gi = grid.firstIndex(where: { $0.id == id }) {
                if grid[gi].col != pos[0] || grid[gi].row != pos[1] { moved.insert(id) }
                grid[gi].col = pos[0]; grid[gi].row = pos[1]
            }
        }
        return moved.isEmpty ? nil : (grid, b.origin, moved)
    }

    /// Place each displaced tile (largest first) into free space not in `reserved`, preserving
    /// size, by least movement. No tile outside `displaced` is touched. Nil if they can't all fit.
    private func relocate(_ displaced: [ToolSlot], reserved: Set<[Int]>) -> [String: [Int]]? {
        let ordered = displaced.sorted {
            $0.toolSize.columns * $0.toolSize.rows > $1.toolSize.columns * $1.toolSize.rows
        }
        func candidates(_ t: ToolSlot) -> [[Int]] {
            let s = t.toolSize
            var list: [[Int]] = []
            for c in 0...(Self.columns - s.columns) {
                for r in 0...(Self.rows - s.rows) { list.append([c, r]) }
            }
            return list.sorted { l, r in
                let dl = abs(l[0] - t.col) + abs(l[1] - t.row)
                let dr = abs(r[0] - t.col) + abs(r[1] - t.row)
                if dl != dr { return dl < dr }
                return l[0] < r[0]
            }
        }
        var placement: [String: [Int]] = [:]
        func occupied() -> Set<[Int]> {
            var s = reserved
            for (id, p) in placement {
                if let t = displaced.first(where: { $0.id == id }) {
                    s.formUnion(cells(col: p[0], row: p[1], size: t.toolSize))
                }
            }
            return s
        }
        func solve(_ idx: Int) -> Bool {
            if idx == ordered.count { return true }
            let t = ordered[idx]
            let occ = occupied()
            for pos in candidates(t) where cells(col: pos[0], row: pos[1], size: t.toolSize).isDisjoint(with: occ) {
                placement[t.id] = pos
                if solve(idx + 1) { return true }
                placement[t.id] = nil
            }
            return false
        }
        return solve(0) ? placement : nil
    }

    /// Move `a` (full size) to the nearest empty slot to the drop — nobody else moves. A calm
    /// fallback when a direct reflow isn't possible. Nil if no empty slot fits.
    private func nearestEmptyPlacement(_ a: ToolSlot, toCol: Int, toRow: Int) -> ([ToolSlot], [Int])? {
        let sA = a.toolSize
        let others = slots.filter { $0.id != a.id }
        var best: (origin: [Int], dist: Int)?
        for c in 0...(Self.columns - sA.columns) {
            for r in 0...(Self.rows - sA.rows) {
                let foot = cells(col: c, row: r, size: sA)
                guard others.allSatisfy({ cells(for: $0).isDisjoint(with: foot) }) else { continue }
                let d = abs(c - toCol) + abs(r - toRow)
                if best == nil || d < best!.dist { best = ([c, r], d) }
            }
        }
        guard let b = best, let ai = slots.firstIndex(where: { $0.id == a.id }) else { return nil }
        var grid = slots
        grid[ai].col = b.origin[0]; grid[ai].row = b.origin[1]
        return (grid, b.origin)
    }

    /// New grid swapping `a` with `b`, swapping sizes too. Returns the grid and the partner.
    private func swapPlacement(_ a: ToolSlot, with b: ToolSlot) -> ([ToolSlot], ToolSlot)? {
        guard let ai = slots.firstIndex(where: { $0.id == a.id }),
              let bi = slots.firstIndex(where: { $0.id == b.id }) else { return nil }
        var grid = slots
        (grid[ai].col, grid[ai].row, grid[ai].size) = (b.col, b.row, b.size)
        (grid[bi].col, grid[bi].row, grid[bi].size) = (a.col, a.row, a.size)
        return (grid, b)
    }

    private func cells(col: Int, row: Int, size: ToolSize) -> Set<[Int]> {
        var s = Set<[Int]>()
        for c in col..<(col + size.columns) { for r in row..<(row + size.rows) { s.insert([c, r]) } }
        return s
    }

    private func cells(for slot: ToolSlot) -> Set<[Int]> {
        cells(col: slot.col, row: slot.row, size: slot.toolSize)
    }

    /// Only slots that fit inside the 5×2 grid (defensive against malformed layouts).
    private var visibleSlots: [ToolSlot] {
        slots.filter { slot in
            let size = slot.toolSize
            return slot.col >= 0 && slot.row >= 0
                && slot.col + size.columns <= Self.columns
                && slot.row + size.rows <= Self.rows
        }
    }

    /// Pixel span for `count` cells including the gaps between them.
    private func span(_ cell: CGFloat, _ count: Int) -> CGFloat {
        cell * CGFloat(count) + gap * CGFloat(count - 1)
    }

    /// Empty cells, merged into a 1x2 area where a whole column is free, else 1x1.
    private var emptyAreas: [GridArea] {
        var occupied = Array(repeating: Array(repeating: false, count: Self.rows),
                             count: Self.columns)
        // The tile being dragged frees its cells immediately, so the grid shows the gap as a
        // living placeholder (it doesn't pop into existence only when the tile lands).
        for slot in visibleSlots where slot.id != dragID {
            let size = slot.toolSize
            for c in slot.col..<(slot.col + size.columns) {
                for r in slot.row..<(slot.row + size.rows) {
                    occupied[c][r] = true
                }
            }
        }

        var areas: [GridArea] = []
        for col in 0..<Self.columns {
            let free = (0..<Self.rows).filter { !occupied[col][$0] }
            if free.count == Self.rows {
                areas.append(GridArea(col: col, row: 0, cols: 1, rows: Self.rows))
            } else {
                for row in free {
                    areas.append(GridArea(col: col, row: row, cols: 1, rows: 1))
                }
            }
        }
        return areas
    }
}

/// An empty grid cell. In Customize Mode the whole area is the add button; hovering anywhere
/// inside it glares the placeholder (border + fill + the "+") so the active target is obvious.
private struct PlaceholderCell: View {
    let area: GridArea
    let isEditing: Bool
    let onAdd: (GridArea) -> Void
    @State private var hovering = false

    var body: some View {
        if isEditing {
            Button { onAdd(area) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: NidusRadius.card, style: .continuous)
                        .fill(.white.opacity(hovering ? 0.10 : 0))
                    RoundedRectangle(cornerRadius: NidusRadius.card, style: .continuous)
                        .strokeBorder(.secondary.opacity(hovering ? 0.55 : 0.3),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: hovering ? .regular : .light))
                        .foregroundStyle(hovering ? .primary : .secondary)
                        .frame(width: 56, height: 56)
                        .nidusGlass(Circle(), interactive: true)
                        .scaleEffect(hovering ? 1.08 : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        } else {
            RoundedRectangle(cornerRadius: NidusRadius.card, style: .continuous)
                .strokeBorder(.secondary.opacity(0.16),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        }
    }
}
