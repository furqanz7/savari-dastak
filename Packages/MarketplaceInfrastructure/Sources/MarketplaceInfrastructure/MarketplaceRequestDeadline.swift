import Foundation

/// Releases the caller even if an underlying SDK task ignores cancellation.
/// The losing worker can return a value, but cannot publish it to the caller.
public enum MarketplaceRequestDeadline {
    public static func run<Value: Sendable>(after timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let result = ResultGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard result.install(continuation) else { return }
                let worker = Task {
                    do { result.finish(.success(try await operation())) }
                    catch { result.finish(.failure(error)) }
                }
                let timer = Task {
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    result.finish(.failure(URLError(.timedOut)))
                }
                result.tasks(worker, timer)
            }
        } onCancel: { result.finish(.failure(CancellationError())) }
    }

    private final class ResultGate<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, any Error>?
        private var resolution: Result<Value, any Error>?
        private var worker: Task<Void, Never>?
        private var timer: Task<Void, Never>?

        func install(_ value: CheckedContinuation<Value, any Error>) -> Bool {
            lock.lock()
            if let resolution {
                lock.unlock(); value.resume(with: resolution); return false
            }
            continuation = value
            lock.unlock(); return true
        }
        func tasks(_ worker: Task<Void, Never>, _ timer: Task<Void, Never>) {
            lock.lock()
            if resolution != nil {
                lock.unlock(); worker.cancel(); timer.cancel(); return
            }
            self.worker = worker; self.timer = timer
            lock.unlock()
        }
        func finish(_ value: Result<Value, any Error>) {
            lock.lock()
            guard resolution == nil else { lock.unlock(); return }
            resolution = value
            let continuation = continuation, worker = worker, timer = timer
            self.continuation = nil; self.worker = nil; self.timer = nil
            lock.unlock()
            worker?.cancel(); timer?.cancel()
            continuation?.resume(with: value)
        }
    }
}
