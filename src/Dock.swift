// The dock itself: a column of rows in the bottom-right corner, one per live
// session. Collapsed, a row is a single line — status dot, project, age.
// Hovering opens it and shows what the session last said.
//
// Rows are individual windows anchored at their top-right corner, so an open
// row grows left and down without moving the pointer out of itself, and the
// rows below slide down in the same animation.

import AppKit

enum Layout {
    static let width: CGFloat = 288
    static let rowHeight: CGFloat = 30
    static let detailMax: CGFloat = 26
    static let gap: CGFloat = 6
    static let inset: CGFloat = 12
    /// Codex rounds its own glass panels at 16.
    static let corner: CGFloat = 16
    /// Transparent margin around each card, for the shadow to fall into.
    static let shadowPad: CGFloat = 16
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 24
    /// Shortening this to chase a fast sweep made the movement feel clipped
    /// without making it feel any quicker: the work behind a row opening
    /// measures under a millisecond, so the delay being felt is the travel
    /// itself, not anything waiting to be computed.
    static let duration: TimeInterval = 0.2
}

/// The display the dock lives on: whichever the user pinned, falling back to
/// the one with the menu bar rather than to whichever happens to be focused.
enum Screens {
    static func number(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    static var target: NSScreen? {
        let pinned = Settings.shared.pinnedScreen
        if pinned != 0, let match = NSScreen.screens.first(where: { number($0) == pinned }) {
            return match
        }
        return NSScreen.screens.first ?? NSScreen.main
    }

    static var all: [NSScreen] { NSScreen.screens }
}

enum Palette {
    /// Fully opaque. The glass decides what comes through; fading the window
    /// on top of that only dulled the card and softened its text — a leftover
    /// from when transparency was being chased with an alpha instead.
    static let opacity: CGFloat = 1.0

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The card's own surface, under the blur.
    ///
    /// Put beside a real banner the glassy version read as washed out: a
    /// banner is a bright, nearly solid card, and what makes it look like
    /// glass is its shadow and its edge, not what shows through it. This layer
    /// is also what the shadow is cast from — a shadow needs something to fall
    /// from, and a path alone drew nothing at all.
    static var surface: NSColor {
        isDark ? NSColor(calibratedWhite: 0.16, alpha: 0.72)
               : NSColor(calibratedWhite: 1.0, alpha: 0.72)
    }

    /// The colour the card actually reads as, laid over the blur.
    ///
    /// Under the blur it did nothing: a behind-window effect paints what is
    /// behind the *window*, so the wallpaper and the material's own grey
    /// covered it and the card came out grey against a white banner. What is
    /// drawn last is what is seen, so the card's colour belongs here — the
    /// blur still softens the edges and gives it its depth.
    /// A light floor laid over the glass.
    ///
    /// The glass takes its colour from whatever is behind it, so over a dark
    /// desktop the card goes dark with it. A banner does not: it keeps a pale
    /// surface wherever it sits, and still shows what is behind. This is what
    /// holds that floor — thin enough that the boundary between two things
    /// behind the dock still reads straight through.
    static var backing: NSColor {
        let lift = CGFloat(Settings.shared.cardTint)
        guard lift > 0 else { return .clear }
        return isDark ? NSColor(calibratedWhite: 0.22, alpha: lift)
                      : NSColor(calibratedWhite: 1.0, alpha: lift)
    }

    static var openTint: NSColor {
        isDark ? NSColor.white.withAlphaComponent(0.05)
               : NSColor.black.withAlphaComponent(0.035)
    }
    static var title: NSColor { NSColor.labelColor }
    static var detail: NSColor { NSColor.labelColor.withAlphaComponent(0.68) }
    static var meta: NSColor { NSColor.labelColor.withAlphaComponent(0.45) }
}

/// Tool marks, drawn rather than loaded: the apps' own icons are square and
/// heavy, and at 14pt they turn to mush.
enum Marks {
    /// Where each tool lives when the session does not name its own copy.
    static let claudeApp = "/Applications/Claude.app"
    static let codexApp = "/Applications/ChatGPT.app"

    private static var cache: [String: NSImage] = [:]

    /// The app's own icon, from the copy this session belongs to.
    ///
    /// Codex sessions carry the bundle they were started in, so a cloned copy
    /// shows the icon that copy was given — the personal profile and the work
    /// one are told apart without reading a word.
    static func icon(for session: Session, size: CGFloat) -> NSImage {
        let owned = session.app ?? ""
        let bundle = owned.isEmpty ? (session.isCodex ? codexApp : claudeApp) : owned
        if let found = appIcon(bundle, size: size) { return found }
        // The app is not installed, or was moved after the session was
        // recorded; a mark still has to appear where one is expected.
        return symbol(session.isCodex ? "circle.hexagonpath" : "asterisk",
                      size: size, description: session.tool)
    }

