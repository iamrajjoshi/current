import Foundation
import Testing
@testable import CurrentFeature

@Test
func streamLinksResolveUniqueNamesAndQualifiedDuplicates() {
    let work = MarkdownStreamLinkTarget(id: UUID(), name: "Reviews", qualifiedName: "Work/Reviews")
    let home = MarkdownStreamLinkTarget(id: UUID(), name: "Reviews", qualifiedName: "Home/Reviews")
    let daily = MarkdownStreamLinkTarget(id: UUID(), name: "Daily")
    let targets = [work, home, daily]
    #expect(MarkdownStreamLinks.resolve("reviews", targets: targets) == nil)
    #expect(MarkdownStreamLinks.resolve("WORK/reviews", targets: targets) == work)
    #expect(MarkdownStreamLinks.resolve(" daily ", targets: targets) == daily)
    #expect(MarkdownStreamLinks.resolve("missing", targets: targets) == nil)
    let source = "📝 [[Daily]] [[Reviews]] [[Work/Reviews]] [[missing]]"
    let links = MarkdownStreamLinks.resolvedLinks(in: source, targets: targets)
    #expect(links.map(\.target.id) == [daily.id, work.id])
    #expect(links.map { (source as NSString).substring(with: $0.sourceRange) } == ["[[Daily]]", "[[Work/Reviews]]"])
    #expect(links.map { (source as NSString).substring(with: $0.labelRange) } == ["Daily", "Work/Reviews"])
}

@Test
func streamLinksRejectCollisionsBetweenBareAndQualifiedNames() {
    let root = MarkdownStreamLinkTarget(id: UUID(), name: "Work/Daily")
    let folder = MarkdownStreamLinkTarget(id: UUID(), name: "Daily", qualifiedName: "Work/Daily")
    let targets = [root, folder]
    #expect(MarkdownStreamLinks.resolve("work/daily", targets: targets) == nil)
    #expect(MarkdownStreamLinks.resolve("Daily", targets: targets) == folder)
    #expect(MarkdownStreamLinks.resolvedLinks(in: "[[Work/Daily]]", targets: targets).isEmpty)
    #expect(MarkdownStreamLinks.completion(in: "[[Work", selection: NSRange(location: 6, length: 0), targets: targets)?.matches.isEmpty == true)
    #expect(MarkdownStreamLinks.resolve("Work/Daily", targets: [folder, folder]) == folder)
}

@Test
func streamLinksLeaveEscapedMalformedAndCodeReferencesLiteral() {
    let targets = [MarkdownStreamLinkTarget(id: UUID(), name: "Daily")]
    let fixtures = [
        #"\[[Daily]]"#, "[[[Daily]]]", "[[Daily\n]]", "[[]]",
        "`[[Daily]]`", "```\n[[Daily]]\n```", "~~~swift\n[[Daily]]"
    ]
    for source in fixtures { #expect(MarkdownStreamLinks.resolvedLinks(in: source, targets: targets).isEmpty) }
    #expect(MarkdownStreamLinks.resolvedLinks(in: #"\\[[Daily]]"#, targets: targets).count == 1)
}

@Test
func streamLinkCompletionReplacesTheWholeReferenceAndIncludesSpaces() throws {
    let vendor = MarkdownStreamLinkTarget(id: UUID(), name: "Vendor reviews", qualifiedName: "Work/Vendor reviews")
    let source = "📝 [[Vendor rev]] later"
    let caret = (source as NSString).range(of: "]]").location
    let completion = try #require(MarkdownStreamLinks.completion(in: source, selection: NSRange(location: caret, length: 0), targets: [vendor]))
    #expect(completion.query == "Vendor rev")
    #expect(completion.matches == [vendor])
    #expect((source as NSString).substring(with: completion.replacementRange) == "[[Vendor rev]]")
    #expect((source as NSString).replacingCharacters(in: completion.replacementRange, with: vendor.insertionText) == "📝 [[Work/Vendor reviews]] later")
    let incomplete = "See [[Vendor "
    #expect(MarkdownStreamLinks.completion(in: incomplete, selection: NSRange(location: incomplete.utf16.count, length: 0), targets: [vendor])?.matches == [vendor])
}

@Test
func streamLinkCompletionRejectsCodeAndAmbiguousSuggestions() {
    let targets = [MarkdownStreamLinkTarget(id: UUID(), name: "Work"), MarkdownStreamLinkTarget(id: UUID(), name: "Work")]
    #expect(MarkdownStreamLinks.completion(in: "[[W", selection: NSRange(location: 3, length: 0), targets: targets)?.matches.isEmpty == true)
    for source in [#"\[[W"#, "[[[W", "```\n[[W", "~~~\n[[W", "[[W\n", "`[[W]]`"] {
        let caret = source == "`[[W]]`" ? 4 : source.utf16.count
        #expect(MarkdownStreamLinks.completion(in: source, selection: NSRange(location: caret, length: 0), targets: targets) == nil)
    }
    #expect(MarkdownStreamLinks.completion(in: "[[Work]]", selection: NSRange(location: 2, length: 3), targets: targets) == nil)
}

@Test
func streamLinksAcceptCachedProtectedRangesFromTheRenderModel() {
    let targets = [MarkdownStreamLinkTarget(id: UUID(), name: "Daily")]
    #expect(MarkdownStreamLinks.resolvedLinks(in: "[[Daily]]", targets: targets,
        protectedRanges: [NSRange(location: 0, length: 9)]).isEmpty)
    #expect(MarkdownStreamLinks.completion(in: "[[Da", selection: NSRange(location: 4, length: 0), targets: targets,
        protectedRanges: [NSRange(location: 0, length: 4)]) == nil)
}
