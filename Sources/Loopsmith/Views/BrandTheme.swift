#if os(macOS)
import AppKit
import SwiftUI

/// Loopsmith "Icy Steel & Cobalt" Brand & Design System tokens.
enum Brand {
    static let tagline = "Autonomous AI feature forge: from prompt to verified Pull Request."

    // MARK: Core Palette (Matte Carbon, Cool Slate & Icy Brushed Steel)
    static let obsidian = Color(red: 0.063, green: 0.071, blue: 0.090)   // #101217 (Deep Midnight Carbon)
    static let charcoal = Color(red: 0.098, green: 0.110, blue: 0.141)   // #191C24 (Cool Slate Charcoal)
    static let slate    = Color(red: 0.141, green: 0.157, blue: 0.200)   // #242833 (Brushed Dark Titanium)
    static let steel    = Color(red: 0.855, green: 0.886, blue: 0.937)   // #DAE2EF (Icy Brushed Steel)
    static let titanium = Color(red: 0.612, green: 0.667, blue: 0.765)   // #9CAAC3 (Cool Metallic Silver)
    static let surface  = Color(nsColor: .controlBackgroundColor)

    // MARK: Accents (Linear / Arc style: Electric Cobalt, Indigo & Glacier Cyan — zero yellow)
    static let cobalt   = Color(red: 0.345, green: 0.514, blue: 0.976)   // #5883F9 (Primary Electric Cobalt)
    static let indigo   = Color(red: 0.518, green: 0.455, blue: 0.965)   // #8474F6 (Deep Ultraviolet Indigo)
    static let cyan     = Color(red: 0.275, green: 0.690, blue: 0.925)   // #46B0EC (Glacier Cyan)
    static let claude   = Color(red: 0.640, green: 0.540, blue: 0.950)   // #A38AF2 (Cool Violet for Claude)
    static let gemini   = Color(red: 0.275, green: 0.690, blue: 0.925)   // #46B0EC (Glacier Cyan for Gemini)
    static let emerald  = Color(red: 0.157, green: 0.745, blue: 0.565)   // #28BE90 (Cool Mint Emerald)
    static let crimson  = Color(red: 0.925, green: 0.310, blue: 0.380)   // #EC4F61 (Cool Rose Crimson)

    // Legacy aliases mapped to the Icy Steel & Cobalt palette (zero yellow)
    static let amber    = cobalt
    static let copper   = cyan

    static func providerColor(_ provider: AgentProvider) -> Color {
        switch provider {
        case .claude: claude
        case .gemini: gemini
        case .antigravity: cobalt
        case .custom: emerald
        }
    }

    /// Generates the minimalist sculpted Blacksmith Anvil Dock icon at runtime (no outlines, no color mixes).
    static func makeAppIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        let s = size / 1024.0
        let cs = CGColorSpaceCreateDeviceRGB()
        let pad = 100.0 * s
        let rect = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
        let radius = 185.0 * s
        let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()

