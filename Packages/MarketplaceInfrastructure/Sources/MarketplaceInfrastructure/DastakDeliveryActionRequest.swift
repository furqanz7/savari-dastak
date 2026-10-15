import Foundation

/// Recovery owns retries. This request must not be retried invisibly by the transport.
public struct DastakDeliveryActionRequest: Encodable, Sendable, SingleAttemptFunctionRequest {
    public let operation: String
    public let missionId: UUID?
    public let offerId: UUID?
    public let stopId: UUID?
    public let returnMissionId: UUID?
    public let returnStopId: UUID?
    public let verificationCode: String?
    public let accountedPackageCount: Int?
    public let objectPath: String?
    public let reason: String?
    public let outcome: DastakV1CollectionOutcome?
    public let method: DastakV1CollectionMethod?
    public let collectionReference: String?
    public let failureReason: String?
    public let expectedMissionVersion: Int?
    public let assignmentId: UUID?

    public init(operation: String, missionId: UUID? = nil, offerId: UUID? = nil, stopId: UUID? = nil,
                returnMissionId: UUID? = nil, returnStopId: UUID? = nil,
                verificationCode: String? = nil, accountedPackageCount: Int? = nil,
                objectPath: String? = nil, reason: String? = nil,
                outcome: DastakV1CollectionOutcome? = nil, method: DastakV1CollectionMethod? = nil,
                collectionReference: String? = nil, failureReason: String? = nil, expectedMissionVersion: Int? = nil, assignmentId: UUID? = nil) {
        self.operation = operation; self.missionId = missionId; self.offerId = offerId; self.stopId = stopId
        self.returnMissionId = returnMissionId; self.returnStopId = returnStopId
        self.verificationCode = verificationCode; self.accountedPackageCount = accountedPackageCount
        self.objectPath = objectPath; self.reason = reason; self.outcome = outcome; self.method = method
        self.collectionReference = collectionReference; self.failureReason = failureReason
        self.expectedMissionVersion = expectedMissionVersion
        self.assignmentId = assignmentId
    }
}
