// Read-only local OCR of the owner's reference images; no network/AI service.
import Foundation
import Vision

guard CommandLine.arguments.count == 2 else { fatalError("Provide reference directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
var results: [[String: Any]] = []
for file in files {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: file).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    results.append(["file": file.lastPathComponent, "lines": lines])
}
let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
