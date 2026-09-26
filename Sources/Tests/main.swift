// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

// MARK: - A tiny test harness
//
// This is a plain executable rather than a SwiftPM `.testTarget` for a concrete
// reason: running an XCTest bundle requires a full Xcode install, and the Command
// Line Tools alone cannot execute one. A self-contained harness means the same
// tests run anywhere the app itself builds, with no private framework APIs.
//
//     swift run hfh-tests
//     swift run hfh-tests FrontMatter
//     swift run hfh-tests --verbose

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@discardableResult
func expect(_ condition: @autoclosure () -> Bool,
            _ message: String,
            file: StaticString = #filePath,
            line: UInt = #line) -> Bool {
    if condition() { return true }
    let failure = "FAIL  \(shortFile(file)):\(line)  \(message)"
    TestRunner.failures.append(failure)
    print(failure)
    return false
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               _ label: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
    if expect(actual == expected, "\(label): expected \(expected), got \(actual)",
              file: file, line: line) { return }
}

private func shortFile(_ file: StaticString) -> String {
    URL(fileURLWithPath: "\(file)").lastPathComponent
}

/// A named collection of checks. Cases register themselves, then run().
///
/// Cases are `@MainActor` because the types under test — SiteEngine, Builder,
/// PreviewServer — are all main-actor isolated, exactly as they are in the app.
struct TestSuite {
    let name: String
    private(set) var cases: [(String, @MainActor () async throws -> Void)] = []

    init(_ name: String) { self.name = name }

    mutating func test(_ title: String, _ body: @escaping @MainActor () async throws -> Void) {
        cases.append((title, body))
    }

    func run(filter: String?) async {
        print("\n▸ \(name)")
        for (title, body) in cases {
            if let filter, !title.lowercased().contains(filter.lowercased()),
               !name.lowercased().contains(filter.lowercased()) {
                continue
            }
            let before = TestRunner.failures.count
            do {
                try await body()
            } catch {
                TestRunner.failures.append("FAIL  \(name) / \(title): threw \(error)")
                print("FAIL  \(name) / \(title): threw \(error)")
            }
            let added = TestRunner.failures.count - before
            if added == 0 {
                print("  ✓ \(title)")
            } else {
                print("  ✗ \(title)  (\(added) failed)")
            }
        }
    }
}

enum TestRunner {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var passed = 0

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let filter = args.first(where: { !$0.hasPrefix("--") })
        let verbose = args.contains("--verbose")

        print("Hugo for Humans — test suite")
        if verbose { printHarnessEnvironment() }

        // allSuites is main-actor isolated, so the runner has to be too.
        let suites = await MainActor.run { allSuites() }
        for suite in suites {
            await suite.run(filter: filter)
        }

        let total = TestRunner.failures.count
        print("\n" + String(repeating: "─", count: 52))
        if total == 0 {
            print("All checks passed.")
        } else {
            print("\(total) check(s) failed:")
            for failure in TestRunner.failures { print("  \(failure)") }
        }
        // A non-zero exit lets CI notice.
        exit(total == 0 ? 0 : 1)
    }

    private static func printHarnessEnvironment() {
        if let url = HugoBinary.resolve(), let version = HugoBinary.version(of: url) {
            print("Hugo:   \(version)")
            print("Binary: \(url.path)")
        } else {
            print("Hugo:   not found — integration checks will be skipped")
        }
    }

    /// Every suite, in the order they should run.
    ///
    /// Main-actor isolated because some suites build fixtures that touch
    /// `SiteEngine` and the registry, which are main-actor types in the app.
    @MainActor
    static func allSuites() -> [TestSuite] {
        [frontMatterSuite(), contentItemSuite(), siteConfigSuite(),
         quotingSuite(), embedSuite(), mediaSuite(), vaultSuite(), targetSuite(),
         editorSuite(),
         builderSuite(), streamedOutputSuite(), themeCatalogSuite(), hugoBinarySuite(), integrationSuite()]
    }
}

// MARK: - Entry point

@main
struct Main {
    static func main() async {
        await TestRunner.main()
    }
}
