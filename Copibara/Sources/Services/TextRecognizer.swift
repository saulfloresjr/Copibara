import Foundation
import Vision

/// On-device text recognition over a captured image.
///
/// This is what makes screenshots searchable — and it's also our fallback source
/// extractor, since "r/homestead" is usually visible right in the pixels even when
/// no URL is available.
enum TextRecognizer {

    /// Recognize text in PNG/TIFF data. Runs synchronously — call it off the main thread.
    static func recognize(in imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // handles, counts — not prose
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[Forage] OCR failed: \(error)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