        let bgColors = [
            CGColor(red: 0.125, green: 0.130, blue: 0.145, alpha: 1.0),
            CGColor(red: 0.070, green: 0.073, blue: 0.082, alpha: 1.0)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: size * 0.5, y: size - pad), end: CGPoint(x: size * 0.5, y: pad), options: [])
        }

        // Centered Blacksmith Anvil (No outline)
        let anvil = CGMutablePath()
        anvil.move(to: CGPoint(x: 310 * s, y: 310 * s))
        anvil.addLine(to: CGPoint(x: 726 * s, y: 310 * s))
        anvil.addLine(to: CGPoint(x: 696 * s, y: 362 * s))
        anvil.addQuadCurve(to: CGPoint(x: 616 * s, y: 492 * s), control: CGPoint(x: 598 * s, y: 416 * s))
        anvil.addLine(to: CGPoint(x: 760 * s, y: 492 * s))
        anvil.addLine(to: CGPoint(x: 760 * s, y: 586 * s))
        anvil.addLine(to: CGPoint(x: 418 * s, y: 586 * s))
        anvil.addLine(to: CGPoint(x: 404 * s, y: 564 * s))
        anvil.addLine(to: CGPoint(x: 224 * s, y: 556 * s))
        anvil.addQuadCurve(to: CGPoint(x: 422 * s, y: 472 * s), control: CGPoint(x: 300 * s, y: 482 * s))
        anvil.addQuadCurve(to: CGPoint(x: 340 * s, y: 362 * s), control: CGPoint(x: 434 * s, y: 412 * s))
        anvil.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16 * s), blur: 32 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        ctx.setFillColor(CGColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1.0))
        ctx.addPath(anvil)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(anvil)
        ctx.clip()
        let anvilColors = [
            CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0),
            CGColor(red: 0.76, green: 0.79, blue: 0.84, alpha: 1.0),
            CGColor(red: 0.54, green: 0.57, blue: 0.63, alpha: 1.0)
        ] as CFArray
        if let anvilGrad = CGGradient(colorsSpace: cs, colors: anvilColors, locations: [0.0, 0.48, 1.0]) {
            ctx.drawLinearGradient(anvilGrad, start: CGPoint(x: 512 * s, y: 586 * s), end: CGPoint(x: 512 * s, y: 310 * s), options: [])
        }

        let lowerFacet = CGMutablePath()
        lowerFacet.move(to: CGPoint(x: 310 * s, y: 310 * s))
        lowerFacet.addLine(to: CGPoint(x: 726 * s, y: 310 * s))
        lowerFacet.addLine(to: CGPoint(x: 696 * s, y: 362 * s))
        lowerFacet.addLine(to: CGPoint(x: 340 * s, y: 362 * s))
        lowerFacet.closeSubpath()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.14))
        ctx.addPath(lowerFacet)
        ctx.fillPath()

        let hardyRect = CGRect(x: 668 * s, y: 530 * s, width: 34 * s, height: 24 * s)
        let hardyPath = CGPath(roundedRect: hardyRect, cornerWidth: 5 * s, cornerHeight: 5 * s, transform: nil)
        ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 0.75))
        ctx.addPath(hardyPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
        ctx.setLineWidth(3 * s)
        ctx.addPath(bgPath)
        ctx.strokePath()
        ctx.restoreGState()

        image.unlockFocus()
        return image
    }
}

