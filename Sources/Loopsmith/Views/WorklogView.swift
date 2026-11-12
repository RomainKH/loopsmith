import SwiftUI

/// The day's Jira worklogs on this project's tickets, the day's total on every project against the daily target,
/// and a way to log more.
struct WorklogView: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var day = Date()
    @State private var logs: [JiraWorklog] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showLogWork = false

    private var projectLogs: [JiraWorklog] { logs.filter { project.owns(issueKey: $0.issueKey) } }
    private var projectTotal: Int { projectLogs.reduce(0) { $0 + $1.seconds } }
    private var dayTotal: Int { logs.reduce(0) { $0 + $1.seconds } }
    private var target: Int { Int(store.settings.dailyHours * 3600) }
    private var progressFraction: Double { min(Double(dayTotal) / Double(max(target, 1)), 1.0) }

    var body: some View {
        ZStack {
            ForgeCanvasBackground(accent: Brand.copper)

            if store.jira.isConfigured {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForgeCard(padding: 18, cornerRadius: 14, tint: Brand.copper) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .center, spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Brand.copper.opacity(0.18))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(Brand.copper)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Jira Worklog")
                                            .font(.title2.weight(.bold))
                                        Text("Daily time logged on \(project.name) and across all projects.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    DatePicker("Day", selection: $day, displayedComponents: .date)
                                        .labelsHidden()
                                    Button {
                                        showLogWork = true
                                    } label: {
                                        Label("Log work", systemImage: "plus")
                                            .font(.callout.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                }

                                Divider().opacity(0.5)

                                HStack(spacing: 32) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("ON \(project.name.uppercased())")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Text(Jira.formatDuration(projectTotal))
                                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("ALL PROJECTS TODAY")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Jira.formatDuration(dayTotal)) / \(Jira.formatDuration(target))")
                                                .font(.caption.monospacedDigit().weight(.semibold))
                                                .foregroundStyle(dayTotal >= target ? Brand.emerald : Brand.amber)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(.quaternary.opacity(0.6))
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: dayTotal >= target ? [Brand.emerald, Brand.emerald.opacity(0.8)] : [Brand.copper, Brand.amber],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: max(geo.size.width * progressFraction, 6))
                                            }
                                        }
                                        .frame(height: 8)
                                    }
                                    .frame(maxWidth: 340)
                                }

                                if project.jiraKeyList.isEmpty {
                                    Label("Every ticket counts for this project until you set its Jira keys in Overview.", systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let error {
                            ForgeCard(padding: 14, cornerRadius: 11, tint: Brand.crimson) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Brand.crimson)
                                    .textSelection(.enabled)
                            }
                        }

                        if !projectLogs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForgeSectionHeader(
                                    title: "Entries (\(projectLogs.count))",
                                    icon: "list.bullet.rectangle.portrait.fill",
                                    tint: Brand.copper
                                )
                                .padding(.horizontal, 4)

                                ForEach(projectLogs) { log in
                                    ForgeCard(padding: 13, cornerRadius: 11) {
                                        HStack(alignment: .center, spacing: 12) {
                                            ForgeCodeChip(
                                                text: log.started.formatted(date: .omitted, time: .shortened),
                                                icon: "clock",
                                                tint: Brand.copper
                                            )
                                            if let url = store.jira.browseURL(log.issueKey) {
                                                Link(destination: url) {
                                                    PhaseBadge(text: log.issueKey, tint: Brand.amber, icon: "arrow.up.right.square")
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                PhaseBadge(text: log.issueKey, tint: Brand.amber)
                                            }
                                            Text(log.comment.isEmpty ? "No comment" : log.comment)
                                                .font(.callout)
                                                .foregroundStyle(log.comment.isEmpty ? .tertiary : .primary)
                                                .lineLimit(2)
                                            Spacer()
                                            Text(Jira.formatDuration(log.seconds))
                                                .font(.callout.monospacedDigit().weight(.bold))
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(Brand.copper.opacity(0.14), in: Capsule())
                                                .foregroundStyle(Brand.copper)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1020, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .overlay {
                    if loading && projectLogs.isEmpty {
                        ProgressView("Loading Jira worklogs…")
                    } else if projectLogs.isEmpty && error == nil {
                        ContentUnavailableView("Nothing logged on this project", systemImage: "clock")
                    }
                }
                .task(id: day) { await load() }
                .sheet(isPresented: $showLogWork) {
                    LogWorkSheet(issueKey: "", comment: "", start: logs.max { $0.end < $1.end }?.end ?? nineAM,
                                 owns: { project.owns(issueKey: $0) }) { Task { await load() } }
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
    /// Which tickets the "My issues" menu lists (a project's own).
    var owns: (String) -> Bool = { _ in true }
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
                    ForEach(store.issues.filter { owns($0.key) }) { issue in Button("\(issue.key) · \(issue.summary)") { issueKey = issue.key } }
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
