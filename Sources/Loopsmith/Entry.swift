import Foundation

enum Loopsmith {
    /// Read by scripts/build-app.sh and the release workflow: bump it here only.
    static let version = "0.2.0"
}

/// One binary for both faces: `loopsmith <command>` runs the command-line interface (every platform),
/// anything else opens the macOS app.
@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        #if os(macOS)
        guard CLI.handles(args) else {
            LoopsmithApp.main()
            return
        }
        #endif
        Task { @MainActor in
            let status = await CLI.run(args)
            exit(status)
        }
        dispatchMain()
    }
}
