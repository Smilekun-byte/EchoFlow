import Vision
import UIKit

class OCRService {
    func recognize(
        image: UIImage,
        languages: [String] = ["zh-Hans", "ja", "en-US"],
        completion: @escaping ([String]) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let texts = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(texts ?? []) }
        }

        request.recognitionLanguages  = languages
        request.recognitionLevel      = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
