import CoreText
import Foundation
import SwiftUI

public extension MarketplaceTypography {
    static let instrumentSerifPostScriptName = "InstrumentSerif-Regular"

    private static let instrumentSerifRegistration: Void = {
        let url = Bundle.module.url(
            forResource: "InstrumentSerif-Regular",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) ?? Bundle.module.url(
            forResource: "InstrumentSerif-Regular",
            withExtension: "ttf"
        )
        guard let url else { return }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func instrumentSerif(fixedSize size: CGFloat) -> Font {
        _ = instrumentSerifRegistration
        return .custom(instrumentSerifPostScriptName, fixedSize: size)
    }

    static func instrumentSerif(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .largeTitle
    ) -> Font {
        _ = instrumentSerifRegistration
        return .custom(instrumentSerifPostScriptName, size: size, relativeTo: textStyle)
    }
}
