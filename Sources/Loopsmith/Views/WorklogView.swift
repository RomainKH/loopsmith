import SwiftUI

/// The day's Jira worklogs against the daily target, and a way to log more.
struct WorklogView: View {
    @Environment(AppStore.self) private var store
    @State private var day = Date()
    @State private var logs: [JiraWorklog] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showLogWork = false

    private var total: Int { logs.reduce(0) { $0 + $1.seconds } }
    private var target: Int { Int(store.settings.dailyHours * 3600) }

    var body: some View {
        Group {
            if store.jira.isConfigured {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DatePicker("Day", selection: $day, displayedComponents: .date).labelsHidden()
                        Spacer()
                        Text("\(Jira.formatDuration(total)) / \(Jira.formatDuration(target))")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(total == target ? .green : total > target ? .orange : .primary)
                        Button("Log work") { showLogWork = true }
                    }
                    ProgressView(value: Double(min(total, target)), total: Double(max(target, 1)))
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    List(logs) { log in
                        HStack(alignment: .firstTextBaseline) {
                            Text(log.started.formatted(date: .omitted, time: .shortened)).monospacedDigit().frame(width: 60, alignment: .leading)
                            if let url = store.jira.browseURL(log.issueKey) { Link(log.issueKey, destination: url).frame(width: 90, alignment: .leading) }
                            Text(Jira.formatDuration(log.seconds)).monospacedDigit().frame(width: 60, alignment: .leading)
                            Text(log.comment).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .overlay {
                        if loading { ProgressView() } else if logs.isEmpty && error == nil {
                            ContentUnavailableView("Nothing logged", systemImage: "clock")
                        }
                    }
                }
                .padding(20)
                .task(id: day) { await load() }
                .sheet(isPresented: $showLogWork) {
                    LogWorkSheet(issueKey: "", comment: "", start: logs.last?.end ?? nineAM) { Task { await load() } }
                }
            } else {
                ContentUnavailableView {
                    Label("Connect Jira", systemImage: "link")
                } description: {
                    Text("Add your Jira site, email and API token in Settings to see and log your work.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
            }
        }
        .navigationTitle("Worklog")
    }

    private var nineAM: Date { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day }

    private func load() async {
        loading = true
        error = nil
        do { logs = try await store.jira.worklogs(on: day) } catch { self.error = error.localizedDescription; logs = [] }
        loading = false
    }
}

struct LogWorkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var issueKey: String
    @State var comment: String
    let start: Date?
    let onLogged: () -> Void
    @State private var started = Date()
    @State private var duration = "1h"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            HStack {
                TextField("Issue", text: $issueKey)
                Menu("My issues") {
                    ForEach(store.issues) { issue in Button("\(issue.key) · \(issue.summary)") { issueKey = issue.key } }
                }
                .fixedSize()
            }
            DatePicker("Started", selection: $started)
            TextField("Time spent", text: $duration, prompt: Text("1h 30m"))
            if let seconds = Jira.parseDuration(duration) {
                LabeledContent("Logged as", value: Jira.formatDuration(seconds))
            }
            TextField("Comment", text: $comment, axis: .vertical).lineLimit(2...5)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "Logging…" : "Log", action: submit)
                    .disabled(busy || issueKey.trimmed.isEmpty || Jira.parseDuration(duration) == nil)
            }
        }
        .task {
            if let start { started = start }
            if store.issues.isEmpty { await store.refreshIssues() }
        }
    }

    private func submit() {
        guard let seconds = Jira.parseDuration(duration) else { return }
        busy = true
        error = nil
        Task {
            do {
                try await store.jira.addWorklog(issue: issueKey.trimmed.uppercased(), started: started, seconds: seconds, comment: comment.trimmed)
                onLogged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}
