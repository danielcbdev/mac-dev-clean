import SwiftUI

struct SelectionFooter: View {
    let count: Int

    var body: some View {
        // Rejected: Xcode's automatic grammar agreement annotation reaches the
        // screen intact wherever it does not resolve. Counts go through
        // CountText and the catalog's plural variations instead.
        Text("^[\(count) item](inflect: true) selected")
    }
}
