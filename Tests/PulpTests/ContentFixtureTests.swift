import Foundation
@testable import Pulp
import Testing

/// Drives `ContentAnalyzer` against the shared, language-neutral fixture contract
/// (`Fixtures/content-derivation.json`). Pear's Rust `pear-core` runs the exact
/// same fixtures, so this suite is what guarantees the Swift and Rust title/tag
/// rules stay in lockstep. The fixture file here is a vendored copy of the
/// canonical contract; `pear-core`'s reconciliation test asserts it matches.
@Suite("ContentAnalyzer shared contract")
struct ContentFixtureTests {
    struct ContentFixture: Decodable, Sendable {
        let name: String
        let input: String
        let title: String
        let tags: [String]
        let hasUncheckedTodos: Bool
    }

    private static func loadFixtures() throws -> [ContentFixture] {
        let url = try #require(
            Bundle.module.url(forResource: "content-derivation", withExtension: "json"),
            "shared content fixtures missing from test bundle"
        )
        let data = try Data(contentsOf: url)
        let fixtures = try JSONDecoder().decode([ContentFixture].self, from: data)
        #expect(!fixtures.isEmpty, "fixture set must not be empty")
        return fixtures
    }

    // Parameterized so each fixture is its own named, independently re-runnable
    // test row — a failure names the exact case rather than burying it in a loop.
    @Test(arguments: try loadFixtures())
    func matchesSharedContract(_ fixture: ContentFixture) {
        #expect(
            ContentAnalyzer.extractTitle(from: fixture.input) == fixture.title,
            "title mismatch for fixture \(fixture.name)"
        )
        #expect(
            ContentAnalyzer.extractTags(from: fixture.input) == fixture.tags,
            "tags mismatch for fixture \(fixture.name)"
        )
        #expect(
            ContentAnalyzer.hasUncheckedTodos(in: fixture.input) == fixture.hasUncheckedTodos,
            "unchecked-todo mismatch for fixture \(fixture.name)"
        )
    }
}
