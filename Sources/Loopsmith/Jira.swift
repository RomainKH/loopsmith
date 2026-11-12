import Foundation

struct JiraIssue: Identifiable, Hashable {
    let key: String
    let summary: String
    let status: String
    var id: String { key }
}

struct JiraWorklog: Identifiable {
    let id: String
    let issueKey: String
    let started: Date
    let seconds: Int
    let comment: String
    var end: Date { started.addingTimeInterval(TimeInterval(seconds)) }
}

/// Jira Cloud REST client (email + API token, basic auth over HTTPS only).
struct Jira {
    var site: String
    var email: String
    var token: String

    var isConfigured: Bool { validatedBaseURL != nil && !email.trimmed.isEmpty && !token.isEmpty }

    private static let issueKeyRegex = try! Regex(#"^[A-Z][A-Z0-9_]{0,31}-\d{1,10}$"#)

    /// Strictly validates a Jira issue key (`PROJ-123`) to prevent URL path traversal or parameter injection.
    static func isValidIssueKey(_ key: String) -> Bool {
        let trimmed = key.trimmed.uppercased()
        return trimmed.wholeMatch(of: issueKeyRegex) != nil
    }

    /// Enforces HTTPS and rejects malformed hosts, credentials in URLs, or private/metadata SSRF hosts.
    var validatedBaseURL: URL? {
        var raw = site.trimmed
        guard !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://") {
            return nil // Never transmit Basic Auth API tokens over cleartext HTTP
        }
        if !raw.lowercased().hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty,
              let host = components.host?.lowercased(),
              host.contains("."),
              !Self.isBlockedHost(host),
              let url = components.url else {
            return nil
        }
        return url
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("169.254.") || host.hasPrefix("192.168.") || host == "0.0.0.0" {
            return true
        }
        return false
    }

    var baseURL: String {
        validatedBaseURL?.absoluteString ?? ""
    }

    func browseURL(_ key: String) -> URL? {
        let cleanKey = key.trimmed.uppercased()
        guard Self.isValidIssueKey(cleanKey), let base = validatedBaseURL else { return nil }
        return base.appendingPathComponent("browse").appendingPathComponent(cleanKey)
    }

    private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        guard let base = validatedBaseURL, let url = URL(string: base.absoluteString + path), url.scheme == "https" else {
            throw AppError("Invalid or insecure Jira site (HTTPS required): \(site)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Basic " + Data("\(email.trimmed):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AppError("Jira answered \(code): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return data.isEmpty ? [String: Any]() : try JSONSerialization.jsonObject(with: data)
    }

    /// Display name and account id of the token's owner.
    func myself() async throws -> (name: String, accountId: String) {
        let obj = try await call("/rest/api/3/myself") as? [String: Any] ?? [:]
        return (obj["displayName"] as? String ?? "", obj["accountId"] as? String ?? "")
    }

    func search(_ jql: String) async throws -> [JiraIssue] {
        let obj = try await call("/rest/api/3/search/jql", method: "POST",
                                 body: ["jql": jql, "fields": ["summary", "status"], "maxResults": 100]) as? [String: Any]
        return (obj?["issues"] as? [[String: Any]] ?? []).compactMap { issue in
            guard let key = issue["key"] as? String, Self.isValidIssueKey(key) else { return nil }
            let fields = issue["fields"] as? [String: Any]
            return JiraIssue(key: key,
                             summary: fields?["summary"] as? String ?? "",
                             status: (fields?["status"] as? [String: Any])?["name"] as? String ?? "")
        }
    }

    /// Summary and description of a ticket, as plain text for the agents (API v2 gives the description as text).
    func issueContext(_ key: String) async throws -> String {
        let cleanKey = key.trimmed.uppercased()
        guard Self.isValidIssueKey(cleanKey) else { throw AppError("Invalid Jira issue key: \(key)") }
        let obj = try await call("/rest/api/2/issue/\(cleanKey)?fields=summary,description") as? [String: Any]
        let fields = obj?["fields"] as? [String: Any]
        let summary = fields?["summary"] as? String ?? ""
        let description = fields?["description"] as? String ?? ""
        return "\(cleanKey): \(summary)\n\n\(description)".trimmed
    }

    /// The token owner's worklogs started on `day` (local time zone).
    func worklogs(on day: Date) async throws -> [JiraWorklog] {
        let me = try await myself()
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let dayText = Self.dayFormatter.string(from: start)
        let issues = try await search("worklogDate = \"\(dayText)\" AND worklogAuthor = currentUser()")
        var logs: [JiraWorklog] = []
        for issue in issues where Self.isValidIssueKey(issue.key) {
            let after = Int(start.timeIntervalSince1970 * 1000), before = Int(end.timeIntervalSince1970 * 1000)
            let obj = try await call("/rest/api/2/issue/\(issue.key)/worklog?startedAfter=\(after)&startedBefore=\(before)") as? [String: Any]
            for log in obj?["worklogs"] as? [[String: Any]] ?? [] {
                guard (log["author"] as? [String: Any])?["accountId"] as? String == me.accountId,
                      let startedText = log["started"] as? String,
                      let started = Self.startedFormatter.date(from: startedText),
                      started >= start, started < end else { continue }
                logs.append(JiraWorklog(id: log["id"] as? String ?? UUID().uuidString,
                                        issueKey: issue.key,
                                        started: started,
                                        seconds: log["timeSpentSeconds"] as? Int ?? 0,
                                        comment: log["comment"] as? String ?? ""))
            }
        }
        return logs.sorted { $0.started < $1.started }
    }

    func addWorklog(issue: String, started: Date, seconds: Int, comment: String) async throws {
        let cleanKey = issue.trimmed.uppercased()
        guard Self.isValidIssueKey(cleanKey) else { throw AppError("Invalid Jira issue key: \(issue)") }
        _ = try await call("/rest/api/2/issue/\(cleanKey)/worklog", method: "POST",
                           body: ["started": Self.startedFormatter.string(from: started),
                                  "timeSpentSeconds": seconds,
                                  "comment": comment])
    }

    static let startedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "1h 30m", "1h30", "45m", "2h", "1.5h" or "90" (minutes) → seconds.
    static func parseDuration(_ text: String) -> Int? {
        let regex = try! Regex(#"(\d+(?:[.,]\d+)?)\s*([hm]?)"#)
        var total = 0.0
        for match in text.lowercased().matches(of: regex) {
            guard let number = match.output[1].substring, let value = Double(number.replacingOccurrences(of: ",", with: ".")) else { continue }
            total += match.output[2].substring == "h" ? value * 3600 : value * 60
        }
        return total > 0 ? Int(total.rounded()) : nil
    }

    static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }
}
