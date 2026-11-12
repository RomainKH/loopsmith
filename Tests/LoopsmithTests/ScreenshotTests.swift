#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Loopsmith

/// Renders the README screenshots from the real views, on a made-up project, without screen recording permission:
/// LOOPSMITH_HOME=$(mktemp -d) LOOPSMITH_SCREENSHOTS=docs/screenshots swift test --filter Screenshots
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LOOPSMITH_SCREENSHOTS"] != nil))
@MainActor struct ScreenshotTests {
    @Test func readmeScreenshots() async throws {
        // A separate home: the demo never touches your projects, settings or keychain.
        _ = try #require(ProcessInfo.processInfo.environment["LOOPSMITH_HOME"])
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LOOPSMITH_SCREENSHOTS"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (store, project, waiting) = Demo.store()
        try await snapshot(ProjectWorkspace(project: project, selection: .overview), store: store,
                           size: CGSize(width: 1320, height: 860), to: folder.appendingPathComponent("overview.png"))
        try await snapshot(ProjectWorkspace(project: project, selection: .feature(waiting)), store: store,
                           size: CGSize(width: 1320, height: 1000), to: folder.appendingPathComponent("feature.png"))
        try await snapshot(Form { AgentsSetupSections() }.formStyle(.grouped), store: store,
                           size: CGSize(width: 720, height: 1180), to: folder.appendingPathComponent("agents.png"))
    }

