import CoreGraphics
import XCTest
@testable import PocketPass

final class BarcodeRendererTests: XCTestCase {

    /// A valid payload for every format the app offers.
    private let payloads: [BarcodeSymbology: String] = [
        .qr: "https://example.com/loyalty/4711",
        .aztec: "M1DOE/JOHN EABC123 PRGLISTP 0417 259Y012A0050 100",
        .pdf417: "PDF417 PAYLOAD 12345",
        .code128: "MEMBER-48213",
        .code39: "MEMBER-42",
        .ean13: "5901234123457",
        .ean8: "96385074",
        .upcA: "036000291452",
        .upcE: "01234565",
        .itf14: "15401412532202",
    ]

    func testEverySymbologyRendersAnImage() throws {
        for symbology in BarcodeSymbology.allCases {
            let payload = try XCTUnwrap(payloads[symbology], "no test payload for \(symbology.displayName)")
            let rendered = try BarcodeRenderer.render(payload: payload, symbology: symbology, pixelWidth: 600)

            XCTAssertGreaterThan(rendered.image.width, 0, symbology.displayName)
            XCTAssertGreaterThan(rendered.image.height, 0, symbology.displayName)
        }
    }

    func testLinearSymbolsFillMostOfTheRequestedWidth() throws {
        // Module widths are whole pixels, so the bitmap never exceeds the requested width
        // and should not fall miles short of it either.
        for symbology in LinearBarcodeEncoder.supported {
            let payload = try XCTUnwrap(payloads[symbology])
            let rendered = try BarcodeRenderer.render(payload: payload, symbology: symbology, pixelWidth: 900)

            XCTAssertLessThanOrEqual(rendered.image.width, 900, symbology.displayName)
            XCTAssertGreaterThan(rendered.image.width, 400, symbology.displayName)
        }
    }

    func testRendererCompletesTheCheckDigitItPrints() throws {
        let rendered = try BarcodeRenderer.render(payload: "590123412345", symbology: .ean13, pixelWidth: 400)
        XCTAssertEqual(rendered.humanReadable, "5901234123457")
    }

    func testInvalidPayloadThrowsRatherThanDrawingNonsense() {
        XCTAssertThrowsError(try BarcodeRenderer.render(payload: "12", symbology: .ean13, pixelWidth: 400))
        XCTAssertThrowsError(try BarcodeRenderer.render(payload: "", symbology: .qr, pixelWidth: 400))
    }

    // MARK: - Bitmap details

    func testLinearSymbolHasAWhiteQuietZone() throws {
        let barcode = try LinearBarcodeEncoder.encode("5901234123457", symbology: .ean13)
        let image = try BitmapBarcodeRenderer.makeImage(from: barcode, moduleWidth: 3, height: 80)

        XCTAssertEqual(image.width, (95 + 20) * 3)
        XCTAssertEqual(image.height, 80)

        // The left quiet zone is 10 modules wide, so anything inside it must be white.
        XCTAssertEqual(try gray(in: image, x: 5, y: 40), 255)
        XCTAssertEqual(try gray(in: image, x: image.width - 5, y: 40), 255)

        // The first guard bar sits immediately after the quiet zone.
        XCTAssertEqual(try gray(in: image, x: 10 * 3 + 1, y: 40), 0)
    }

    func testModuleWidthNeverDropsBelowOnePixel() {
        XCTAssertEqual(
            BitmapBarcodeRenderer.moduleWidth(forTotalModules: 1_000, targetPixelWidth: 10),
            1
        )
    }

    func testCacheReturnsTheSameRenderTwice() throws {
        let cache = BarcodeImageCache()
        let first = try cache.render(payload: "5901234123457", symbology: .ean13, pixelWidth: 512)
        let second = try cache.render(payload: "5901234123457", symbology: .ean13, pixelWidth: 512)
        XCTAssertTrue(first === second)

        cache.removeAll()
        let third = try cache.render(payload: "5901234123457", symbology: .ean13, pixelWidth: 512)
        XCTAssertFalse(first === third)
    }

    // MARK: - Helpers

    /// Reads one pixel out of an 8-bit grayscale image.
    private func gray(in image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let provider = try XCTUnwrap(image.dataProvider)
        let data = try XCTUnwrap(provider.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        XCTAssertEqual(image.bitsPerPixel, 8, "this helper assumes one byte per pixel")
        return bytes[y * image.bytesPerRow + x]
    }
}
