import SwiftUI

struct SwiftUIMenuButton: View {
    weak var selectionHandler: MenuSelectionHandler?

    @AppStorage("RunestoneExample.showLineNumbers") private var showLineNumbers = true
    @AppStorage("RunestoneExample.showPageGuide") private var showPageGuide = false
    @AppStorage("RunestoneExample.showInvisibleCharacters") private var showInvisibleCharacters = false
    @AppStorage("RunestoneExample.wrapLines") private var wrapLines = false
    @AppStorage("RunestoneExample.highlightSelectedLine") private var highlightSelectedLine = true
    @AppStorage("RunestoneExample.isEditable") private var isEditable = true
    @AppStorage("RunestoneExample.isSelectable") private var isSelectable = true

    var body: some View {
        Menu("Options", systemImage: "ellipsis") {
            if #available(iOS 16, *) {
                Section {
                    Button("Find") {
                        selectionHandler?.handleSelection(of: .presentFind)
                    }
                    Button("Find and Replace") {
                        selectionHandler?.handleSelection(of: .presentFindAndReplace)
                    }
                }
            }

            Section {
                Button("Go to Line") {
                    selectionHandler?.handleSelection(of: .presentGoToLine)
                }
            }

            Section {
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    .onChange(of: showLineNumbers) {
                        selectionHandler?.handleSelection(of: .toggleLineNumbers)
                    }
                Toggle("Show Page Guide", isOn: $showPageGuide)
                    .onChange(of: showPageGuide) {
                        selectionHandler?.handleSelection(of: .togglePageGuide)
                    }
                Toggle("Show Invisible Characters", isOn: $showInvisibleCharacters)
                    .onChange(of: showInvisibleCharacters) {
                        selectionHandler?.handleSelection(of: .toggleInvisibleCharacters)
                    }
                Toggle("Wrap Lines", isOn: $wrapLines)
                    .onChange(of: wrapLines) {
                        selectionHandler?.handleSelection(of: .toggleWrapLines)
                    }
                Toggle("Highlight Selected Line", isOn: $highlightSelectedLine)
                    .onChange(of: highlightSelectedLine) {
                        selectionHandler?.handleSelection(of: .toggleHighlightSelectedLine)
                    }
            }

            Section {
                Toggle("Allow Editing", isOn: $isEditable)
                    .onChange(of: isEditable) {
                        selectionHandler?.handleSelection(of: .toggleEditable)
                    }
                Toggle("Allow Selection", isOn: $isSelectable)
                    .onChange(of: isSelectable) {
                        selectionHandler?.handleSelection(of: .toggleSelectable)
                    }
            }

            Section {
                Button("Theme") {
                    selectionHandler?.handleSelection(of: .presentThemePicker)
                }
            }
        }
        .labelStyle(.iconOnly)
    }
}


