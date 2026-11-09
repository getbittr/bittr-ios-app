//
//  QRCode.swift
//  BittrWidget
//
//  Created by Tom Melters on 21/09/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

// Same encoding the Receive screen uses for the lightning address: the plain
// address string at correction level H.
func qrCode(for text:String) -> CGImage? {

    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "H"

    guard let output = filter.outputImage else { return nil }

    // The generator emits one pixel per module, so scale up before rasterising
    // or the widget draws a handful of pixels stretched across the card.
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

    return CIContext().createCGImage(scaled, from: scaled.extent)
}
