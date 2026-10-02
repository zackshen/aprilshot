import Foundation

/// Value snapshots make an entire stroke/text insertion one undoable operation.
struct History<Element> {
    struct State {
        let id: UUID
        var items: [Element]
    }
    private(set) var current = State(id: UUID(), items: [])
    private var past: [State] = []
    private var future: [State] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var items: [Element] { current.items }

    mutating func append(_ item: Element) {
        past.append(current)
        current = State(id: UUID(), items: current.items + [item])
        future.removeAll()
    }
    mutating func undo() {
        guard let state = past.popLast() else { return }
        future.append(current)
        current = state
    }
    mutating func redo() {
        guard let state = future.popLast() else { return }
        past.append(current)
        current = state
    }
}