    /// Rows redraw thirty times a second while anything is working, so the
    /// icon is fetched once per app and kept.
    private static func appIcon(_ bundle: String, size: CGFloat) -> NSImage? {
        let key = "\(bundle)@\(size)"
        if let hit = cache[key] { return hit }
        guard FileManager.default.fileExists(atPath: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }

    private static var glyphs: [String: NSImage] = [:]

    /// Held rather than rebuilt. These are fixed shapes, and the spinner asks
    /// for them thirty times a second.
    static func symbol(_ name: String, size: CGFloat,
                       description: String) -> NSImage {
        let key = "\(name)@\(size)"
        if let hit = glyphs[key] { return hit }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let made = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: size, height: size))
        glyphs[key] = made
        return made
    }

    private static var tints: [String: NSImage] = [:]

    static func tinted(_ image: NSImage, _ color: NSColor, key: String) -> NSImage {
        if let hit = tints[key] { return hit }
        let made = tinted(image, color)
        tints[key] = made
        return made
    }

    /// Recolour a symbol, which otherwise draws in its own template black.
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// The turning arc, as a layer rather than something drawn.
///
/// It used to be redrawn from a timer thirty times a second. Even limited to
/// the badge, each frame dirtied a window whose background is a behind-window
/// blur, and the blur had to be recomposited every time — the app sat at a
/// fifth of a core with nothing happening but a spinner. Handed to Core
/// Animation the rotation runs on the render server and costs this process
/// nothing at all.
enum Spinner {
    static func make(diameter: CGFloat, colour: NSColor) -> CALayer {
        let box = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let arc = CAShapeLayer()
        arc.frame = box
        arc.path = CGPath(ellipseIn: box.insetBy(dx: 1, dy: 1), transform: nil)
        arc.fillColor = nil
        arc.strokeColor = colour.cgColor
        arc.lineWidth = 1.9
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.62
        // Anchored dead centre so the arc turns rather than orbits.
        arc.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -Double.pi * 2
        turn.duration = 1.2
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        arc.add(turn, forKey: "turn")
        return arc
    }
}

/// The edges that make glass read as glass.
///
/// Codex draws its own overlay with a hairline border and two inset
/// highlights — a bright line just inside the top, a fainter one along the
/// bottom — over the native glass. They are what makes the surface look lit
/// without covering it, which is the part that was missing while brightness
/// was being chased with a wash of white over the whole card.
enum Rim {
    static func draw(in bounds: NSRect, corner: CGFloat) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let edge = NSBezierPath(roundedRect: inset, xRadius: corner - 0.5,
                                yRadius: corner - 0.5)
        edge.lineWidth = 1
        (Palette.isDark ? NSColor.white.withAlphaComponent(0.10)
                        : NSColor.black.withAlphaComponent(0.06)).setStroke()
        edge.stroke()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner).addClip()
        // inset 0 1px 1px #fff9
        NSColor.white.withAlphaComponent(Palette.isDark ? 0.22 : 0.60).setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        // inset 0 -1px 2px #fff3
        NSColor.white.withAlphaComponent(Palette.isDark ? 0.08 : 0.20).setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class RowView: NSView {
    weak var card: RowCard?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    private var spinner: CALayer?
    private var spinnerColour: NSColor?

    /// Put the turning arc in place, or take it away.
    ///
    /// Rebuilt only when its colour changes, so the rotation is never
    /// restarted mid-turn by an unrelated redraw.
    func setSpinner(_ on: Bool, colour: NSColor) {
        // Probe: is the spinner layer what darkens a working row?
        let on = on && !UserDefaults.standard.bool(forKey: "noSpinner")
        guard on else {
            spinner?.removeFromSuperlayer()
            spinner = nil
            spinnerColour = nil
            return
        }
        if spinner != nil, spinnerColour == colour { return }
        spinner?.removeFromSuperlayer()
        let made = Spinner.make(diameter: badgeRect.width - 7, colour: colour)
        made.frame = badgeRect.insetBy(dx: 3.5, dy: 3.5)
        layer?.addSublayer(made)
        spinner = made
        spinnerColour = colour
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseUp(with event: NSEvent) {
        card?.click(at: convert(event.locationInWindow, from: nil))
    }

    /// Where the status mark sits. The spinner turns inside this and nothing
    /// else moves, so it is the only part that has to be redrawn for it.
    var badgeRect: NSRect {
        NSRect(x: Layout.padding, y: (Layout.rowHeight - 16) / 2,
               width: 16, height: 16)
    }

    /// The clear-away control, top-right, only while the row is open.
    var resolveRect: NSRect {
        NSRect(x: bounds.width - 24, y: (Layout.rowHeight - 18) / 2,
               width: 18, height: 18)
    }

    private var hoverResolve = false

    func setResolveHover(_ on: Bool) {
        guard on != hoverResolve else { return }
        hoverResolve = on
        needsDisplay = true
    }

    /// The status mark inside its badge.
    ///
    /// Working is the only one that moves: an arc chasing its own tail, which
    /// reads as progress without needing a percentage nobody has. Waiting is
    /// an arrow pointing back at the reader, because the row is asking for
    /// something. Idle is a flat bar — present, but with nothing to say.
    private func drawStatus(_ session: Session, in badge: NSRect) {
        let dimmed = session.mark == .parked
        let colour = dimmed
            ? NSColor.labelColor.withAlphaComponent(0.45) : session.color

        switch session.mark {
        case .working:
            break        // the spinner is a layer, and turns on its own

        case .yourTurn:
            // Solid, and pointing the way a thing you press points.
            let glyph = Marks.symbol("play.fill", size: 8,
                                     description: session.label)
            Marks.tinted(glyph, colour, key: "play\(session.state)\(dimmed)").draw(
                in: NSRect(x: badge.midX - glyph.size.width / 2 + 0.5,
                           y: badge.midY - glyph.size.height / 2,
                           width: glyph.size.width, height: glyph.size.height))

        case .parked:
            let bar = NSRect(x: badge.midX - 3.5, y: badge.midY - 0.8,
                             width: 7, height: 1.6)
            colour.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 0.8, yRadius: 0.8).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let card, let session = card.session else { return }
        let open = card.isOpen

        // Wiped back to nothing first.
        //
        // This view is the glass's own contents, and drawing over what was
        // there before let everyhalf-transparent pixel pile onto the last one:
        // a row grew darker each time it redrew, while a row nobody touched
        // stayed as bright as it started.
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        Palette.backing.setFill()
        bounds.fill()
        if open {
            Palette.openTint.setFill()
            bounds.fill()
        }
        Rim.draw(in: bounds, corner: Layout.corner)

        var x = Layout.padding

        // What the session is doing, as a mark rather than a word. A row is
        // read at a glance and sideways, so the shape has to carry it — the
        // three states are told apart by silhouette before colour.
        setSpinner(session.mark == .working, colour: session.color)
        let badge = badgeRect
        let dim = session.mark == .parked

        // A solid disc under the mark.
        //
        // It used to be a wash of the state's own colour at a fifth strength,
        // which was legible over the near-opaque card it was drawn on. On
        // glass the desktop comes through it, and the mark had to compete with
        // whatever happened to be behind the dock. The disc now carries its
        // own ground, so the mark reads the same over water as over a page.
        let disc = NSBezierPath(ovalIn: badge)
        (Palette.isDark ? NSColor(calibratedWhite: 0.16, alpha: 0.92)
                        : NSColor(calibratedWhite: 1.0, alpha: 0.92)).setFill()
        disc.fill()
        session.color.withAlphaComponent(dim ? 0.14 : 0.24).setFill()
        disc.fill()
        // A rim of the state's colour, which is what carries at a glance.
        disc.lineWidth = 1
        session.color.withAlphaComponent(dim ? 0.30 : 0.55).setStroke()
        NSBezierPath(ovalIn: badge.insetBy(dx: 0.5, dy: 0.5)).stroke()
        drawStatus(session, in: badge)
        x = badge.maxX + 7

        // which tool this session belongs to
        // Drawn in its own colours: an app icon greyed out reads as disabled,
        // and these are the one place in the row that is meant to be
        // recognised rather than read.
        // Work another agent split off sits under a branch mark, so a task
        // that fanned out reads as one thing with limbs rather than as
        // several unrelated conversations.
        if session.isDelegated {
            let branch = Marks.symbol("arrow.turn.down.right", size: 8,
                                      description: "위임된 작업")
            Marks.tinted(branch, NSColor.labelColor.withAlphaComponent(0.32),
                         key: "branch")
                .draw(in: NSRect(x: x, y: Layout.rowHeight / 2 - branch.size.height / 2,
                                 width: branch.size.width, height: branch.size.height))
            x += branch.size.width + 3
        }

        let mark = Marks.icon(for: session, size: 14)
        mark.draw(in: NSRect(x: x, y: Layout.rowHeight / 2 - mark.size.height / 2,
                             width: mark.size.width, height: mark.size.height),
                  from: .zero, operation: .sourceOver,
                  fraction: session.mark == .parked ? 0.55 : 1.0)
        x += mark.size.width + 6

        var right = bounds.width - Layout.padding
        if open {
            // resolve control takes the age's place while the row is open
            let dot = resolveRect.insetBy(dx: 4, dy: 4)
            (hoverResolve ? NSColor.systemRed.withAlphaComponent(0.9)
                          : NSColor.labelColor.withAlphaComponent(0.16)).setFill()
            NSBezierPath(ovalIn: dot).fill()
            if let glyph = NSImage(systemSymbolName: "checkmark",
                                   accessibilityDescription: "치우기") {
                let mark = NSImage(size: NSSize(width: 7, height: 7),
                                   flipped: false) { rect in
                    glyph.draw(in: rect)
                    (self.hoverResolve ? NSColor.white
                        : NSColor.labelColor.withAlphaComponent(0.6)).set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                mark.draw(in: NSRect(x: dot.midX - 3.5, y: dot.midY - 3.5,
                                     width: 7, height: 7))
            }
            right = resolveRect.minX - 8
        }
        let age = Age.text(since: session.date)
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: Palette.meta, .kern: 0.2]
        let metaSize = (age as NSString).size(withAttributes: metaAttrs)
        right -= metaSize.width
        (age as NSString).draw(at: NSPoint(x: right, y: (Layout.rowHeight - 13) / 2),
                               withAttributes: metaAttrs)
        right -= 8

        let clip = NSMutableParagraphStyle()
        clip.lineBreakMode = .byTruncatingTail

        // The chat's own subject leads; the folder trails it, smaller.
        let line = NSMutableAttributedString(
            string: session.headline,
            attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                         .foregroundColor: Palette.title, .kern: -0.1])
        if !session.subhead.isEmpty {
            line.append(NSAttributedString(
                string: "  " + session.subhead,
                attributes: [.font: NSFont.systemFont(ofSize: 10.5),
                             .foregroundColor: Palette.meta]))
        }
        line.addAttribute(.paragraphStyle, value: clip,
                          range: NSRange(location: 0, length: line.length))
        line.draw(in: NSRect(x: x, y: (Layout.rowHeight - 16) / 2,
                             width: max(20, right - x), height: 16))

        guard open else { return }
        let detail = session.title.isEmpty ? session.cwd : session.title
        (detail as NSString).draw(
            in: NSRect(x: Layout.padding + 14, y: Layout.rowHeight - 4,
                       width: bounds.width - Layout.padding * 2 - 14,
                       height: Layout.detailMax),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: Palette.detail,
                             .paragraphStyle: clip])
    }
}

