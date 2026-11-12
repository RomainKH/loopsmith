import Foundation

enum Git {
    /// Rejects ref or branch names that could be interpreted as git flags (`-…`) or traverse paths (`..`, control chars).
    static func isSafeRef(_ ref: String) -> Bool {
        let trimmed = ref.trimmed
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("-"),
              !trimmed.hasPrefix("/"),
              !trimmed.hasSuffix("/"),
              !trimmed.hasSuffix(".lock"),
              !trimmed.contains(".."),
              !trimmed.contains("@{") else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines
            .union(.controlCharacters)
            .union(CharacterSet(charactersIn: "\\~^:?*["))
        return trimmed.rangeOfCharacter(from: forbidden) == nil
    }

    static func isRepo(_ path: String) async -> Bool {
        await Shell.run(["git", "-C", path, "rev-parse", "--git-dir"]).ok
    }

    static func defaultBranch(repo: String) async -> String {
        let name = await Shell.run(["git", "-C", repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"]).out.trimmed
        let branch = name.hasPrefix("origin/") ? String(name.dropFirst("origin/".count)) : "main"
        return isSafeRef(branch) ? branch : "main"
    }

    /// Creates the feature's worktree from the freshest base it can reach and returns the base commit.
    static func addWorktree(repo: String, base: String, branch: String, path: String) async throws -> String {
        guard isSafeRef(base) else { throw AppError("Invalid base branch name: \(base)") }
        guard isSafeRef(branch) else { throw AppError("Invalid feature branch name: \(branch)") }
        _ = await Shell.run(["git", "-C", repo, "fetch", "origin", "--", base])
        let remoteFound = await Shell.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet", "origin/\(base)^{commit}"]).ok
        let start = remoteFound ? "origin/\(base)" : base
        let commit = try await Shell.check(["git", "-C", repo, "rev-parse", "--verify", "\(start)^{commit}"])
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try await Shell.check(["git", "-C", repo, "worktree", "add", "-b", branch, "--", path, commit])
        return commit
    }

    /// Refuses a worktree with uncommitted changes (git's own check): nothing is lost by mistake.
    static func removeWorktree(repo: String, path: String) async throws {
        try await Shell.check(["git", "-C", repo, "worktree", "remove", "--", path])
    }

    static func commitAndPush(worktree: String, branch: String, message: String) async throws {
        guard isSafeRef(branch) else { throw AppError("Invalid branch name: \(branch)") }
        try await Shell.check(["git", "-C", worktree, "add", "-A"])
        // `diff --cached --quiet` exits 1 when something is staged.
        if await Shell.run(["git", "-C", worktree, "diff", "--cached", "--quiet"]).status == 1 {
            try await Shell.check(["git", "-C", worktree, "commit", "-m", message])
        }
        try await Shell.check(["git", "-C", worktree, "push", "-u", "origin", "--", branch])
    }

    /// What the agents changed: tracked changes against the base commit, then each new file.
    static func diff(worktree: String, base: String) async -> String {
        guard isSafeRef(base) else { return "" }
        var text = await Shell.run(["git", "-C", worktree, "diff", base, "--"]).out
        let untracked = await Shell.run(["git", "-C", worktree, "ls-files", "--others", "--exclude-standard"]).out
        for file in untracked.split(separator: "\n") {
            // `--` prevents an untracked file named `--output=...` from being parsed as a git flag.
            text += await Shell.run(["git", "-C", worktree, "diff", "--no-index", "--", "/dev/null", String(file)]).out
        }
        return text
    }

    /// Branch and folder name: "APP-42 Free shipping bar" → "app-42-free-shipping-bar".
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var slug = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-")
        if slug.count > 48 { slug = String(slug.prefix(48)) }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "feature" : slug
    }
}
