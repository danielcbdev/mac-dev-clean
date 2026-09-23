import Foundation

/// Holds the one task a feature model has in flight.
///
/// It exists so `deinit`, which is nonisolated, can still cancel work owned by
/// a `@MainActor` model. `@unchecked Sendable` is sound here because the stored
/// task is only ever read or written while holding the lock.
final class CancellableWork: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init() {}

    func replace(with newTask: Task<Void, Never>?) {
        lock.lock()
        let previous = task
        task = newTask
        lock.unlock()
        previous?.cancel()
    }

    func cancel() {
        lock.lock()
        let current = task
        task = nil
        lock.unlock()
        current?.cancel()
    }

    var current: Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }
}
