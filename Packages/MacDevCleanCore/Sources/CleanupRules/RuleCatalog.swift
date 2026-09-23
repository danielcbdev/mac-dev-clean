import CryptoKit
import Domain
import Foundation

/// One artifact the catalog is willing to call disposable, and why.
public struct RuleMatch: Sendable, Equatable {
    public let ruleID: String
    public let url: URL
    public let category: CleanupCategory
    public let risk: RiskLevel
    public let consequenceKey: String
    /// The project directory or registered cache location this match is
    /// confined to.
    public let allowedRoot: URL
    /// A fingerprint of the evidence that justified the match. Recomputed
    /// before validation and again before execution; a change invalidates the
    /// candidate.
    public let evidenceDigest: String

    public init(
        ruleID: String,
        url: URL,
        category: CleanupCategory,
        risk: RiskLevel,
        consequenceKey: String,
        allowedRoot: URL,
        evidenceDigest: String
    ) {
        self.ruleID = ruleID
        self.url = url
        self.category = category
        self.risk = risk
        self.consequenceKey = consequenceKey
        self.allowedRoot = allowedRoot
        self.evidenceDigest = evidenceDigest
    }
}

/// The declarative catalog of supported developer artifacts.
///
/// It describes and detects. It deletes nothing, and it never executes project
/// code: no package script runs, no JavaScript configuration is evaluated, no
/// repository hook fires. Detection reads a manifest and, for ambiguous
/// directories, asks Git.
///
/// Directory names alone never establish disposability. `node_modules` counts
/// only beside a readable `package.json`; `build` counts only in a project
/// whose `pubspec.yaml` shows Flutter; `dist` counts only when a static
/// configuration declares it as output, Git ignores it, and Git tracks nothing
/// inside it.
public struct RuleCatalog: Sendable {

    public init() {}

    // MARK: - Project rules

    public func matches(
        in project: URL,
        files: any FileSystemClient,
        git: any GitStatusChecking
    ) async throws -> [RuleMatch] {
        var result: [RuleMatch] = []

        let packageManifest = try await Self.readManifest("package.json", in: project, files: files)
        let hasNodeProject = packageManifest.map { Self.isJSONObject($0) } ?? false

        if hasNodeProject, let packageManifest {
            let digest = Self.digest(ruleID: "node.modules", evidence: packageManifest)
            if try await Self.isDirectory("node_modules", in: project, files: files) {
                result.append(
                    RuleMatch(
                        ruleID: "node.modules",
                        url: Self.child(of: project, named: "node_modules"),
                        category: .node,
                        risk: .low,
                        consequenceKey: ConsequenceKey.reinstallDependencies,
                        allowedRoot: project,
                        evidenceDigest: digest
                    )
                )
            }

            if let turbo = try await Self.readManifest("turbo.json", in: project, files: files),
                Self.isJSONObject(turbo),
                try await Self.isDirectory(".turbo", in: project, files: files)
            {
                result.append(
                    RuleMatch(
                        ruleID: "node.turbo",
                        url: Self.child(of: project, named: ".turbo"),
                        category: .node,
                        risk: .low,
                        consequenceKey: ConsequenceKey.rebuildOutput,
                        allowedRoot: project,
                        evidenceDigest: Self.digest(ruleID: "node.turbo", evidence: turbo)
                    )
                )
            }
        }

        if let pubspec = try await Self.readManifest("pubspec.yaml", in: project, files: files),
            Self.declaresFlutter(pubspec)
        {
            let flutterRules: [(String, String, CleanupCategory, String, Bool)] = [
                ("flutter.build", "build", .flutter, ConsequenceKey.rebuildOutput, true),
                ("flutter.dartTool", ".dart_tool", .flutter, ConsequenceKey.rebuildOutput, true),
                (
                    "flutter.plugins", ".flutter-plugins", .flutter, ConsequenceKey.rebuildOutput,
                    false
                ),
                (
                    "flutter.pluginDependencies", ".flutter-plugins-dependencies", .flutter,
                    ConsequenceKey.rebuildOutput, false
                ),
            ]
            for (ruleID, name, category, consequence, mustBeDirectory) in flutterRules {
                let present =
                    mustBeDirectory
                    ? try await Self.isDirectory(name, in: project, files: files)
                    : try await Self.isRegularFile(name, in: project, files: files)
                guard present else { continue }
                result.append(
                    RuleMatch(
                        ruleID: ruleID,
                        url: Self.child(of: project, named: name),
                        category: category,
                        risk: .low,
                        consequenceKey: consequence,
                        allowedRoot: project,
                        evidenceDigest: Self.digest(ruleID: ruleID, evidence: pubspec)
                    )
                )
            }
        }

        if let distMatch = try await webDistMatch(in: project, files: files, git: git) {
            result.append(distMatch)
        }

        return result
    }

