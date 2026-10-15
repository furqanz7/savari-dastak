import Testing
import SwiftUI
@testable import MarketplaceDesignSystem
#if canImport(AppKit)
import AppKit
#endif

@Test
func dastakBrandAndDestructiveColoursRemainDistinct() {
    #expect(MarketplaceColors.dastakAccent.hex == 0xB08D57)
    #expect(MarketplaceColors.destructive.hex == 0xA65A45)
    #expect(MarketplaceColors.dastakAccent != MarketplaceColors.destructive)
}

@Test
func primaryActionsStayNeutral() {
    #expect(MarketplaceColors.primaryAction.hex == 0x21130E)
    #expect(MarketplaceColors.primaryActionForeground.hex == 0xF5F2EC)
}

@Test
func customerSurfacesAndTextFollowBothAppearances() {
    #expect(MarketplaceColors.canvas(for: .light) == MarketplaceColors.canvasLight.color)
    #expect(MarketplaceColors.canvas(for: .dark) == MarketplaceColors.canvasDark.color)
    #expect(MarketplaceColors.surface(for: .light) == MarketplaceColors.surfaceLight.color)
    #expect(MarketplaceColors.surface(for: .dark) == MarketplaceColors.surfaceDark.color)
    #expect(MarketplaceColors.primaryText(for: .light) == MarketplaceColors.textPrimaryLight.color)
    #expect(MarketplaceColors.primaryText(for: .dark) == MarketplaceColors.textPrimaryDark.color)
    #expect(MarketplaceColors.accent(for: .light) == MarketplaceColors.dastakAccent.color)
    #expect(MarketplaceColors.accent(for: .dark) == MarketplaceColors.dastakAccentDark.color)
    #expect(MarketplaceColors.surface(for: .light) != MarketplaceColors.surface(for: .dark))
}

@Test
func customerPrimaryAndSelectedLabelsHaveReadablePaletteContrast() {
    func luminance(_ rgb: MarketplaceRGB) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((rgb.hex >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    for (text, background) in [
        (MarketplaceColors.textPrimaryLight, MarketplaceColors.surfaceLight),
        (MarketplaceColors.textPrimaryDark, MarketplaceColors.surfaceDark),
        (MarketplaceColors.primaryActionForeground, MarketplaceColors.dastakAccentSoft),
    ] {
        let values = [luminance(text), luminance(background)].sorted()
        #expect((values[1] + 0.05) / (values[0] + 0.05) >= 4.5)
    }
}

@Test
func controlsMeetTheMinimumTouchTarget() {
    #expect(MarketplaceMetrics.minimumTouchTarget >= 44)
    #expect(MarketplaceMetrics.compactCornerRadius <= 8)
}

@Test
func spacingUsesAStableFourPointRhythm() {
    #expect(MarketplaceSpacing.xSmall == 4)
    #expect(MarketplaceSpacing.small == 8)
    #expect(MarketplaceSpacing.medium == 16)
    #expect(MarketplaceSpacing.large == 24)
    #expect(MarketplaceSpacing.xLarge == 32)
}

@Test
func bilingualWordmarkCopyIsStable() {
    #expect(MarketplaceWordmark.dastakLatin == "Dastak")
    #expect(MarketplaceWordmark.dastakUrdu == "دستک")
    #expect(MarketplaceWordmark.savariLatin == "Savari")
    #expect(MarketplaceWordmark.savariUrdu == "سواری")
}

@Test
func instrumentSerifIsBundledAndRegistered() {
    _ = MarketplaceTypography.instrumentSerif(fixedSize: 24)

    #if canImport(AppKit)
    #expect(NSFont(name: MarketplaceTypography.instrumentSerifPostScriptName, size: 24) != nil)
    #endif
}