    /// Hosts the view in a dark window kept off screen, lets SwiftUI settle, then draws the window at 2x.
    private func snapshot<V: View>(_ view: V, store: AppStore, size: CGSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Loopsmith"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.environment(store).tint(Brand.cobalt))
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.close() }
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        // The window server's copy of our own window (no screen recording permission needed for one's own windows).
        // CGWindowListCreateImage is gone from the macOS 15 SDK headers but still in CoreGraphics.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
        let symbol = try #require(dlsym(handle, "CGWindowListCreateImage"))
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // .null rect: the window's own bounds; 8 = including window; 1 << 0 | 1 << 3 = ignore framing, best resolution.
        let full = try #require(create(.null, 8, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue())
        // 1.4x is sharp in the README and keeps each file under a megabyte.
        let scale = min(1, size.width * 1.4 / CGFloat(full.width))
        let width = Int(CGFloat(full.width) * scale), height = Int(CGFloat(full.height) * scale)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rep = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

/// A made-up shop and four features at different steps, with the agents' runs, findings and approvals.
@MainActor enum Demo {
    static func store() -> (AppStore, Project, UUID) {
        let store = AppStore()
        var settings = Settings()
        settings.worktreesRoot = "~/Loopsmith"
        settings.analysisModel = "claude-opus-5-5"
        settings.devModel = "claude-opus-5-5"
        settings.reviewModel = "agy:gemini-4-argon-high"
        settings.qaModel = "api:ollama/qwen3-coder:30b"
        settings.customPermissionMode = "bypassPermissions"
        settings.endpoints = [ModelEndpoint(name: "ollama", baseURL: "http://localhost:11434",
                                            models: ["devstral:24b", "gpt-oss:20b", "qwen3-coder:30b"])]
        settings.onboarded = true
        store.settings = settings
        store.cliStatuses = [.claude: (true, "2.1.330 (Claude Code)"), .antigravity: (true, "agy 1.5.6")]
        store.cachedAntigravityModels = AgentProvider.antigravity.presetModels
        store.notify(title: "", subtitle: "")
        store.activeToast = nil

        var project = Project(path: "/Users/dev/code/acme-shop", name: "acme-shop", baseBranch: "main")
        project.jiraKeys = "SHOP"
        project.briefUpdatedAt = Date().addingTimeInterval(-86_400 * 3)
        project.brief = """
        ## What the project is
        Acme Shop, the storefront and checkout of an online shop: Next.js 15, React 19, TypeScript, Stripe.

        ## Stack and layout
        - `src/app`: routes (App Router). `src/cart`, `src/checkout`: cart and checkout features.
        - `src/lib`: money, currency, API clients. `tests/`: Vitest unit tests, Playwright end-to-end.

        ## Setup in a fresh worktree
        `pnpm install`, copy `.env.local` (Stripe test keys). No database: the API is mocked with MSW.

        ## Commands
        `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm e2e`. CI gates on lint, typecheck and test.

        ## Conventions
        Money is in integer cents (`Money` type), never floats. Feature flags in `src/lib/flags.ts`.
        """
        store.projects = [project]

        let waiting = feature("Free shipping progress bar", key: "SHOP-142", slug: "shop-142-free-shipping-progress-bar",
                              minutesAgo: 95, phase: .fixReview,
                              prompt: "Under the cart summary, show how much is left before free shipping (from €50) with a progress bar, then \"Free shipping unlocked\". Same bar in the mini cart.") { f in
            f.analysis = analysis
            f.runs = [
                run(.analysis, "Feasibility", "claude-opus-5-5", minutesAgo: 94, seconds: 141, tokens: 61_200, cost: 0.41,
                    log: ["→ Read src/cart/CartSummary.tsx", "→ Grep freeShipping", "→ Read src/lib/money.ts"],
                    summary: analysis.summary),
                run(.dev, "Implementation", "claude-opus-5-5", minutesAgo: 80, seconds: 512, tokens: 284_000, cost: 2.37,
                    log: ["I'll add the bar next to the cart summary and keep the threshold in the shipping config.",
                          "→ Read src/cart/CartSummary.tsx", "→ Write src/cart/FreeShippingBar.tsx",
                          "→ Edit src/cart/CartSummary.tsx", "→ Write tests/cart/FreeShippingBar.test.tsx",
                          "→ Bash pnpm test -- FreeShippingBar", "→ Bash pnpm typecheck"],
                    summary: "- New `FreeShippingBar` under the cart summary: amount left, progress, then \"Free shipping unlocked\".\n- Threshold from `shippingConfig.freeShippingFrom`.\n- 6 unit tests; `pnpm test` and `pnpm typecheck` pass."),
                run(.review, "Correctness", "agy:gemini-4-argon-high", minutesAgo: 66, seconds: 203, tokens: 97_400, cost: nil,
                    log: ["→ run_command git diff 4f1c2ab", "→ view_file src/cart/FreeShippingBar.tsx", "→ view_file src/cart/useCart.ts"],
                    summary: "One real bug: the bar flashes \"unlocked\" while the cart loads.", findings: [findings[0]]),
                run(.review, "Spec & standards", "agy:gemini-4-argon-high", minutesAgo: 66, seconds: 176, tokens: 88_900, cost: nil,
                    log: ["→ run_command git diff 4f1c2ab", "→ view_file src/lib/money.ts"],
                    summary: "Matches the ticket; the threshold ignores the shopper's currency.", findings: [findings[1], findings[2]]),
            ]
            f.pending = [findings[0], findings[1]]
            f.awaitingApproval = true
        }

        let review = feature("Guest checkout email validation", key: "SHOP-151", slug: "shop-151-guest-checkout-email-validation",
                             minutesAgo: 40, phase: .review,
                             prompt: "Validate the guest email on blur and on submit, with the message under the field.") { f in
            f.runs = [
                run(.analysis, "Feasibility", "claude-opus-5-5", minutesAgo: 39, seconds: 98, tokens: 44_800, cost: 0.29,
                    log: ["→ Read src/checkout/GuestForm.tsx"], summary: "Feasible: validate on blur with the existing zod schema."),
                run(.dev, "Implementation", "claude-opus-5-5", minutesAgo: 30, seconds: 341, tokens: 151_000, cost: 1.12,
                    log: ["→ Edit src/checkout/GuestForm.tsx", "→ Bash pnpm test -- GuestForm"],
                    summary: "- Email checked on blur and on submit with `guestSchema`.\n- Error message under the field; 4 tests."),
            ]
            f.awaitingApproval = true
        }

        let ready = feature("Wishlist share links", key: "SHOP-133", slug: "shop-133-wishlist-share-links",
                            minutesAgo: 300, phase: .ready,
                            prompt: "Let shoppers share their wishlist with a read-only link.") { f in
            f.reviewFixes = 1
            f.runs = [
                run(.analysis, "Feasibility", "claude-opus-5-5", minutesAgo: 299, seconds: 120, tokens: 52_000, cost: 0.35),
                run(.dev, "Implementation", "claude-opus-5-5", minutesAgo: 290, seconds: 600, tokens: 310_000, cost: 2.81),
                run(.review, "Correctness", "agy:gemini-4-argon-high", minutesAgo: 270, seconds: 190, tokens: 90_000, cost: nil),
                run(.review, "Spec & standards", "agy:gemini-4-argon-high", minutesAgo: 270, seconds: 160, tokens: 81_000, cost: nil),
                run(.dev, "Fix · review round 1", "claude-opus-5-5", minutesAgo: 255, seconds: 240, tokens: 120_000, cost: 0.92),
                run(.review, "Correctness", "agy:gemini-4-argon-high", minutesAgo: 245, seconds: 150, tokens: 70_000, cost: nil),
                run(.review, "Spec & standards", "agy:gemini-4-argon-high", minutesAgo: 245, seconds: 140, tokens: 66_000, cost: nil),
                run(.qa, "Quality gates", "api:ollama/qwen3-coder:30b", minutesAgo: 230, seconds: 420, tokens: 140_000, cost: nil),
                run(.qa, "Behaviour", "api:ollama/qwen3-coder:30b", minutesAgo: 230, seconds: 380, tokens: 128_000, cost: nil),
            ]
        }

        let shipped = feature("Fix rounding of cart totals", key: "SHOP-120", slug: "shop-120-fix-rounding-of-cart-totals",
                              minutesAgo: 1_500, phase: .prOpened,
                              prompt: "Cart totals are off by a cent with three or more discounted items.") { f in
            f.prURL = "https://github.com/acme/shop/pull/412"
            f.runs = [
                run(.analysis, "Feasibility", "claude-opus-5-5", minutesAgo: 1_499, seconds: 90, tokens: 40_000, cost: 0.27),
                run(.dev, "Implementation", "claude-opus-5-5", minutesAgo: 1_490, seconds: 420, tokens: 200_000, cost: 1.65),
            ]
        }

        store.features = [waiting, review, ready, shipped]
        return (store, project, waiting.id)
    }

