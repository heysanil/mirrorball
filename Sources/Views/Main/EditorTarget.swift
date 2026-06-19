import Foundation

/// What the editor sheet is editing: a brand-new forward, or an existing entry.
enum EditorTarget: Identifiable {
    case new
    case edit(ForwardEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let entry): entry.id.uuidString
        }
    }
}
