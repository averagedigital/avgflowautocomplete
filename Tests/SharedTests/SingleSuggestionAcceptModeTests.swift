import XCTest
@testable import avgFlow

@MainActor
final class SingleSuggestionAcceptModeTests: XCTestCase {
    func testAcceptanceSynthesizerUsesNextWordMode() {
        let synthesizer = AcceptanceSynthesizer(
            textInsertionService: TextInsertionService(),
            compatibilityLayer: AppCompatibilityLayer()
        )
        let completion = Completion(
            text: " hello world again",
            confidence: 0.9,
            source: .hybrid
        )

        let partial = synthesizer.partialAcceptance(
            for: completion,
            currentCompletionsCount: 1,
            acceptMode: .nextWord,
            includeTrailingWhitespace: true
        )

        XCTAssertEqual(partial?.chunk, " hello ")
        XCTAssertEqual(partial?.remainingText, "world again")
    }

    func testAcceptanceSynthesizerSkipsPartialAcceptanceForFullSuggestionMode() {
        let synthesizer = AcceptanceSynthesizer(
            textInsertionService: TextInsertionService(),
            compatibilityLayer: AppCompatibilityLayer()
        )
        let completion = Completion(
            text: " hello world again",
            confidence: 0.9,
            source: .hybrid
        )

        let partial = synthesizer.partialAcceptance(
            for: completion,
            currentCompletionsCount: 1,
            acceptMode: .fullSuggestion,
            includeTrailingWhitespace: true
        )

        XCTAssertNil(partial)
    }

    func testInlineGhostPresentationRequiresPreciseCaretGeometry() {
        XCTAssertEqual(
            SuggestionPanelController.presentationStyleForLayout(
                suggestionCount: 1,
                isWrapped: false,
                anchorQuality: .preciseCaret
            ),
            .inlineGhost
        )

        XCTAssertEqual(
            SuggestionPanelController.presentationStyleForLayout(
                suggestionCount: 1,
                isWrapped: false,
                anchorQuality: .syntheticCaret
            ),
            .bubble
        )

        XCTAssertEqual(
            SuggestionPanelController.presentationStyleForLayout(
                suggestionCount: 1,
                isWrapped: false,
                anchorQuality: .inputFallback
            ),
            .bubble
        )
    }

    func testInlineGhostPresentationFallsBackToBubbleForWrappedOrMultiSuggestionLayouts() {
        XCTAssertEqual(
            SuggestionPanelController.presentationStyleForLayout(
                suggestionCount: 2,
                isWrapped: false,
                anchorQuality: .preciseCaret
            ),
            .bubble
        )

        XCTAssertEqual(
            SuggestionPanelController.presentationStyleForLayout(
                suggestionCount: 1,
                isWrapped: true,
                anchorQuality: .preciseCaret
            ),
            .bubble
        )
    }

    func testSyntheticPlacementAccountsForWrappedLinesWithoutNewlines() {
        let prefix = String(repeating: "a", count: 15)
        let placement = CursorPositionResolver.syntheticPlacement(
            prefix: prefix,
            charsPerLine: 10,
            maxLines: 5
        )

        XCTAssertEqual(
            placement,
            CursorPositionResolver.SyntheticTextPlacement(visualLineIndex: 1, column: 5)
        )
    }

    func testSyntheticPlacementAccountsForNewlinesAndCapsVisibleLineCount() {
        let placement = CursorPositionResolver.syntheticPlacement(
            prefix: "hello\nworldwide",
            charsPerLine: 5,
            maxLines: 2
        )

        XCTAssertEqual(
            placement,
            CursorPositionResolver.SyntheticTextPlacement(visualLineIndex: 1, column: 4)
        )
    }

    func testGeometryFallbackPolicySuppressesCoarseFallbacksForTerminals() {
        let policy = AppCompatibilityLayer().geometryFallbackPolicy(for: .terminalLike)

        XCTAssertFalse(policy.allowsSyntheticCaret)
        XCTAssertFalse(policy.allowsInputFallback)
        XCTAssertFalse(policy.allowsMouseFallback)
        XCTAssertFalse(
            SuggestionPanelController.allowsAnchorQuality(
                .syntheticCaret,
                geometryFallbackPolicy: policy
            )
        )
        XCTAssertFalse(
            SuggestionPanelController.allowsAnchorQuality(
                .inputFallback,
                geometryFallbackPolicy: policy
            )
        )
    }

