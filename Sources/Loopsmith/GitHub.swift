import Foundation

struct PullRequest: Identifiable, Decodable {
    struct Repository: Decodable { let nameWithOwner: String }
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let repository: Repository
    var id: String { url }
}

/// GitHub through the `gh` CLI, so the user's own login is used.
enum GitHub {
    /// Ensures a URL string uses `https://` before opening it in the user's browser.
    static func safeHTTPSURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func authStatus() async -> String {
        let r = await Shell.run(["gh", "auth", "status"])
        return (r.out + r.err).trimmed.nonEmpty ?? "gh not found: install it with `brew install gh`"
    }

    static func myOpenPullRequests() async throws -> [PullRequest] {
        let out = try await Shell.check(["gh", "search", "prs", "--author=@me", "--state=open",
                                         "--json", "number,title,url,isDraft,repository", "--limit", "50"])
        return try JSONDecoder().decode([PullRequest].self, from: Data(out.utf8))
    }

    /// Opens the pull request and returns its URL.
    static func createPullRequest(worktree: String, base: String, branch: String, title: String, body: String, draft: Bool) async throws -> String {
        guard Git.isSafeRef(base), Git.isSafeRef(branch) else {
            throw AppError("Invalid base or head branch name.")
        }
        var args = ["gh", "pr", "create", "--base", base, "--head", branch, "--title", title, "--body", body]
        if draft { args.append("--draft") }
        let out = try await Shell.check(args, cwd: worktree)
        return out.split(separator: "\n").last.map(String.init) ?? out
    }
}