/// One card in the column: a blurred surface, its shadow, and its contents.
///
/// The effect view sits inside a wrapper again. Made the card itself, with the
/// shadows moved onto the window's content layer, the blur stopped sampling
/// anything at all — every material painted the same flat tint, which is what
/// a backdrop with nothing behind it looks like. This is the arrangement the
/// wallpaper was last seen through.
class CardView: NSView {
    /// Whether the system's own glass is available to build cards on.
    static let usesSystemGlass = NSClassFromString("NSGlassEffectView") != nil

    /// The surface the card is built on.
    ///
    /// macOS 26 has a glass effect of its own, and it is not one of the
    /// NSVisualEffectView materials — it refracts what is behind it rather
    /// than blurring and tinting it, which is why no combination of material
    /// and opacity ever came close. Codex asks for it by name: its own styles
    /// carry `-owl-native-material: glass` and switch their CSS blur off when
    /// it is available. Older systems fall back to the closest material.
    let glass: NSView
    private let effect: NSVisualEffectView?
    private let corner: CGFloat

    init(corner: CGFloat, shadow: CGFloat) {
        self.corner = corner
        if let type = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let made = type.init(frame: .zero)
            made.setValue(corner, forKey: "cornerRadius")
            glass = made
            effect = nil
        } else {
            let made = NSVisualEffectView()
            made.blendingMode = .behindWindow
            made.state = .active
            made.wantsLayer = true
            made.layer?.cornerRadius = corner
            made.layer?.cornerCurve = .continuous
            made.layer?.masksToBounds = true
            glass = made
            effect = made
        }

        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        applyMaterial()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The glass is left alone.
    ///
    /// Its tintColor only ever darkened it, whatever colour or alpha it was
    /// given, and it was applied on every repaint — which is why the card
    /// started bright and dimmed as soon as anything redrew it. None of the
    /// private knobs lifted it either: each was either no change or a drop
    /// straight down to clear.
    /// The glass is left alone.
    ///
    /// Its tintColor does not tint. Given white and given black it settles on
    /// exactly the same colour, so the hue is discarded; only the alpha does
    /// anything, and it works backwards — the more of it, the darker the card.
    /// It reads as a dial on how much of the glass's own brightening to give
    /// up, and no setting of it goes past leaving it alone.
    func applyTint() {
        guard effect == nil else { return }
        glass.setValue(nil, forKey: "tintColor")
        glass.setValue(0, forKey: "style")     // regular, as Codex asks for
        // Adaptation off. The property defaults to 2, which is why setting it
        // to 2 earlier changed nothing — that was the default being written
        // back. Codex turns this off outright rather than leaving it on
        // automatic, which is what stops a card taking its colour from
        // whatever it happens to be sitting over.
        // 1, measured rather than guessed. The property defaults to 2, and both
        // 0 and 2 let each card take its lightness from whatever it sits over
        // — a column spanning a dark rock and bright water spread across
        // eleven levels of brightness, with some cards flipping to dark
        // outright. At 1 the spread is nil: every card holds the same surface
        // wherever it is.
        glass.setValue(1, forKey: "_adaptiveAppearance")
        // Pin the appearance so the glass stops following what is behind it.
        //
        // Left to itself it takes its light or dark look from the desktop, so
        // a card over a dark wallpaper turns dark with it. Codex holds its own
        // overlay still the same way — its glass carries a forced appearance
        // rather than an adaptive one.
        glass.appearance = NSAppearance(named: Palette.isDark ? .darkAqua : .aqua)
    }