    func testGeometryFallbackPolicyAllowsSyntheticButNotCoarseFallbackForCodeEditors() {
        let policy = AppCompatibilityLayer().geometryFallbackPolicy(for: .codeEditor)

        XCTAssertTrue(policy.allowsSyntheticCaret)
        XCTAssertFalse(policy.allowsInputFallback)
        XCTAssertFalse(policy.allowsMouseFallback)
        XCTAssertTrue(
            SuggestionPanelController.allowsAnchorQuality(
                .syntheticCaret,
                geometryFallbackPolicy: policy
            )
        )
        XCTAssertFalse(
            SuggestionPanelController.allowsAnchorQuality(
                .inputFallback,
                geometryFallbackPolicy: policy
            )
        )
    }

    func testGeometryFallbackPolicyKeepsWebHostsOnFullFallbackChain() {
        let policy = AppCompatibilityLayer().geometryFallbackPolicy(for: .webKit)

        XCTAssertTrue(policy.allowsSyntheticCaret)
        XCTAssertTrue(policy.allowsInputFallback)
        XCTAssertTrue(policy.allowsMouseFallback)
        XCTAssertTrue(
            SuggestionPanelController.allowsAnchorQuality(
                .syntheticCaret,
                geometryFallbackPolicy: policy
            )
        )
        XCTAssertTrue(
            SuggestionPanelController.allowsAnchorQuality(
                .inputFallback,
                geometryFallbackPolicy: policy
            )
        )
    }

    func testSettingsViewModelMigratesLegacyNextChunkModeToNextWord() {
        let suiteName = "SingleSuggestionAcceptModeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("nextChunk", forKey: Constants.UserDefaultsKeys.singleSuggestionAcceptMode)

        let viewModel = SettingsViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.singleSuggestionAcceptMode, .nextWord)

        viewModel.forceApplyEngineSettings()

        XCTAssertEqual(
            defaults.string(forKey: Constants.UserDefaultsKeys.singleSuggestionAcceptMode),
            SingleSuggestionAcceptMode.nextWord.rawValue
        )
    }

    func testClipboardRestoreAllowedWhenInjectedContentIsStillCurrent() {
        XCTAssertTrue(
            TextInsertionService.shouldRestoreClipboard(
                injectedChangeCount: 10,
                currentChangeCount: 10
            )
        )
    }

    func testClipboardRestoreRejectedAfterExternalClipboardChange() {
        XCTAssertFalse(
            TextInsertionService.shouldRestoreClipboard(
                injectedChangeCount: 10,
                currentChangeCount: 11
            )
        )
    }

    func testActiveSelectionSuppressesStandardCompletion() {
        XCTAssertFalse(CursorPositionResolver.allowsStandardCompletion(selectedRangeLength: 3))
        XCTAssertTrue(CursorPositionResolver.allowsStandardCompletion(selectedRangeLength: 0))
    }

    func testUnconfirmedInsertionDoesNotAuthorizeConfirmedSideEffects() {
        let result = InsertionResult(
            succeeded: true,
            isConfirmed: false,
            route: .clipboardFallback,
            targetClass: .chromiumElectron,
            reason: "clipboard_fallback_posted_unverified"
        )

        XCTAssertFalse(result.shouldRecordAcceptance)
        XCTAssertFalse(result.allowsPartialContinuation)
    }

    func testConfirmedInsertionAuthorizesConfirmedSideEffects() {
        let result = InsertionResult(
            succeeded: true,
            isConfirmed: true,
            route: .accessibility,
            targetClass: .appKitNative,
            reason: "ax_success"
        )

        XCTAssertTrue(result.shouldRecordAcceptance)
        XCTAssertTrue(result.allowsPartialContinuation)
    }
}
