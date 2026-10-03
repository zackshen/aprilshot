import AppKit

/// All files contain synthetic pixels and live under one disposable test root.
/// Every cleanup call injects a mover into a test folder, never the real Trash.
@main
struct ExportCleanupTests {
    static var checks = 0
    static var failures = 0
    static let manager = FileManager.default
    static let day: TimeInterval = 86_400
    static let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 + 60 * day))

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do {
            if try !condition() { failures += 1; print("FAIL: \(message)") }
        } catch { failures += 1; print("FAIL: \(message): \(error)") }
    }
    static func expectError(_ message: String, _ action: () throws -> Void) {
        do { try action(); check(false, message) }
        catch { check(true, message) }
    }
    static func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<2 { for x in 0..<2 { rep.setColor(.systemBlue, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }
    static func filename(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "AprilShot_\(formatter.string(from: date))_\(UUID().uuidString).png"
    }
    static func legacy(_ directory: URL, at date: Date, data: Data? = nil) throws -> URL {
        let url = directory.appendingPathComponent(filename(at: date))
        try (data ?? png()).write(to: url)
        try manager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }
    static func owned(_ directory: URL, at date: Date) throws -> URL {
        try OwnedExportRegistry.validateDirectory(directory, create: true)
        try OwnedExportRegistry.prepareForSave(directory: directory)
        let url = try legacy(directory, at: date)
        try OwnedExportRegistry.register(url, createdAt: date)
        return url
    }
    static func folder(_ root: URL, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name).appendingPathComponent("Exports", isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func mover(to trash: URL) -> (URL) throws -> Void {
        { url in
            try manager.createDirectory(at: trash, withIntermediateDirectories: true)
            try manager.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
    }

    static func main() throws {
        // Canonicalize only the fixture base: macOS's /var temp alias is a symlink.
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AprilShot cleanup 测试 \(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) } // disposable synthetic fixtures only
        check(ExportRetentionPolicy.default == .threeDays, "default keeps the recent three days")
        check(Set(ExportRetentionPolicy.allCases.map { $0.rawValue }) == Set([0, 1, 3, 7, 30]), "retention options use supported day counts")
        check(ExportRetentionPolicy(rawValue: 2) == nil, "unsupported setting cannot become a retention policy")

        let absent = root.appendingPathComponent("Absent/Exports")
        let missingCleaner = ExportCleanup(directory: absent, trash: { _ in check(false, "missing directory never calls mover") })
        let empty = try missingCleaner.plan(mode: .allOwned, now: now)
        check(empty.count == 0, "missing export directory has an empty preview")
        check(try missingCleaner.run(empty, now: now).movedCount == 0, "empty cleanup is a no-op")
        check(!manager.fileExists(atPath: absent.path), "preview does not create a missing directory")

        let legacyDirectory = try folder(root, "Legacy")
        let old = try legacy(legacyDirectory, at: now.addingTimeInterval(-4 * day))
        let boundary = try legacy(legacyDirectory, at: now.addingTimeInterval(-3 * day))
        let recent = try legacy(legacyDirectory, at: now.addingTimeInterval(-2 * day))
        let fresh = try legacy(legacyDirectory, at: now.addingTimeInterval(-60))
        let future = try legacy(legacyDirectory, at: now.addingTimeInterval(day))
        let clipboard = try legacy(legacyDirectory, at: now.addingTimeInterval(-7 * day))
        let unrelated = legacyDirectory.appendingPathComponent("User Saved.png")
        try png().write(to: unrelated)
        let invalidDate = legacyDirectory.appendingPathComponent("AprilShot_2026-02-30_12-00-00_\(UUID().uuidString).png")
        try png().write(to: invalidDate)
        let corrupt = try legacy(legacyDirectory, at: now.addingTimeInterval(-7 * day),
                                 data: Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data("not a PNG".utf8))
        let nested = legacyDirectory.appendingPathComponent("Nested", isDirectory: true)
        try manager.createDirectory(at: nested, withIntermediateDirectories: false)
        let nestedPNG = try legacy(nested, at: now.addingTimeInterval(-10 * day))
        let exterior = root.appendingPathComponent("external.png")
        try png().write(to: exterior)
        let symlink = legacyDirectory.appendingPathComponent(filename(at: now.addingTimeInterval(-8 * day)))
        try manager.createSymbolicLink(at: symlink, withDestinationURL: exterior)
        let namedDirectory = legacyDirectory.appendingPathComponent(filename(at: now.addingTimeInterval(-9 * day)))
        try manager.createDirectory(at: namedDirectory, withIntermediateDirectories: false)
        let trash = root.appendingPathComponent("Fixture Trash")
        let cleaner = ExportCleanup(directory: legacyDirectory, trash: mover(to: trash))
        let automatic = try cleaner.plan(mode: .expired(.threeDays), protectedPath: clipboard.path, now: now)
        check(automatic.urls == [old], "automatic cleanup selects only strictly expired unprotected legacy PNG")
        check(automatic.legacyCount == 1, "preview surfaces legacy candidate count")
        check(automatic.byteCount == UInt64(try Data(contentsOf: old).count), "preview computes bytes from verified files")
        check(automatic.protectedCount == 3, "fresh, future-dated, and clipboard files are protected")
        check(automatic.untrackedCount == 6, "unrelated, corrupt, directories, invalid dates, and symlink stay untracked")
        check(try cleaner.plan(mode: .expired(.never), now: now).count == 0, "never disables automatic cleanup")
        check(try cleaner.plan(mode: .expired(.oneDay), protectedPath: clipboard.path, now: now).count == 3,
              "one-day policy uses its own cutoff")
        check(try cleaner.plan(mode: .expired(.sevenDays), protectedPath: clipboard.path, now: now).count == 0,
              "seven-day policy preserves younger files")
        check(try cleaner.plan(mode: .expired(.thirtyDays), protectedPath: clipboard.path, now: now).count == 0,
              "thirty-day policy preserves younger files")
        let manual = try cleaner.plan(mode: .allOwned, protectedPath: clipboard.path, now: now)
        check(Set(manual.urls) == Set([old, boundary, recent]), "manual cleanup includes retained owned files but honors protections")
        check(manager.fileExists(atPath: old.path), "preview alone never moves a file")
        let firstResult = try cleaner.run(automatic, protectedPath: clipboard.path, now: now)
        check(firstResult.movedCount == 1 && firstResult.failures.isEmpty, "expired copy moves successfully using injected mover")
        check(manager.fileExists(atPath: trash.appendingPathComponent(old.lastPathComponent).path), "moved fixture remains recoverable")
        check([boundary, recent, fresh, future, clipboard, unrelated, invalidDate, corrupt, nestedPNG, exterior, symlink, namedDirectory]
            .allSatisfy { manager.fileExists(atPath: $0.path) }, "all protected and unowned content survives cleanup")
        check(try cleaner.run(automatic, protectedPath: clipboard.path, now: now).movedCount == 0, "repeated confirmed plan cannot move more files")
        check(try cleaner.plan(mode: .expired(.threeDays), protectedPath: clipboard.path, now: now.addingTimeInterval(1)).urls.contains(boundary),
              "file becomes eligible only after strict retention boundary passes")

        // Ownership migration closes after the first registry is persisted.
        let laterLookalike = try legacy(legacyDirectory, at: now.addingTimeInterval(-20 * day))
        let laterPreview = try cleaner.plan(mode: .allOwned, protectedPath: clipboard.path, now: now)
        check(!laterPreview.urls.contains(laterLookalike), "later Save-like exact filenames are never adopted once a registry exists")
        check(laterPreview.untrackedCount == 7, "untracked later file remains visible in preview count")

        let savedDirectory = try folder(root, "Save")
        let existingLegacy = try legacy(savedDirectory, at: now.addingTimeInterval(-5 * day))
        let store = CopiedImageStore(directory: savedDirectory)
        let copy = try store.savePNG(png())
        let savedCleaner = ExportCleanup(directory: savedDirectory, trash: mover(to: root.appendingPathComponent("Saved Trash")))
        let savedPlan = try savedCleaner.plan(mode: .allOwned, now: now)
        check(Set(savedPlan.urls) == Set([existingLegacy, copy]), "first copy snapshots old legacy files and registers new owned PNG")
        check(savedPlan.legacyCount == 1, "new copies are registered without being labeled legacy")
        check(try manager.contentsOfDirectory(at: savedDirectory, includingPropertiesForKeys: nil).count == 2,
              "ownership manifest stays outside the PNG-only export directory")
        check(manager.fileExists(atPath: OwnedExportRegistry.manifestURL(savedDirectory).path), "ownership registry is durable across service instances")
        let latestCleaner = ExportCleanup(directory: savedDirectory, trash: { _ in check(false, "fresh copy should not move") })
        let latest = try latestCleaner.plan(mode: .allOwned, now: Date())
        check(!latest.urls.contains(copy), "fresh just-copied image survives manual cleanup")

        let mutations = try folder(root, "Mutations")
        let changed = try owned(mutations, at: now.addingTimeInterval(-10 * day))
        let replaced = try owned(mutations, at: now.addingTimeInterval(-10 * day))
        let turnedLink = try owned(mutations, at: now.addingTimeInterval(-10 * day))
        let deleted = try owned(mutations, at: now.addingTimeInterval(-10 * day))
        var mutationMoves = 0
        let mutationCleaner = ExportCleanup(directory: mutations, trash: { _ in mutationMoves += 1 })
        let beforeMutation = try mutationCleaner.plan(mode: .allOwned, now: now)
        check(beforeMutation.count == 4, "mutation fixture begins with four owned candidates")
        try Data("edited user content".utf8).write(to: changed)
        try png().write(to: replaced, options: .atomic)
        try manager.removeItem(at: turnedLink)
        try manager.createSymbolicLink(at: turnedLink, withDestinationURL: exterior)
        try manager.removeItem(at: deleted)
        let mutationResult = try mutationCleaner.run(beforeMutation, now: now)
        check(mutationMoves == 0 && mutationResult.skippedCount == 4, "post-confirmation edits, replacements, symlinks, and missing files are all skipped")
        check(try Data(contentsOf: changed) == Data("edited user content".utf8), "changed contents are not touched")
        check(try mutationCleaner.plan(mode: .allOwned, now: now).changedCount == 4, "changed identity count is surfaced separately")

        let delayed = try folder(root, "Delayed")
        let before = try owned(delayed, at: now.addingTimeInterval(-10 * day))
        var liveClipboard: String? = nil
        var delayedMoves = 0
        let delayedCleaner = ExportCleanup(directory: delayed, trash: { _ in delayedMoves += 1 }, currentProtectedPath: { liveClipboard })
        let delayedPlan = try delayedCleaner.plan(mode: .allOwned, now: now)
        let after = try owned(delayed, at: now.addingTimeInterval(-10 * day))
        liveClipboard = before.path
        let delayedResult = try delayedCleaner.run(delayedPlan, now: now)
        check(delayedMoves == 0 && delayedResult.skippedCount == 1, "current clipboard is checked again after confirmation")
        check(manager.fileExists(atPath: after.path), "new files created after preview never enter its approved set")
        let alias = root.appendingPathComponent("clipboard alias.png")
        try manager.createSymbolicLink(at: alias, withDestinationURL: before)
        liveClipboard = alias.path
        check(try !delayedCleaner.plan(mode: .allOwned, now: now).urls.contains(before), "clipboard alias protects its actual owned target")

        let freshness = try folder(root, "Freshness Boundary")
        let atFreshLimit = try owned(freshness, at: now.addingTimeInterval(-ExportCleanup.freshProtectionInterval))
        let freshnessCleaner = ExportCleanup(directory: freshness, trash: { _ in })
        check(try freshnessCleaner.plan(mode: .allOwned, now: now).count == 0, "exact five-minute freshness boundary stays protected")
        check(try freshnessCleaner.plan(mode: .allOwned, now: now.addingTimeInterval(1)).urls == [atFreshLimit],
              "manual candidate appears after freshness boundary passes")

        let swapped = try folder(root, "Swapped Directory")
        let swappedFile = try owned(swapped, at: now.addingTimeInterval(-10 * day))
        let swappedCleaner = ExportCleanup(directory: swapped, trash: { _ in check(false, "replaced export directory cannot move content") })
        let swappedPlan = try swappedCleaner.plan(mode: .allOwned, now: now)
        let renamed = swapped.deletingLastPathComponent().appendingPathComponent("Original Exports")
        try manager.moveItem(at: swapped, to: renamed)
        try manager.createDirectory(at: swapped, withIntermediateDirectories: false)
        expectError("directory replacement after preview fails closed") { _ = try swappedCleaner.run(swappedPlan, now: now) }
        check(manager.fileExists(atPath: renamed.appendingPathComponent(swappedFile.lastPathComponent).path), "original directory contents survive replacement check")

        let errors = try folder(root, "Errors")
        let canMove = try owned(errors, at: now.addingTimeInterval(-10 * day))
        let cannotMove = try owned(errors, at: now.addingTimeInterval(-10 * day))
        let errorTrash = root.appendingPathComponent("Error Trash")
        let errorCleaner = ExportCleanup(directory: errors, trash: { url in
            if url == cannotMove { throw CocoaError(.fileWriteNoPermission) }
            try mover(to: errorTrash)(url)
        })
        let errorResult = try errorCleaner.run(errorCleaner.plan(mode: .allOwned, now: now), now: now)
        check(errorResult.movedCount == 1 && errorResult.failures.count == 1, "one failed Trash move does not prevent independent eligible files")
        check(errorResult.failures.first?.url == cannotMove && manager.fileExists(atPath: cannotMove.path), "failed move identifies the file and preserves it")
        check(!manager.fileExists(atPath: canMove.path), "success count reflects actual moved source")
        let noop = ExportCleanup(directory: errors, trash: { _ in })
        let noopResult = try noop.run(noop.plan(mode: .allOwned, now: now), now: now)
        check(noopResult.movedCount == 0 && noopResult.failures.count == 1, "no-op mover cannot falsely report success")

        let redirected = root.appendingPathComponent("Redirected Exports")
        try manager.createSymbolicLink(at: redirected, withDestinationURL: savedDirectory)
        let redirectedCleaner = ExportCleanup(directory: redirected, trash: { _ in check(false, "symlink directory cannot move content") })
        expectError("symlink export directory is rejected by cleanup") { _ = try redirectedCleaner.plan(mode: .allOwned, now: now) }
        let fileCount = try manager.contentsOfDirectory(at: savedDirectory, includingPropertiesForKeys: nil).count
        var clipboardWrites = 0
        let redirectedCopier = ImagePathCopier(store: CopiedImageStore(directory: redirected), writePath: { _ in clipboardWrites += 1; return true })
        expectError("symlink export directory is rejected by saving") { _ = try redirectedCopier.copyPNG(png()) }
        let countAfterRejectedSave = try manager.contentsOfDirectory(at: savedDirectory, includingPropertiesForKeys: nil).count
        check(clipboardWrites == 0 && countAfterRejectedSave == fileCount,
              "redirected save neither writes external files nor changes clipboard")
        let ancestorAlias = root.appendingPathComponent("Ancestor Alias")
        try manager.createSymbolicLink(at: ancestorAlias, withDestinationURL: savedDirectory.deletingLastPathComponent())
        let ancestorCleaner = ExportCleanup(directory: ancestorAlias.appendingPathComponent("Exports"), trash: { _ in })
        expectError("symlink ancestor is rejected") { _ = try ancestorCleaner.plan(mode: .allOwned, now: now) }
        expectError("save rejects symlink ancestor") { _ = try CopiedImageStore(directory: ancestorAlias.appendingPathComponent("Exports")).savePNG(png()) }

        let badRegistry = try folder(root, "Bad Registry")
        let badRecordFile = try owned(badRegistry, at: now.addingTimeInterval(-10 * day))
        let registry = OwnedExportRegistry.manifestURL(badRegistry)
        let registryCleaner = ExportCleanup(directory: badRegistry, trash: { _ in check(false, "unsafe registry stops cleanup") })
        let registryPlan = try registryCleaner.plan(mode: .allOwned, now: now)
        try manager.removeItem(at: registry)
        expectError("registry removed after confirmation fails closed") { _ = try registryCleaner.run(registryPlan, now: now) }
        try manager.createSymbolicLink(at: registry, withDestinationURL: exterior)
        expectError("symlink registry cannot be read as ownership") { _ = try registryCleaner.plan(mode: .allOwned, now: now) }
        expectError("symlink registry blocks saving before PNG creation") { _ = try CopiedImageStore(directory: badRegistry).savePNG(png()) }
        check(manager.fileExists(atPath: badRecordFile.path), "registry failure preserves owned image")
        try manager.removeItem(at: registry)
        try Data("malformed registry".utf8).write(to: registry)
        expectError("corrupt registry fails closed rather than remigrating names") { _ = try registryCleaner.plan(mode: .allOwned, now: now) }

        let hardLinks = try folder(root, "Hard Links")
        let original = try owned(hardLinks, at: now.addingTimeInterval(-10 * day))
        try manager.linkItem(at: original, to: root.appendingPathComponent("hardlink.png"))
        let hardLinkCleaner = ExportCleanup(directory: hardLinks, trash: { _ in check(false, "multiply linked file cannot move") })
        check(try hardLinkCleaner.plan(mode: .allOwned, now: now).count == 0, "hard-linked export is treated as changed and preserved")

        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) export cleanup assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
}