    /// Only meaningful on the fallback: the glass effect has one look.
    func applyMaterial() {
        applyTint()
        guard let effect else { return }
        switch Settings.shared.cardMaterial {
        case "hudWindow": effect.material = .hudWindow
        case "fullScreenUI": effect.material = .fullScreenUI
        case "popover": effect.material = .popover
        case "sheet": effect.material = .sheet
        case "sidebar": effect.material = .sidebar
        case "selection": effect.material = .selection
        case "underWindowBackground": effect.material = .underWindowBackground
        default: effect.material = .menu
        }
    }

    /// The view drawn inside the glass, kept the size of the card.
    var content: NSView? {
        didSet {
            guard let content else { return }
            // The glass effect hosts its contents rather than having them
            // added as subviews; the fallback takes them the ordinary way.
            if effect == nil {
                glass.setValue(content, forKey: "contentView")
            } else {
                glass.addSubview(content)
            }
            content.frame = glass.bounds
        }
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        content?.frame = glass.bounds
    }
}

/// A card standing for one session.
final class RowCard: CardView {
    private(set) var session: Session?
    private(set) var isOpen = false
    private weak var dock: Dock?
    private let view = RowView()

    init(session: Session, dock: Dock) {
        self.session = session
        self.dock = dock
        super.init(corner: Layout.corner, shadow: 11)
        view.card = self
        view.autoresizingMask = [.width, .height]
        content = view
    }

