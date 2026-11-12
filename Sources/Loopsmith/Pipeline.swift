import Foundation

enum Pipeline {
    /// After a review or QA round: send the blocking findings back to dev while fix rounds are left,
    /// otherwise move on and keep them as open points for the pull request.
    static func afterRound(_ findings: [Finding], fixesDone: Int, maxFixes: Int) -> (fix: [Finding], unresolved: [Finding]) {
        let blocking = findings.filter(\.isBlocking)
        if blocking.isEmpty { return ([], []) }
        return fixesDone < maxFixes ? (blocking, []) : ([], blocking)
    }
}

extension AppStore {
    func start(_ id: UUID) {
        guard tasks[id] == nil, let f = feature(id), f.phase != .ready, f.phase != .prOpened else { return }
        update(id) { $0.running = true; $0.error = nil }
        tasks[id] = Task {
            await runPipeline(id)
            tasks[id] = nil
            processes[id] = nil
            update(id) { $0.running = false }
            save()
        }
    }

    func stop(_ id: UUID) {
        tasks[id]?.cancel()
        processes[id]?.forEach { $0.terminate() }
    }

    func stopAll() {
        for id in tasks.keys { stop(id) }
        save()
    }

    /// Runs the phases from where the feature stands, so a stopped or interrupted feature continues where it was.
    private func runPipeline(_ id: UUID) async {
        do {
            while !Task.isCancelled, let f = feature(id) {
                switch f.phase {
                case .analysis:
                    let analysis = try await runAnalysis(id)
                    update(id) { $0.analysis = analysis; $0.phase = .dev }
                    if analysis.isBlocked {
                        update(id) { $0.error = "The analysis says the request is blocked: \(analysis.summary) Continue starts development anyway." }
                        save()
                        return
                    }
                case .dev:
                    try await runDev(id, fixing: nil)
                    update(id) { $0.phase = .review }
                case .review, .qa:
                    let role: Role = f.phase == .review ? .review : .qa
                    let findings = try await runChecks(id, role: role)
                    let fixesDone = role == .review ? f.reviewFixes : f.qaFixes
                    let next = Pipeline.afterRound(findings, fixesDone: fixesDone, maxFixes: settings.maxFixRounds)
                    update(id) {
                        $0.pending = next.fix
                        $0.unresolved += next.unresolved
                        switch (role, next.fix.isEmpty) {
                        case (.review, false): $0.phase = .fixReview
                        case (.review, true): $0.phase = .qa
                        case (_, false): $0.phase = .fixQA
                        case (_, true): $0.phase = .ready
                        }
                    }
                case .fixReview, .fixQA:
                    let role: Role = f.phase == .fixReview ? .review : .qa
                    try await runDev(id, fixing: role)
                    update(id) {
                        $0.pending = []
                        if role == .review { $0.reviewFixes += 1; $0.phase = .review } else { $0.qaFixes += 1; $0.phase = .qa }
                    }
                case .ready, .prOpened:
                    return
                }
                save()
            }
        } catch {
            if !Task.isCancelled { update(id) { $0.error = error.localizedDescription } }
        }
    }

    /// The dev agent: a new session for the first run, the same session for fixes, so it keeps its own context.
    private func runDev(_ id: UUID, fixing role: Role?) async throws {
        guard let f = feature(id) else { return }
        let prompt: String, lens: String
        var resume = f.devSessionId
        if let role {
            let round = (role == .review ? f.reviewFixes : f.qaFixes) + 1
            lens = "Fix · \(role == .review ? "review" : "QA") round \(round)"
            let fix = Agent.fixPrompt(f.pending, from: role)
            prompt = resume == nil ? "\(f.devRequest)\n\n\(fix)" : fix
        } else if resume != nil {
            lens = "Implementation (resumed)"
            prompt = "You were interrupted. Check the state of the worktree and finish the task."
        } else {
            lens = "Implementation"
            prompt = f.devRequest
            resume = nil
        }
        _ = try await runAgent(id, role: .dev, lens: lens, prompt: prompt, system: Agent.devSystemPrompt(f),
                               model: settings.devModel, resume: resume, schema: nil)
    }

    /// Reads the request against the code before any change: feasibility, approach, problems, acceptance criteria.
    private func runAnalysis(_ id: UUID) async throws -> Analysis {
        guard let f = feature(id) else { throw AppError("Feature not found") }
        let (runID, result) = try await runAgent(id, role: .analysis, lens: "Feasibility", prompt: "Analyse this request:\n\n\(f.request)",
                                                 system: Agent.analysisSystemPrompt(f), model: settings.analysisModel,
                                                 resume: nil, schema: Agent.analysisSchema)
        guard let data = result.structured, let analysis = try? JSONDecoder().decode(Analysis.self, from: data) else {
            updateRun(id, runID) { $0.status = .failed; $0.error = "No structured analysis in the answer" }
            throw AppError("The analysis did not return a result")
        }
        updateRun(id, runID) { $0.summary = analysis.summary }
        return analysis
    }

