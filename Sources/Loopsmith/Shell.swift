import Foundation

struct ShellResult {
    var status: Int32
    var out: String
    var err: String
    var ok: Bool { status == 0 }
}

enum Shell {
    /// Environment of the user's login shell: an app opened from the Finder only gets /usr/bin:/bin,
    /// so claude, gh, node or npm would not be found.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        var path = env["PATH"] ?? "/usr/bin:/bin"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh")
        p.arguments = ["-ilc", "printf '__PATH__%s__PATH__' \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        if (try? p.run()) != nil {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            _ = done.wait(timeout: .now() + 5)
            let parts = text.components(separatedBy: "__PATH__")
            if parts.count >= 3, !parts[1].isEmpty { path = parts[1] }
        }
        let home = NSHomeDirectory()
        env["PATH"] = [path, "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].joined(separator: ":")
        return env
    }()

    private static func process(_ args: [String], cwd: String?) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.environment = environment
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        return p
    }

    /// Starts a process. Its exit status arrives on the returned stream: the handler is set before it starts, so no exit is missed.
    private static func start(_ p: Process) throws -> AsyncStream<Int32> {
        let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
        p.terminationHandler = { exited.yield($0.terminationStatus); exited.finish() }
        try p.run()
        return exits
    }

    /// The exit status, never through waitUntilExit(): it once kept waiting for an agent that had exited (2026-11-12).
    /// A process that is gone without its exit being reported answers -1 instead of hanging.
    private static func exitStatus(of p: Process, _ exits: AsyncStream<Int32>) async -> Int32 {
        let pid = p.processIdentifier
        return await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await exits.first { _ in true } }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    if kill(pid, 0) != 0, errno == ESRCH {
                        // Leave the handler time to report a normal exit first.
                        try? await Task.sleep(for: .seconds(1))
                        return nil
                    }
                }
                return nil
            }
            let status = await group.next() ?? nil
            group.cancelAll()
            return status ?? -1
        }
    }

    /// Blocking read on a GCD thread, so it never holds a Swift concurrency thread.
    private static func readAll(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { c in
            DispatchQueue.global().async { c.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile()) }
        }
    }

    /// Runs a command to the end. A command that cannot start answers status -1.
    static func run(_ args: [String], cwd: String? = nil) async -> ShellResult {
        let p = process(args, cwd: cwd)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let exits: AsyncStream<Int32>
        do { exits = try start(p) } catch { return ShellResult(status: -1, out: "", err: error.localizedDescription) }
        // Both pipes are read at once: a full stderr pipe would block the command forever.
        async let outData = readAll(out)
        async let errData = readAll(err)
        let (o, e) = await (outData, errData)
        return ShellResult(status: await exitStatus(of: p, exits), out: String(decoding: o, as: UTF8.self), err: String(decoding: e, as: UTF8.self))
    }

    /// Runs a command and returns its trimmed output, or throws with its error output.
    @discardableResult
    static func check(_ args: [String], cwd: String? = nil) async throws -> String {
        let r = await run(args, cwd: cwd)
        guard r.ok else {
            let detail = (r.err.nonEmpty ?? r.out).trimmed
            throw AppError("\(args.prefix(3).joined(separator: " ")) failed: \(detail)")
        }
        return r.out.trimmed
    }

    /// Runs a command, writes `input` to its stdin and hands each stdout line to `onLine`.
    /// `register` receives the process as soon as it runs, so it can be stopped.
    static func stream(_ args: [String], cwd: String, input: String,
                       register: @MainActor (Process) -> Void,
                       onLine: @MainActor (String) -> Void) async throws -> ShellResult {
        let p = process(args, cwd: cwd)
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        let exits = try start(p)
        await register(p)
        async let errData = readAll(err)
        try? inp.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try? inp.fileHandleForWriting.close()
        for try await line in out.fileHandleForReading.bytes.lines {
            await onLine(line)
        }
        let errText = String(decoding: await errData, as: UTF8.self)
        return ShellResult(status: await exitStatus(of: p, exits), out: "", err: errText)
    }
}