    required init?(coder: NSCoder) { fatalError() }

    var collapsedSize: NSSize { NSSize(width: Layout.width, height: Layout.rowHeight) }
    var expandedSize: NSSize {
        NSSize(width: Layout.width, height: Layout.rowHeight + Layout.detailMax)
    }

    func update(_ session: Session) {
        self.session = session
        view.needsDisplay = true
    }

    func refresh() { view.needsDisplay = true }

    @discardableResult
    func setOpen(_ open: Bool) -> Bool {
        guard open != isOpen else { return false }
        isOpen = open
        view.needsDisplay = true
        return true
    }

    private(set) var targetFrame: NSRect = .zero
    func setTarget(_ frame: NSRect) { targetFrame = frame }

    func click(at point: NSPoint) {
        guard let session else { return }
        if isOpen, view.resolveRect.contains(point) {
            dock?.resolve(session)
            return
        }
        dock?.activate(session)
    }

    /// Where the resolve control sits, in the dock's own coordinates.
    func resolveHitBox() -> NSRect {
        let local = view.resolveRect
        return NSRect(x: frame.minX + local.minX,
                      y: frame.maxY - local.maxY,
                      width: local.width, height: local.height)
    }

    func setResolveHover(_ on: Bool) { view.setResolveHover(on) }
}

/// The card at the top: how many sessions, a settings button, and a grip.
final class HeaderCard: CardView {
    private let view = HeaderView()
    private weak var dock: Dock?