    /// Two agents with no shared context, each from its own lens, in parallel.
    private func runChecks(_ id: UUID, role: Role) async throws -> [Finding] {
        let lenses = role == .review ? Agent.reviewLenses : Agent.qaLenses
        async let first = verdict(id, role: role, lens: lenses[0])
        async let second = verdict(id, role: role, lens: lenses[1])
        let (a, b) = try await (first, second)
        return a.findings + b.findings
    }

    private func verdict(_ id: UUID, role: Role, lens: Lens) async throws -> Verdict {
        guard let f = feature(id) else { throw AppError("Feature not found") }
        let (runID, result) = try await runAgent(id, role: role, lens: lens.name, prompt: Agent.checkPrompt(f, lens: lens),
                                                 system: Agent.checkSystemPrompt(f, role: role),
                                                 model: role == .review ? settings.reviewModel : settings.qaModel,
                                                 resume: nil, schema: Agent.verdictSchema)
        guard let data = result.structured, let verdict = try? JSONDecoder().decode(Verdict.self, from: data) else {
            updateRun(id, runID) { $0.status = .failed; $0.error = "No structured verdict in the answer" }
            throw AppError("\(lens.name) did not return a verdict")
        }
        updateRun(id, runID) { $0.summary = verdict.summary; $0.findings = verdict.findings }
        return verdict
    }

    private func runAgent(_ id: UUID, role: Role, lens: String, prompt: String, system: String, model: String,
                          resume: String?, schema: String?) async throws -> (UUID, AgentResult) {
        guard let f = feature(id) else { throw AppError("Feature not found") }
        let run = AgentRun(role: role, lens: lens, model: model)
        update(id) { $0.runs.append(run) }
        let args = Agent.arguments(model: model, permissionMode: settings.permissionMode,
                                   systemPrompt: Agent.withBrief(system, brief: project(at: f.repoPath)?.brief),
                                   resume: resume, schema: schema, readOnly: role != .dev,
                                   disabledMCP: f.disabledMCP, disabledSkills: f.disabledSkills)
        var result: AgentResult?
        do {
            let exit = try await Shell.stream(args, cwd: f.worktreePath, input: prompt,
                                              register: { self.processes[id, default: []].append($0) }) { line in
                for event in Agent.parse(line) {
                    switch event {
                    case .session(let session):
                        self.updateRun(id, run.id) { $0.sessionId = session }
                        if role == .dev { self.update(id) { $0.devSessionId = session } }
                    case .log(let text):
                        self.updateRun(id, run.id) { $0.append(log: text) }
                    case .result(let r):
                        result = r
                    }
                }
            }
            guard let done = result, !done.isError else {
                throw AppError(result?.text.nonEmpty ?? exit.err.nonEmpty?.trimmed ?? "claude stopped with status \(exit.status)")
            }
            updateRun(id, run.id) { $0.status = .done; $0.summary = done.text; $0.cost = done.cost; $0.endedAt = Date() }
            if role == .dev, let session = done.sessionId { update(id) { $0.devSessionId = session } }
            save()
            return (run.id, done)
        } catch {
            let stopped = Task.isCancelled
            updateRun(id, run.id) {
                $0.status = stopped ? .stopped : .failed
                $0.error = stopped ? nil : error.localizedDescription
                $0.endedAt = Date()
            }
            throw error
        }
    }
}

extension AppStore {
    /// Has an agent read the project and write the brief every agent of its features gets.
    func scanProject(_ id: UUID) {
        guard let p = project(id), !p.scanning else { return }
        updateProject(id) { $0.scanning = true; $0.scanError = nil; $0.scanLog = [] }
        tasks[id] = Task {
            await runScan(id)
            tasks[id] = nil
            processes[id] = nil
            updateProject(id) { $0.scanning = false }
            save()
        }
    }

    private func runScan(_ id: UUID) async {
        guard let p = project(id) else { return }
        let args = Agent.arguments(model: settings.analysisModel, permissionMode: settings.permissionMode,
                                   systemPrompt: Agent.projectBriefSystemPrompt, resume: nil, schema: nil, readOnly: true,
                                   disabledMCP: p.disabledMCP, disabledSkills: p.disabledSkills)
        var result: AgentResult?
        do {
            let exit = try await Shell.stream(args, cwd: p.path, input: "Write the brief of this repository.",
                                              register: { self.processes[id, default: []].append($0) }) { line in
                for event in Agent.parse(line) {
                    switch event {
                    case .log(let text): self.updateProject(id) { $0.scanLog.append(text) }
                    case .result(let r): result = r
                    case .session: break
                    }
                }
            }
            guard let done = result, !done.isError, let brief = done.text.nonEmpty else {
                throw AppError(result?.text.nonEmpty ?? exit.err.nonEmpty?.trimmed ?? "claude stopped with status \(exit.status)")
            }
            updateProject(id) { $0.brief = brief.trimmed; $0.briefUpdatedAt = Date() }
        } catch {
            if !Task.isCancelled { updateProject(id) { $0.scanError = error.localizedDescription } }
        }
    }
}
