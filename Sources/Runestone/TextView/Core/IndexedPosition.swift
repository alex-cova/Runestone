import Foundation
@preconcurrency import AppKit

final class IndexedPosition: UITextPosition {
    let index: Int

    init(index: Int) {
        self.index = index
    }
}
