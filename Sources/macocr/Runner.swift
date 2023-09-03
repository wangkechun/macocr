//
//  Runner.swift
//  macocr
//
//  Created by Matthias Winkelmann on 13.01.22.
//
import Cocoa
import Vision
import Foundation



@available(macOS 11.0, *)
class Runner {


    struct ImageFileType {
        var uti: CFString
        var fileExtention: String

        // This list can include anything returned by CGImageDestinationCopyTypeIdentifiers()
        // I'm including only the popular formats here
        static let bmp = ImageFileType(uti: kUTTypeBMP, fileExtention: "bmp")
        static let gif = ImageFileType(uti: kUTTypeGIF, fileExtention: "gif")
        static let jpg = ImageFileType(uti: kUTTypeJPEG, fileExtention: "jpg")
        static let png = ImageFileType(uti: kUTTypePNG, fileExtention: "png")
        static let tiff = ImageFileType(uti: kUTTypeTIFF, fileExtention: "tiff")
    }

    func convertPDF(at sourceURL: URL, to destinationURL: URL, fileType: ImageFileType, dpi: CGFloat = 200) throws -> [URL] {
        let pdfDocument = CGPDFDocument(sourceURL as CFURL)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        var urls = [URL](repeating: URL(fileURLWithPath : "/"), count: pdfDocument.numberOfPages)
        DispatchQueue.concurrentPerform(iterations: pdfDocument.numberOfPages) { i in
            // Page number starts at 1, not 0
            let pdfPage = pdfDocument.page(at: i + 1)!

            let mediaBoxRect = pdfPage.getBoxRect(.mediaBox)
            let scale = dpi / 72.0
            let width = Int(mediaBoxRect.width * scale)
            let height = Int(mediaBoxRect.height * scale)

            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo)!
            context.interpolationQuality = .high
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(pdfPage)

            let image = context.makeImage()!
            let imageName = sourceURL.deletingPathExtension().lastPathComponent
            let imageURL = destinationURL.appendingPathComponent("\(imageName)-Page\(i+1).\(fileType.fileExtention)")

            let imageDestination = CGImageDestinationCreateWithURL(imageURL as CFURL, fileType.uti, 1, nil)!
            CGImageDestinationAddImage(imageDestination, image, nil)
            CGImageDestinationFinalize(imageDestination)

            urls[i] = imageURL
        }
        return urls
    }


struct Resp:Encodable{
   var file: String
   var error: String
   var obs: [String] = []
}

static func run(files: [String]) -> Int32 {


    // Flag ideas:
    // --version
    // Print REVISION
    // --langs
    //guard let langs = VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: REVISION)
    // --fast (default accurate)
    // --fix (default no language correction)
    while let file = readLine(){
        let url = URL(fileURLWithPath: file)
        let img = NSImage(byReferencing: url)
        guard let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let resp = Resp(file: file, error:"Error: failed to convert NSImage to CGImage")
            let encoder = JSONEncoder()
            guard let encodedData = try? encoder.encode(resp), 
            let jsonText = String(data: encodedData, encoding: .utf8) else {
                fatalError("`JSON Encode Failed`")
            }
            print(jsonText)
            fflush(stdout)
            continue
        }

        let request = VNRecognizeTextRequest { (request, error) in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let obs : [String] = observations.map { $0.topCandidates(1).first?.string ?? ""}
            // try? obs.joined(separator: "\n").write(to: url.appendingPathExtension("md"), atomically: true, encoding: String.Encoding.utf8)
            let resp = Resp(file: file, error:"", obs:obs)
            let encoder = JSONEncoder()
            guard let encodedData = try? encoder.encode(resp), 
            let jsonText = String(data: encodedData, encoding: .utf8) else {
                fatalError("`JSON Encode Failed`")
            }
            print(jsonText)
            fflush(stdout)
        }
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate // or .fast
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision2
        request.recognitionLanguages = ["zh", "en"]
        request.customWords = []

        try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])
    }
    return 0
}
}
