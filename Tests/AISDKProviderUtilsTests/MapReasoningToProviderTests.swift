import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("mapReasoningToProvider")
struct MapReasoningToProviderTests {
    private let effortMap: [LanguageModelV4ReasoningEffort: String] = [
        .minimal: "low",
        .low: "low",
        .medium: "medium",
        .high: "high",
        .xhigh: "max"
    ]

    @Test("mapReasoningToProviderEffort returns direct matches without warning")
    func effortReturnsDirectMatchWithoutWarning() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderEffort(
            reasoning: .medium,
            effortMap: effortMap,
            warnings: &warnings
        )

        #expect(result == "medium")
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderEffort returns renamed matches with compatibility warning")
    func effortReturnsRenamedMatchWithWarning() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderEffort(
            reasoning: .minimal,
            effortMap: effortMap,
            warnings: &warnings
        )

        #expect(result == "low")
        #expect(warnings == [
            .compatibility(
                feature: "reasoning",
                details: #"reasoning "minimal" is not directly supported by this model. mapped to effort "low"."#
            )
        ])
    }

    @Test("mapReasoningToProviderEffort handles xhigh compatibility mapping")
    func effortReturnsXHighCompatibilityWarning() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderEffort(
            reasoning: .xhigh,
            effortMap: effortMap,
            warnings: &warnings
        )

        #expect(result == "max")
        #expect(warnings == [
            .compatibility(
                feature: "reasoning",
                details: #"reasoning "xhigh" is not directly supported by this model. mapped to effort "max"."#
            )
        ])
    }

    @Test("mapReasoningToProviderEffort warns when level is unsupported")
    func effortWarnsForUnsupportedLevel() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderEffort(
            reasoning: .high,
            effortMap: [.medium: "medium"],
            warnings: &warnings
        )

        #expect(result == nil)
        #expect(warnings == [
            .unsupported(
                feature: "reasoning",
                details: #"reasoning "high" is not supported by this model."#
            )
        ])
    }

    @Test("isCustomReasoning matches upstream custom reasoning guard")
    func customReasoningGuard() {
        #expect(!isCustomReasoning(nil))
        #expect(!isCustomReasoning(.providerDefault))
        #expect(isCustomReasoning(LanguageModelV4ReasoningEffort.none))

        for value in [
            LanguageModelV4ReasoningEffort.minimal,
            .low,
            .medium,
            .high,
            .xhigh
        ] {
            #expect(isCustomReasoning(value))
        }
    }

    @Test("mapReasoningToProviderBudget returns percentage budget")
    func budgetReturnsKnownPercentage() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .medium,
            maxOutputTokens: 64_000,
            maxReasoningBudget: 64_000,
            warnings: &warnings
        )

        #expect(result == 19_200)
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderBudget caps at maxReasoningBudget")
    func budgetCapsAtMaximum() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .xhigh,
            maxOutputTokens: 64_000,
            maxReasoningBudget: 50_000,
            warnings: &warnings
        )

        #expect(result == 50_000)
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderBudget floors at default minimum")
    func budgetFloorsAtDefaultMinimum() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .minimal,
            maxOutputTokens: 10_000,
            maxReasoningBudget: 10_000,
            warnings: &warnings
        )

        #expect(result == 1_024)
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderBudget respects custom minimum")
    func budgetRespectsCustomMinimum() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .minimal,
            maxOutputTokens: 10_000,
            maxReasoningBudget: 10_000,
            minReasoningBudget: 512,
            warnings: &warnings
        )

        #expect(result == 512)
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderBudget respects custom percentages")
    func budgetRespectsCustomPercentages() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .medium,
            maxOutputTokens: 10_000,
            maxReasoningBudget: 10_000,
            budgetPercentages: [.medium: 0.5],
            warnings: &warnings
        )

        #expect(result == 5_000)
        #expect(warnings == [])
    }

    @Test("mapReasoningToProviderBudget warns when custom percentages omit level")
    func budgetWarnsForUnsupportedLevel() {
        var warnings: [SharedV4Warning] = []

        let result = mapReasoningToProviderBudget(
            reasoning: .high,
            maxOutputTokens: 64_000,
            maxReasoningBudget: 64_000,
            budgetPercentages: [.medium: 0.5],
            warnings: &warnings
        )

        #expect(result == nil)
        #expect(warnings == [
            .unsupported(
                feature: "reasoning",
                details: #"reasoning "high" is not supported by this model."#
            )
        ])
    }
}
