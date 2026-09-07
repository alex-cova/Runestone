@preconcurrency import AppKit

/// The overlay for Search Everywhere / Find Action / Recent Files / Go-to-file: a query field
/// above a grouped, keyboard-navigable results list. Positioned and driven by
/// `CommandPaletteController`; follows the same `NSView` + baked-`CGColor` idiom as
/// `WorkspaceSearchPanelView`.
@MainActor
public final class CommandPaletteView: NSView {
    public var onQueryChange: ((String) -> Void)?
    public var onMoveSelection: ((Int) -> Void)?
    public var onConfirm: (() -> Void)?
    public var onCancel: (() -> Void)?
    /// Row was clicked — argument is the item index (headers excluded).
    public var onActivateItemAtIndex: ((Int) -> Void)?

    private enum Row {
        case header(String)
        case item(PaletteItem)
    }

    private let queryField = PaletteQueryField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var rows: [Row] = []
    /// Table row index of the currently selected item, or `nil`.
    private var selectedTableRow: Int?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var placeholder: String = "" {
        didSet { queryField.placeholderString = placeholder }
    }

    public var query: String {
        get { queryField.stringValue }
        set { queryField.stringValue = newValue }
    }

    /// Makes the query field first responder — call after the view is in a window.
    public func focusQueryField() {
        window?.makeFirstResponder(queryField)
    }

    /// - Parameters:
    ///   - sections: grouped results.
    ///   - selectedItemIndex: index among items (headers excluded).
    public func update(sections: [PaletteSection], selectedItemIndex: Int) {
        var newRows: [Row] = []
        for section in sections {
            if !section.title.isEmpty {
                newRows.append(.header(section.title))
            }
            for item in section.items {
                newRows.append(.item(item))
            }
        }
        rows = newRows
        tableView.reloadData()

        let itemRowIndices = rows.indices.filter { if case .item = rows[$0] { return true } else { return false } }
        if itemRowIndices.isEmpty {
            selectedTableRow = nil
        } else {
            let clamped = min(max(selectedItemIndex, 0), itemRowIndices.count - 1)
            selectedTableRow = itemRowIndices[clamped]
        }
        if let selectedTableRow {
            tableView.selectRowIndexes(IndexSet(integer: selectedTableRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedTableRow)
        } else {
            tableView.deselectAll(nil)
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.font = .systemFont(ofSize: 15)
        queryField.isBezeled = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.delegate = self
        queryField.onMoveSelection = { [weak self] delta in self?.onMoveSelection?(delta) }
        queryField.onConfirm = { [weak self] in self?.onConfirm?() }
        queryField.onCancel = { [weak self] in self?.onCancel?() }
        addSubview(queryField)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.action = #selector(tableViewClicked)
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            queryField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            queryField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            queryField.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @objc private func tableViewClicked() {
        let clickedRow = tableView.clickedRow
        guard rows.indices.contains(clickedRow), case .item = rows[clickedRow] else {
            return
        }
        let itemIndex = rows[0...clickedRow].reduce(into: -1) { count, row in
            if case .item = row { count += 1 }
        }
        onActivateItemAtIndex?(itemIndex)
    }

    private func attributedTitle(for item: PaletteItem) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: item.title,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        let matched = Set(item.matchedIndices)
        let characters = Array(item.title)
        var utf16Offset = 0
        for (index, character) in characters.enumerated() {
            let length = String(character).utf16.count
            if matched.contains(index) {
                result.addAttributes(
                    [.foregroundColor: NSColor.controlAccentColor,
                     .font: NSFont.boldSystemFont(ofSize: 13)],
                    range: NSRange(location: utf16Offset, length: length)
                )
            }
            utf16Offset += length
        }
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            result.append(NSAttributedString(
                string: "   \(subtitle)",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 11)
                ]
            ))
        }
        return result
    }
}

extension CommandPaletteView: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .item = rows[row] { return true }
        return false
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let id = NSUserInterfaceItemIdentifier("headerCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? Self.makeLabelCell(id: id)
            cell.textField?.stringValue = title.uppercased()
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.font = .systemFont(ofSize: 10, weight: .semibold)
            return cell
        case .item(let item):
            let id = NSUserInterfaceItemIdentifier("itemCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? Self.makeLabelCell(id: id)
            cell.textField?.attributedStringValue = attributedTitle(for: item)
            return cell
        }
    }

    private static func makeLabelCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let view = NSTableCellView()
        view.identifier = id
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        view.addSubview(textField)
        view.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}

extension CommandPaletteView: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(queryField.stringValue)
    }
}

/// Query field that routes ↑/↓/Return/Esc to the palette instead of the field editor.
private final class PaletteQueryField: NSTextField {
    var onMoveSelection: ((Int) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            onMoveSelection?(-1)
        case #selector(NSResponder.moveDown(_:)):
            onMoveSelection?(1)
        case #selector(NSResponder.insertNewline(_:)):
            onConfirm?()
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        default:
            super.doCommand(by: selector)
        }
    }
}