/// Vector SwiftUI rendering of the minimalist Loopsmith Anvil emblem (solid brushed steel on matte carbon, no outlines).
struct LoopsmithLogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let s = min(w, h) / 100.0

            // Squircle Background
            let rect = CGRect(x: 2 * s, y: 2 * s, width: 96 * s, height: 96 * s)
            let bgPath = Path(roundedRect: rect, cornerRadius: 22 * s, style: .continuous)
            context.fill(
                bgPath,
                with: .linearGradient(
                    Gradient(colors: [Brand.charcoal, Brand.obsidian]),
                    startPoint: CGPoint(x: 50 * s, y: 0),
                    endPoint: CGPoint(x: 50 * s, y: 100 * s)
                )
            )
            context.stroke(bgPath, with: .color(.white.opacity(0.08)), lineWidth: 1 * s)

            // Centered Blacksmith Anvil (y=0 top, y=100 bottom), no stroke
            var anvil = Path()
            anvil.move(to: CGPoint(x: 28 * s, y: 72 * s))
            anvil.addLine(to: CGPoint(x: 75 * s, y: 72 * s))
            anvil.addLine(to: CGPoint(x: 71.5 * s, y: 66 * s))
            anvil.addQuadCurve(to: CGPoint(x: 62.5 * s, y: 51 * s), control: CGPoint(x: 60.5 * s, y: 60 * s))
            anvil.addLine(to: CGPoint(x: 79 * s, y: 51 * s))
            anvil.addLine(to: CGPoint(x: 79 * s, y: 40 * s))
            anvil.addLine(to: CGPoint(x: 40 * s, y: 40 * s))
            anvil.addLine(to: CGPoint(x: 38.5 * s, y: 42.5 * s))
            anvil.addLine(to: CGPoint(x: 18 * s, y: 43.5 * s))
            anvil.addQuadCurve(to: CGPoint(x: 40.5 * s, y: 53 * s), control: CGPoint(x: 26.5 * s, y: 52 * s))
            anvil.addQuadCurve(to: CGPoint(x: 31.5 * s, y: 66 * s), control: CGPoint(x: 42 * s, y: 60 * s))
            anvil.closeSubpath()

            context.fill(
                anvil,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.76, green: 0.79, blue: 0.84),
                        Color(red: 0.54, green: 0.57, blue: 0.63)
                    ]),
                    startPoint: CGPoint(x: 50 * s, y: 40 * s),
                    endPoint: CGPoint(x: 50 * s, y: 72 * s)
                )
            )

            // Foot bevel plane
            var foot = Path()
            foot.move(to: CGPoint(x: 28 * s, y: 72 * s))
            foot.addLine(to: CGPoint(x: 75 * s, y: 72 * s))
            foot.addLine(to: CGPoint(x: 71.5 * s, y: 66 * s))
            foot.addLine(to: CGPoint(x: 31.5 * s, y: 66 * s))
            foot.closeSubpath()
            context.fill(foot, with: .color(.black.opacity(0.14)))

            // Hardy hole
            let hardy = Path(roundedRect: CGRect(x: 68 * s, y: 43.5 * s, width: 4 * s, height: 3 * s), cornerRadius: 0.8 * s)
            context.fill(hardy, with: .color(Brand.obsidian.opacity(0.75)))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.28), radius: size * 0.1, y: 2)
    }
}

struct ProviderBadge: View {
    let model: String
    var showModelName: Bool = true
    var compact: Bool = false

    private var provider: AgentProvider { AgentProvider.detect(from: model) }
    private var tint: Color { Brand.providerColor(provider) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: provider.icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(showModelName ? model : provider.shortLabel)
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .help("\(provider.label) · \(model)")
    }
}

/// Pill badge for a pipeline phase or status.
struct PhaseBadge: View {
    let text: String
    let tint: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
        .foregroundStyle(tint)
    }
}

/// Monospace metadata chip for git branches, Jira keys, or file paths.
struct ForgeCodeChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
        )
        .foregroundStyle(.primary.opacity(0.85))
    }
}

/// Atmospheric background canvas for the "Icy Steel & Cobalt" Art Direction (single-pass GPU gradient).
struct ForgeCanvasBackground: View {
    var accent: Color = Brand.cobalt

    var body: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.06),
                Brand.obsidian.opacity(0.14),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Elevated architectural surface card with cool titanium sheen and specular 1px border (zero offscreen shadow pass).
struct ForgeCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(.background.secondary)
                    .overlay(
                        shape.fill((tint ?? Brand.slate).opacity(tint != nil ? 0.07 : 0.20))
                    )
            )
            .overlay(
                shape.strokeBorder((tint ?? Brand.steel).opacity(tint != nil ? 0.34 : 0.12), lineWidth: 1)
            )
    }
}

/// Dark obsidian console box for streaming CLI logs, diffs, and terminal output.
struct ForgeTerminalBox<Content: View>: View {
    var title: String = "CONSOLE OUTPUT"
    var trailingText: String? = nil
    var statusColor: Color = Brand.amber
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(statusColor.opacity(0.85)).frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.steel.opacity(0.7))
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Brand.steel.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Brand.charcoal)

            Divider().overlay(.white.opacity(0.07))

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.obsidian)
                .foregroundStyle(Brand.steel)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

/// Section header with eyebrow label and icon.
struct ForgeSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Brand.amber

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.headline)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif
