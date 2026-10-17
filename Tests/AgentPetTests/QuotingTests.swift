import Foundation
import Testing
@testable import AgentPet

struct QuotingTests {
    @Test func shellQuotesPlainPathsInSingleQuotes() {
        #expect(ScriptQuoting.shell("/Users/me/project") == "'/Users/me/project'")
    }

    @Test func shellEscapesEmbeddedSingleQuotes() {
        #expect(ScriptQuoting.shell("it's") == "'it'\\''s'")
    }

    @Test func shellKeepsExpansionCharactersInert() {
        let quoted = ScriptQuoting.shell("$HOME `id` $(id) \\ \"x\"")
        #expect(quoted == "'$HOME `id` $(id) \\ \"x\"'")
    }

    @Test func appleScriptEscapesBackslashesBeforeQuotes() {
        #expect(ScriptQuoting.appleScript("a\\b\"c") == "a\\\\b\\\"c")
    }

    @Test func doScriptLiteralSurvivesBothLayers() {
        let command = "cd \(ScriptQuoting.shell("/tmp/it's \"x\" \\ $y")) && claude"
        let literal = ScriptQuoting.appleScriptShellCommand(command)
        #expect(literal.hasPrefix("\"") && literal.hasSuffix("\""))
        // Every double quote and backslash inside the literal is escaped, so it cannot end the string early.
        let inner = String(literal.dropFirst().dropLast())
        var escaped = false
        for character in inner {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            #expect(character != "\"")
        }
        #expect(!escaped)
    }

    @Test func rejectsDirectoriesWithControlCharacters() {
        #expect(SafeDirectory.isSafe("/Users/me/project"))
        #expect(SafeDirectory.isSafe("/tmp/it's \"x\" $y"))
        #expect(!SafeDirectory.isSafe(""))
        #expect(!SafeDirectory.isSafe("/tmp/a\nb"))
        #expect(!SafeDirectory.isSafe("/tmp/a\rb"))
        #expect(!SafeDirectory.isSafe("/tmp/a\u{0}b"))
        #expect(!SafeDirectory.isSafe("/tmp/a\tb"))
    }
}
