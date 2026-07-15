import Foundation

enum SavariLog {
    nonisolated static func debug(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
        Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
#endif
    }
}
