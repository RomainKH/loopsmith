import Foundation
import Testing
@testable import Loopsmith

@Suite struct ShellTests {
    /// The command closes its output then lives on: the wait for its exit starts before it exits.
    /// waitUntilExit() on another thread than the launch one never woke up (agent stuck at its end).
    @Test(.timeLimit(.minutes(1))) @MainActor func streamReturnsWhenTheProcessExitsAfterClosingItsOutput() async throws {
        for _ in 0..<5 {
            var lines: [String] = []
            let r = try await Shell.stream(["sh", "-c", "echo hi; exec 1>&- 2>&-; sleep 0.3; exit 3"], cwd: "/", input: "",
                                           register: { _ in }) { lines.append($0) }
            #expect(lines == ["hi"])
            #expect(r.status == 3)
        }
    }

    @Test(.timeLimit(.minutes(1))) func runReturnsTheExitStatusAndBothOutputs() async {
        let r = await Shell.run(["sh", "-c", "echo out; echo err >&2; exit 2"])
        #expect(r.status == 2 && r.out == "out\n" && r.err == "err\n")
    }
}