    init(dock: Dock) {
        self.dock = dock
        super.init(corner: Layout.headerHeight / 2, shadow: 8)
        view.owner = self
        view.autoresizingMask = [.width, .height]
        content = view
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(counts: (waiting: Int, working: Int, idle: Int)) {
        view.counts = counts
        view.needsDisplay = true
    }

    func drag(by delta: CGSize) { dock?.moveAnchor(by: delta) }
}

/// The one window everything lives in.
///
/// Clicks in the gaps between cards, and in the margin the shadows fall into,
/// pass through: the dock sits over the desktop, and a column of dead ground
/// around every row would swallow them.
final class DockContent: NSView {

    private var shadows: [CALayer] = []

    /// A shadow behind every card, kept light on purpose.
    ///
    /// The glass samples whatever is behind it, so a shadow laid there is
    /// partly drawn back into the card and greys it. Masking the card's own
    /// footprint out of the shadow did not work — the fill stayed and it came
    /// out darker still — so the shadow is simply kept faint enough that what
    /// the glass picks up costs a few levels rather than tens.
    func castShadows(_ boxes: [(NSRect, CGFloat)]) {
        wantsLayer = true
        layer?.masksToBounds = false
        // Measured: at this strength the glass gives back three or four levels
        // of brightness to the shadow behind it, against tens at the eleven
        // points and 0.18 it started on — that was what greyed the column.
        let strength: Float = Palette.isDark ? 0.24 : 0.12
        let spread: CGFloat = 5
        while shadows.count < boxes.count {
            let made = CALayer()
            made.shadowColor = NSColor.black.cgColor
            made.shadowOffset = CGSize(width: 0, height: -2)
            layer?.insertSublayer(made, at: 0)
            shadows.append(made)
        }
        while shadows.count > boxes.count { shadows.removeLast().removeFromSuperlayer() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, spec) in zip(shadows, boxes) {
            layer.frame = spec.0
            layer.shadowOpacity = strength
            layer.shadowRadius = spread
            layer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: spec.0.size),
                                      cornerWidth: spec.1, cornerHeight: spec.1,
                                      transform: nil)
        }
        CATransaction.commit()
    }

    /// Cards go inside this when the system provides one.
    var group: NSView? {
        didSet { group?.frame = bounds }
    }

    /// Where a card belongs: inside the group if there is one.
    var cardHost: NSView { group ?? self }

    override func layout() {
        super.layout()
        group?.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for card in cardHost.subviews where card.frame.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }

    /// Mouse-moved events only reach the active application, and this dock
    /// never becomes one — no event monitor sees the pointer while it is over
    /// the column. A tracking area is delivered either way.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    weak var dock: Dock?
    override func mouseEntered(with event: NSEvent) { dock?.pointerMoved() }
    override func mouseMoved(with event: NSEvent) { dock?.pointerMoved() }
    override func mouseExited(with event: NSEvent) { dock?.pointerMoved() }
}

final class DockWindow: NSPanel {
    let content = DockContent()

    /// No glass container.
    ///
    /// Apple's NSGlassEffectContainerView merges sibling glass views into one
    /// piece, which is right for the single bubble Codex uses it for. A column
    /// of ten cards merges into something much heavier: measured against the
    /// same wallpaper the cards dropped from 210 to 185, a quarter of the way
    /// back to opaque, for nothing gained.

    init(dock: Dock) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Above the notification banners and the Codex pet, both of which sit
        // higher than .floating and were covering the column.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false            // each card carries its own
        hidesOnDeactivate = false
        alphaValue = Palette.opacity
        content.dock = dock
        content.autoresizingMask = [.width, .height]
        contentView = content
    }
}

/// Hands the dock the same menu the status item shows.
///
/// The settings live in the menu bar, which means leaving the dock to change
/// anything about it. This lets the header open that menu where the dock
/// already is.
enum Menus {
    static var build: (() -> NSMenu)?
}

final class HeaderView: NSView {
    weak var owner: HeaderCard?
    var counts: (waiting: Int, working: Int, idle: Int) = (0, 0, 0)
    private var dragging = false
    private var hoverGrip = false
    private var hoverGear = false

