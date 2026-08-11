import CoreGraphics
import Foundation
import ImageIO
import XCTest

final class AppIconAssetTests: XCTestCase {
    private var appIconDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TodoNative/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    }

    func testEveryAppIconSlotMatchesItsDeclaredPointSizeAndScale() throws {
        let contents = try assetContents()

        for image in try XCTUnwrap(contents["images"] as? [[String: String]]) {
            guard let filename = image["filename"] else { continue }

            let expectedPixels = try expectedPixelDimension(for: image)
            let icon = try iconImage(named: filename)
            let width = icon.width
            let height = icon.height
            let slotDescription = (image["idiom"] ?? "unknown")
                + " " + (image["size"] ?? "unknown")
                + " @" + (image["scale"] ?? "unknown")

            XCTAssertEqual(width, expectedPixels, "\(filename) does not match \(slotDescription)")
            XCTAssertEqual(height, expectedPixels, "\(filename) does not match \(slotDescription)")
        }
    }

    func testEveryReferencedAppIconPNGHasNoAlphaChannel() throws {
        let contents = try assetContents()

        for filename in Set(try XCTUnwrap(contents["images"] as? [[String: String]]).compactMap(\.filename)) {
            let image = try iconImage(named: filename)

            XCTAssertTrue(
                image.alphaInfo.hasNoAlphaChannel,
                "\(filename) must not include an alpha channel for App Store submission"
            )
        }
    }

    func testMarketingAppIconIs1024PixelsSquare() throws {
        let contents = try assetContents()
        let marketingIcon = try XCTUnwrap(
            (contents["images"] as? [[String: String]])?.first(where: { $0["idiom"] == "ios-marketing" })
        )
        let filename = try XCTUnwrap(marketingIcon["filename"])
        let image = try iconImage(named: filename)

        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 1024)
    }

    private func assetContents() throws -> [String: Any] {
        let contentsURL = appIconDirectory.appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: contentsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func expectedPixelDimension(for image: [String: String]) throws -> Int {
        let size = try XCTUnwrap(image["size"])
        let scale = try XCTUnwrap(image["scale"])
        let pointDimension = try XCTUnwrap(Double(size.replacingOccurrences(of: "x", with: " ").split(separator: " ").first ?? ""))
        let scaleFactor = try XCTUnwrap(Double(scale.replacingOccurrences(of: "x", with: "")))
        return Int((pointDimension * scaleFactor).rounded())
    }

    private func iconImage(named filename: String) throws -> CGImage {
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(
            appIconDirectory.appendingPathComponent(filename) as CFURL,
            nil
        ))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    }
}

private extension Dictionary where Key == String, Value == String {
    var filename: String? { self["filename"] }
}

private extension CGImageAlphaInfo {
    var hasNoAlphaChannel: Bool {
        self == .none || self == .noneSkipFirst || self == .noneSkipLast
    }
}
