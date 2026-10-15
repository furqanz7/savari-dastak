import Foundation
import XCTest
@testable import DastakUI

final class DastakDeliveryDeadlineTests: XCTestCase {
    func testTimeoutReturnsEvenWhenTransportIgnoresCancellation() async throws {
        let transport = SuspendedDeliveryResult()
        let request = Task {
            try await DastakDeliveryDeadline.run(after: .milliseconds(40)) { await transport.read() }
        }
        await transport.waitUntilStarted()
        do { _ = try await request.value; XCTFail("The wait must end without waiting for the transport") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        // A late reply may finish the old worker but cannot resume the caller a
        // second time, poison another request, or change any delivery state.
        await transport.release()
        let next = try await DastakDeliveryDeadline.run(after: .seconds(1)) { 9 }
        XCTAssertEqual(next, 9)
    }

    func testCancellationReleasesWaitEvenWhenTransportIgnoresIt() async {
        let transport = SuspendedDeliveryResult()
        let request = Task {
            try await DastakDeliveryDeadline.run(after: .seconds(5)) { await transport.read() }
        }
        await transport.waitUntilStarted()
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancellation must release the wait") }
        catch { XCTAssertTrue(error is CancellationError) }
        await transport.release()
    }
}

private actor SuspendedDeliveryResult {
    private var continuation: CheckedContinuation<Int, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func read() async -> Int {
        await withCheckedContinuation {
            continuation = $0; started?.resume(); started = nil
        }
    }
    func release() { continuation?.resume(returning: 1); continuation = nil }
}