    /// `dist` is the dangerous one: plenty of projects commit a built site.
    ///
    /// Three independent facts are required, and any one of them missing means
    /// no candidate:
    ///
    /// 1. a static, plain-JSON configuration declaring `dist` as its output;
    /// 2. Git ignores the directory;
    /// 3. Git tracks nothing inside it.
    ///
    /// If Git cannot answer, the artifact is skipped rather than guessed.
    private func webDistMatch(
        in project: URL,
        files: any FileSystemClient,
        git: any GitStatusChecking
    ) async throws -> RuleMatch? {
        guard try await Self.isDirectory("dist", in: project, files: files) else { return nil }
        guard
            let tsconfig = try await Self.readManifest("tsconfig.json", in: project, files: files),
            Self.declaresDistOutput(tsconfig)
        else {
            return nil
        }

        let dist = Self.child(of: project, named: "dist")
        let repository = project

        // Any Git failure is a skip, never an assumption.
        guard let ignored = try? await git.isIgnored(dist, repository: repository), ignored else {
            return nil
        }
        guard
            let tracked = try? await git.containsTrackedFiles(at: dist, repository: repository),
            !tracked
        else {
            return nil
        }

        return RuleMatch(
            ruleID: "web.dist",
            url: dist,
            category: .webBuild,
            risk: .medium,
            consequenceKey: ConsequenceKey.redeployArtifact,
            allowedRoot: project,
            evidenceDigest: Self.digest(ruleID: "web.dist", evidence: tsconfig)
        )
    }

    // MARK: - Global rules

    public func globalRoots(home: URL) -> [CleanupRuleID: [URL]] {
        var roots: [CleanupRuleID: [URL]] = [:]
        for rule in GlobalCacheRules.all {
            roots[rule.id] = rule.relativePaths.map { home.appendingPathComponent($0) }
        }
        return roots
    }

    // MARK: - Evidence digests

    /// Fingerprint of a project rule's evidence: the rule identifier bound to
    /// the exact manifest bytes that justified it.
    ///
    /// Binding the identifier in means one manifest cannot be replayed as
    /// evidence for a different rule.
    public static func digest(ruleID: CleanupRuleID, evidence: Data) -> String {
        var input = Data(ruleID.utf8)
        input.append(0)
        input.append(evidence)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprint of a global cache rule: it has no manifest, so the evidence
    /// is the registered location itself.
    public static func digest(ruleID: CleanupRuleID, registeredRoot: URL) -> String {
        digest(ruleID: ruleID, evidence: Data(registeredRoot.standardizedFileURL.path.utf8))
    }

    // MARK: - Evidence reading

    private static func readManifest(
        _ name: String,
        in project: URL,
        files: any FileSystemClient
    ) async throws -> Data? {
        try? await files.readPrefix(
            at: child(of: project, named: name),
            limit: maximumEvidenceBytes
        )
    }

    private static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    /// Textual, deliberately conservative: no YAML parser ships with Foundation
    /// and no third-party runtime dependency is allowed. A pubspec counts as
    /// Flutter when it has a top-level `flutter:` section or a `sdk: flutter`
    /// dependency. Anything else is treated as a plain Dart package, whose
    /// `build` directory is left alone.
    private static func declaresFlutter(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "flutter:" { return true }
            if trimmed.replacingOccurrences(of: " ", with: "") == "sdk:flutter" { return true }
        }
        return false
    }

    /// Strict JSON only. A `tsconfig.json` written with comments does not parse
    /// and the directory is left for manual review, which is the safe direction:
    /// stripping comments correctly needs a parser that would also have to get
    /// strings containing `//` right, and being wrong there would delete work.
    private static func declaresDistOutput(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let options = root["compilerOptions"] as? [String: Any],
            let outDir = options["outDir"] as? String
        else {
            return false
        }
        let normalized =
            outDir
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "./", with: "")
        return normalized == "dist" || normalized == "dist/"
    }

    /// One canonical spelling for a child path.
    ///
    /// `appendingPathComponent` stats the filesystem and adds a trailing slash
    /// for an existing directory, so the same location can otherwise be spelled
    /// two ways that do not compare equal.
    static func child(of parent: URL, named name: String) -> URL {
        URL(fileURLWithPath: parent.appendingPathComponent(name).path, isDirectory: false)
    }

    private static func isDirectory(
        _ name: String,
        in project: URL,
        files: any FileSystemClient
    ) async throws -> Bool {
        guard let entry = try? await files.entry(at: child(of: project, named: name)) else {
            return false
        }
        // A symbolic link is never an artifact, whatever it points at.
        return entry.kind == .directory && !entry.isCloudPlaceholder && !entry.isMount
    }

    private static func isRegularFile(
        _ name: String,
        in project: URL,
        files: any FileSystemClient
    ) async throws -> Bool {
        guard let entry = try? await files.entry(at: child(of: project, named: name)) else {
            return false
        }
        return entry.kind == .file && !entry.isCloudPlaceholder
    }
}
