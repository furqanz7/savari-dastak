import Testing
@testable import MarketplaceDesignSystem

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