    override var isFlipped: Bool { true }
    private var gripRect: NSRect { NSRect(x: 0, y: 0, width: 26, height: bounds.height) }
    private var gearRect: NSRect {
        NSRect(x: 26, y: 0, width: 22, height: bounds.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let grip = gripRect.contains(point)
        let gear = gearRect.contains(point)
        if grip != hoverGrip || gear != hoverGear {
            hoverGrip = grip
            hoverGear = gear
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverGrip = false
        hoverGear = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if gearRect.contains(point), let menu = Menus.build?() {
            // Upwards. The header sits on top of the stack, and this view is
            // flipped, so opening downwards would lay the menu straight over
            // the rows it is meant to be filtering.
            menu.popUp(positioning: nil,
                       at: NSPoint(x: gearRect.minX, y: gearRect.minY - 4),
                       in: self)
            return
        }
        dragging = gripRect.contains(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        owner?.drag(by: CGSize(width: event.deltaX, height: event.deltaY))
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func draw(_ dirtyRect: NSRect) {
        // Wiped back to nothing first, the same way a row is.
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        Palette.backing.setFill()
        bounds.fill()
        Rim.draw(in: bounds, corner: bounds.height / 2)

        NSColor.labelColor.withAlphaComponent(hoverGrip ? 0.6 : 0.3).setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                NSBezierPath(ovalIn: NSRect(x: 10 + CGFloat(column) * 4,
                                            y: bounds.height / 2 - 5 + CGFloat(row) * 4,
                                            width: 2.5, height: 2.5)).fill()
            }
        }

        let gear = Marks.symbol("slider.horizontal.3", size: 10,
                                description: "설정")
        Marks.tinted(gear, NSColor.labelColor.withAlphaComponent(hoverGear ? 0.7 : 0.32),
                     key: "gear\(hoverGear)")
            .draw(in: NSRect(x: gearRect.midX - gear.size.width / 2,
                             y: bounds.height / 2 - gear.size.height / 2,
                             width: gear.size.width, height: gear.size.height))

        var parts: [(String, NSColor)] = []
        if counts.waiting > 0 { parts.append(("대기 \(counts.waiting)", .systemOrange)) }
        if counts.working > 0 { parts.append(("작업 \(counts.working)", .systemGreen)) }
        if counts.idle > 0 {
            parts.append(("유휴 \(counts.idle)", NSColor.labelColor.withAlphaComponent(0.35)))
        }
        if parts.isEmpty { parts = [("세션 없음", Palette.meta)] }

        var x = bounds.width - Layout.padding
        for (text, color) in parts.reversed() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: color, .kern: 0.2]
            let size = (text as NSString).size(withAttributes: attrs)
            x -= size.width
            (text as NSString).draw(at: NSPoint(x: x, y: bounds.height / 2 - size.height / 2),
                                    withAttributes: attrs)
            x -= 9
        }
    }
}

// MARK: - the dock

final class Dock {
    private var rows: [RowCard] = []
    private lazy var window = DockWindow(dock: self)
    private lazy var header = HeaderCard(dock: self)
    private var hoverTimer: Timer?
    private var reloadTimer: Timer?
    private var lastCounts: (waiting: Int, working: Int, idle: Int) = (0, 0, 0)

