import Foundation

enum PromptBuilder {
    // MARK: - Prompt

    static func buildPrompt(
        context: TextContext,
        suggestionCount: Int,
        userPatterns: [String],
        userMemories: [String] = [],
        styleInsights: [String] = [],
        goodCompletions: [String] = [],
        lexiconStyleSnippet: String? = nil,
        replacementMode: Bool = false
    ) -> String {
        let sanitizedCount = max(1, suggestionCount)
        let before = escapeXML(String(context.textBefore.suffix(Constants.Limits.contextBeforeCharacterLimit)))
        let after = escapeXML(String(context.textAfter.prefix(Constants.Limits.contextAfterCharacterLimit)))
        let language = escapeXML(context.language)

        let relevantPatterns = userPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Constants.Limits.maxPromptPatterns)
            .map(escapeXML)
        let memories = userMemories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Constants.Limits.maxPromptPatterns)
            .map(escapeXML)
        let insights = styleInsights
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Constants.Limits.maxPromptPatterns)
            .map(escapeXML)
        let examples = goodCompletions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Constants.Limits.maxGoodCompletions)
            .map(escapeXML)
        let snippet = (lexiconStyleSnippet ?? context.lexiconStyleSnippet ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snippetBlock = snippet.isEmpty ? "<none/>" : escapeXML(snippet)

        let patternsBlock: String
        if relevantPatterns.isEmpty {
            patternsBlock = "<none/>"
        } else {
            patternsBlock = relevantPatterns.map { "- \($0)" }.joined(separator: "\n")
        }

        let memoriesBlock = memories.isEmpty ? "<none/>" : memories.map { "- \($0)" }.joined(separator: "\n")
        let insightsBlock = insights.isEmpty ? "<none/>" : insights.map { "- \($0)" }.joined(separator: "\n")
        let completionsBlock = examples.isEmpty ? "<none/>" : examples.map { "- \($0)" }.joined(separator: "\n")

        let modeInstruction: String
        if replacementMode {
            modeInstruction = """
            Complete or replace the text at <cursor/>. Provide \(sanitizedCount) suggestions.
            You may either continue the text OR replace recent input using REPLACE:N:text format.
            Language: \(language)
            """
        } else {
            modeInstruction = """
            Complete the text at <cursor/>. Provide \(sanitizedCount) natural suggestions.
            Language: \(language)
            """
        }

        return """
        <context>
        \(before)
        </context>
        <cursor/>
        <after>
        \(after)
        </after>
        <user_patterns>
        \(patternsBlock)
        </user_patterns>
        <good_completions>
        \(completionsBlock)
        </good_completions>
        <user_style_profile>
        \(insightsBlock)
        </user_style_profile>
        <user_memories>
        \(memoriesBlock)
        </user_memories>
        <style_snippet>
        \(snippetBlock)
        </style_snippet>
        <instruction>
        \(modeInstruction)
        </instruction>
        """
    }

    // MARK: - Private

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