    static let analysis = Analysis(
        feasibility: "feasible",
        summary: "Show how much is left before free shipping under the cart summary, and celebrate once it is reached.",
        approach: "Add a `FreeShippingBar` component fed by `useCart()`, read the threshold from `shippingConfig`, and render it in `CartSummary` and the mini cart.",
        impacted: ["src/cart/CartSummary.tsx: renders the bar", "src/cart/shipping.ts: threshold and currency",
                   "src/components/MiniCart.tsx: same bar, compact"],
        risks: ["The cart total is 0 until `useCart` resolves", "Totals are in the shopper's currency, the threshold in EUR",
                "Discount codes change the total after the bar renders"],
        assumptions: ["The threshold applies to the total after discounts, before shipping"],
        acceptanceCriteria: ["Under €50 the bar shows the amount left and the progress",
                             "At €50 or more it shows \"Free shipping unlocked\"", "Nothing flashes while the cart loads"])

    static let findings = [
        Finding(severity: "major", file: "src/cart/FreeShippingBar.tsx", line: 38,
                title: "Shows \"unlocked\" while the cart is loading",
                detail: "`total` is 0 until `useCart` resolves, so the bar briefly renders the wrong state. Render nothing while `isLoading`."),
        Finding(severity: "major", file: "src/cart/shipping.ts", line: 12,
                title: "Threshold compared across currencies",
                detail: "The €50 threshold is compared with totals in the shopper's currency. Convert with `toBaseCurrency`, as `computeTax` does."),
        Finding(severity: "minor", file: "src/cart/FreeShippingBar.tsx", line: 9,
                title: "Progress not exposed to screen readers",
                detail: "Add `role=\"progressbar\"` with `aria-valuenow`."),
    ]

    static func feature(_ title: String, key: String, slug: String, minutesAgo: Double, phase: Phase, prompt: String,
                        _ change: (inout Feature) -> Void) -> Feature {
        var f = Feature(title: title, prompt: prompt, jiraKey: key, jiraContext: nil, repoPath: "/Users/dev/code/acme-shop",
                        baseBranch: "main", baseCommit: "4f1c2ab9d0e6", branch: "feat/\(slug)",
                        worktreePath: "/Users/dev/Loopsmith/acme-shop/\(slug)", disabledMCP: [], disabledSkills: [])
        f.createdAt = Date().addingTimeInterval(-minutesAgo * 60)
        f.phase = phase
        change(&f)
        return f
    }

    static func run(_ role: Role, _ lens: String, _ model: String, minutesAgo: Double, seconds: Double, tokens: Int,
                    cost: Double?, log: [String] = [], summary: String? = nil, findings: [Finding]? = nil) -> AgentRun {
        var r = AgentRun(role: role, lens: lens, model: model)
        r.startedAt = Date().addingTimeInterval(-minutesAgo * 60)
        r.endedAt = r.startedAt.addingTimeInterval(seconds)
        r.status = .done
        r.tokens = tokens
        r.cost = cost
        for line in log { r.append(log: line) }
        r.summary = summary ?? (role == .review || role == .qa ? "No blocking problem." : "Done.")
        r.findings = findings ?? ((role == .review || role == .qa) ? [] : nil)
        return r
    }
}
#endif