    func start() {
        window.content.cardHost.addSubview(header)
        reload()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.reload()
        }
        // Pointer still, cards moving underneath it: no tracking area reports
        // that. A backstop only, so it can tick slowly.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] _ in
            self?.updateHover()
        }
    }

    func stop() {
        hoverTimer?.invalidate()
        reloadTimer?.invalidate()
        window.orderOut(nil)
    }

    // MARK: data

    func reload() {
        let sessions = SessionStore.load()
            .filter { Settings.shared.showIdle || $0.state != "idle" }
            .filter { Settings.shared.showDelegated || !$0.isDelegated }
            .filter { !Settings.shared.isHidden(source: $0.sourceKey) }
            .filter { !Settings.shared.isResolved($0.id, updated: $0.updated) }

        // Rows are sorted by how recently they moved, so the order churns every
        // few seconds. Re-sorting while the pointer is on a row yanks it away
        // mid-hover, which is what made the whole column judder. Hold the
        // order still until the pointer leaves.
        if rows.contains(where: { $0.isOpen }) {
            for session in sessions {
                rows.first { $0.session?.id == session.id }?.update(session)
            }
            return
        }

        var kept: [RowCard] = []
        for session in sessions {
            if let existing = rows.first(where: { $0.session?.id == session.id }) {
                existing.update(session)
                kept.append(existing)
            } else {
                let card = RowCard(session: session, dock: self)
                card.alphaValue = 0
                window.content.cardHost.addSubview(card)
                kept.append(card)
            }
        }
        for gone in rows where !kept.contains(where: { $0 === gone }) {
            gone.removeFromSuperview()
        }
        rows = kept

        let counts = (
            waiting: sessions.filter { $0.state == "waiting" }.count,
            working: sessions.filter { $0.state == "working" }.count,
            idle: sessions.filter { $0.state == "idle" }.count
        )
        lastCounts = counts
        header.set(counts: counts)
        if !window.isVisible { window.orderFrontRegardless() }

        layout(animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.duration
            for card in rows where card.alphaValue < Palette.opacity {
                card.animator().alphaValue = Palette.opacity
            }
        }
    }

    /// Redraw every card, for a change that alters how they look but not
    /// where they are.
    func repaint() {
        window.alphaValue = Palette.opacity
        header.applyMaterial()
        header.set(counts: lastCounts)
        rows.forEach { card in
            card.applyMaterial()
            card.refresh()
        }
    }

    func pointerMoved() { updateHover() }

    private func updateHover() {
        guard !rows.isEmpty, window.isVisible else { return }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)

        // Half the gap counts as part of the card on either side. A pointer
        // crossing the clear air between two cards belonged to neither, so the
        // open one shut and the next opened, and the column sprang about while
        // nothing had really changed.
        let reach = Layout.gap / 2
        let target = rows.first {
            $0.frame.insetBy(dx: 0, dy: -reach).contains(point)
        }
        var changed = false
        for card in rows {
            if card.setOpen(card === target) { changed = true }
            card.setResolveHover(card === target && card.resolveHitBox().contains(point))
        }
        if changed { layout(animated: true) }
    }

    // MARK: layout

    /// Bottom-right by default, stacked upwards: the newest and most urgent
    /// sits closest to the corner, where the eye already is.
    func layout(animated: Bool) {
        guard let screen = Screens.target else { return }
        let offset = Settings.shared.anchorOffset
        let pad = Layout.shadowPad

        // The window is sized for the tallest the column can get, so opening a
        // row never resizes it. A window resize is the app's own work, frame
        // by frame; the cards inside are layers, and moving them is not.
        var stack = Layout.headerHeight + Layout.gap
        for _ in rows { stack += Layout.rowHeight + Layout.gap }
        let tallest = stack + Layout.detailMax
        let size = NSSize(width: Layout.width + pad * 2, height: tallest + pad * 2)

        let right = screen.visibleFrame.maxX - Layout.inset - offset.width
        let bottom = screen.visibleFrame.minY + Layout.inset + offset.height
        let origin = NSPoint(x: right - Layout.width - pad, y: bottom - pad)
        let wanted = NSRect(origin: origin, size: size)
        if window.frame != wanted { window.setFrame(wanted, display: true) }

        var y = pad
        var targets: [(RowCard, NSRect)] = []
        for card in rows.reversed() {
            let height = (card.isOpen ? card.expandedSize : card.collapsedSize).height
            targets.append((card, NSRect(x: pad, y: y, width: Layout.width, height: height)))
            y += height + Layout.gap
        }
        let crown = NSRect(x: pad, y: y, width: Layout.width, height: Layout.headerHeight)

        let moved = targets.filter { $0.0.targetFrame != $0.1 }
        moved.forEach { $0.0.setTarget($0.1) }
        guard !moved.isEmpty || header.frame != crown else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Layout.duration : 0
            context.allowsImplicitAnimation = false
            if animated {
                // Off the mark immediately: easing in as well made a card feel
                // like it was deciding whether to follow.
                context.timingFunction =
                    CAMediaTimingFunction(controlPoints: 0.05, 0.8, 0.2, 1)
            }
            if animated {
                self.header.animator().frame = crown
                for (card, box) in moved { card.animator().frame = box }
            } else {
                self.header.frame = crown
                for (card, box) in moved { card.frame = box }
            }
        }

        // Shadows only where the glass cannot draw its own.
        //
        // NSGlassEffectView carries a shadow already — measured, the twenty
        // points outside a card sit eight levels darker than the desktop
        // further out. Adding another put black behind the cards, which is
        // exactly where the glass samples from, and every card refracted its
        // neighbours' shadow and came out grey. Codex splits it the same way:
        // `0 0 transparent` under native glass, `0 3px 16px` in the CSS
        // fallback.
        var boxes: [(NSRect, CGFloat)] = [(crown, Layout.headerHeight / 2)]
        for (card, box) in targets { boxes.append((box, Layout.corner)) }
        window.content.castShadows(boxes)

    }

    func moveAnchor(by delta: CGSize) {
        guard let screen = Screens.target else { return }
        var offset = Settings.shared.anchorOffset
        offset.width = min(max(0, offset.width - delta.width),
                           screen.visibleFrame.width - Layout.width - Layout.inset)
        offset.height = min(max(0, offset.height - delta.height),
                            screen.visibleFrame.height - 160)
        Settings.shared.anchorOffset = offset
        layout(animated: false)
    }

    func activate(_ session: Session) {
        Route.open(session)
    }

    /// Clear a session away until it does something new.
    func resolve(_ session: Session) {
        Settings.shared.resolve(session.id, updated: session.updated)
        reload()
    }
}
