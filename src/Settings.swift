import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Quiet sessions are usually noise; off by default.
    var showIdle: Bool {
        get { defaults.object(forKey: "showIdle") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showIdle") }
    }

    /// Sources whose rows are put away, by `Session.sourceKey`.
    ///
    /// Stored as the hidden set rather than the shown one so that a copy of
    /// an app installed later shows up on its own instead of staying invisible
    /// until someone finds the setting.
    var hiddenSources: Set<String> {
        get { Set(defaults.stringArray(forKey: "hiddenSources") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "hiddenSources") }
    }

    func isHidden(source key: String) -> Bool { hiddenSources.contains(key) }

    func toggle(source key: String) {
        var held = hiddenSources
        if held.contains(key) { held.remove(key) } else { held.insert(key) }
        hiddenSources = held
    }

    /// How much light the glass is lifted by.
    ///
    /// The glass effect refracts what is behind it and takes its colour from
    /// there, so over a dark desktop the card comes out dark. A tint lifts it
    /// back towards the pale surface a banner keeps whatever it sits on.
    var cardTint: Double {
        // Nothing, by default. The glass takes its colour from what is behind
        // it, and white laid over that buys brightness by giving up exactly
        // the thing the glass was for — at 0.28 the desktop stopped showing
        // through at all. The dial stays for anyone who would rather have the
        // light.
        get { defaults.object(forKey: "cardTint") as? Double ?? 0.0 }
        set { defaults.set(newValue, forKey: "cardTint") }
    }

    static let tintLevels: [(String, Double)] = [
        ("유리 그대로", 0.0), ("살짝 밝게", 0.16), ("보통", 0.28),
        ("밝게", 0.40), ("아주 밝게", 0.55),
    ]

    /// How much of the whole card comes through, window and all.
    ///
    /// The blur has a floor: the most see-through material still stops 58% of
    /// what is behind it, and nothing laid over it can go below that. Only the
    /// window's own opacity can, so that is what this turns. It carries the
    /// text with it, which is why it stops short of nothing.
    var cardSheer: Double {
        get { defaults.object(forKey: "cardSheer") as? Double ?? 0.82 }
        set { defaults.set(newValue, forKey: "cardSheer") }
    }

    static let opacityLevels: [(String, Double)] = [
        ("최대로 비치게", 0.70), ("많이 비치게", 0.82), ("보통", 0.90),
        ("또렷하게", 1.0),
    ]

    /// Which blur the cards are built on.
    ///
    /// Every AppKit material carries a tint of its own on top of the blur, and
    /// how much of the desktop survives it differs from one to the next. None
    /// of them is `backdrop-filter: blur(40px)`, so which comes closest is a
    /// matter of looking rather than reasoning — it belongs in the menu.
    var cardMaterial: String {
        // The material macOS builds its own menus on, which is the surface
        // that was actually being asked for: the boundary between two things
        // behind the dock shows straight through it. The others lighten what
        // is behind them into a flat wash — the card ends up pale rather than
        // clear, whatever is laid over it.
        get { defaults.string(forKey: "cardMaterial") ?? "menu" }
        set { defaults.set(newValue, forKey: "cardMaterial") }
    }

    static let materials: [(String, String)] = [
        ("창 아래 (틴트 없음에 가까움)", "underWindowBackground"),
        ("HUD", "hudWindow"),
        ("전체화면 UI", "fullScreenUI"),
        ("팝오버", "popover"),
        ("메뉴", "menu"),
        ("시트", "sheet"),
        ("사이드바", "sidebar"),
        ("선택", "selection"),
    ]

    /// Whether the column is folded away into a single tab.
    ///
    /// Kept, unlike the reach: this is how someone wants the dock to sit, not
    /// something they reach for to answer one question.
    var collapsed: Bool {
        get { defaults.bool(forKey: "collapsed") }
        set { defaults.set(newValue, forKey: "collapsed") }
    }

    /// Runs another agent split off from a task of its own.
    ///
    /// Shown by default: they are real work, and hiding them makes a busy
    /// stretch look idle. One task can fan out into several at once, though,
    /// so there is a way to put them away.
    var showDelegated: Bool {
        get { defaults.object(forKey: "showDelegated") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showDelegated") }
    }

    /// Sessions the user has cleared away, with the activity stamp they were
    /// cleared at. If the session moves again it comes back — resolving is
    /// "I have dealt with this", not "never show me this".
    private let resolvedKey = "resolved"

    func isResolved(_ id: String, updated: Double) -> Bool {
        guard let stamp = (defaults.dictionary(forKey: resolvedKey)
                           as? [String: Double])?[id] else { return false }
        return updated <= stamp + 1
    }

    func resolve(_ id: String, updated: Double) {
        var map = (defaults.dictionary(forKey: resolvedKey) as? [String: Double]) ?? [:]
        map[id] = updated
        // keep it from growing without bound
        if map.count > 300 {
            let newest = map.sorted { $0.value > $1.value }.prefix(200)
            map = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        defaults.set(map, forKey: resolvedKey)
    }

    func clearResolved() { defaults.removeObject(forKey: resolvedKey) }

    private let seenKey = "acknowledged"

    /// Whether this turn has already been looked at.
    ///
    /// Kept against the session's own timestamp rather than as a flag, so
    /// answering it and having it come back to you lights it again — what was
    /// acknowledged was that turn, not the session for good.
    func wasSeen(_ id: String, updated: Double) -> Bool {
        guard let stamp = (defaults.dictionary(forKey: seenKey)
                           as? [String: Double])?[id] else { return false }
        return updated <= stamp + 1
    }

    func acknowledge(_ id: String, updated: Double) {
        var map = (defaults.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
        map[id] = updated
        if map.count > 300 {
            let newest = map.sorted { $0.value > $1.value }.prefix(200)
            map = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        defaults.set(map, forKey: seenKey)
    }

    /// Which display the dock belongs on. NSScreen.main follows the focused
    /// window, so without pinning, the dock hops between monitors as the user
    /// works. Stored as the screen's number, which survives sleep and
    /// reconnects better than an index into the screen list.
    var pinnedScreen: Int {
        get { defaults.integer(forKey: "pinnedScreen") }
        set { defaults.set(newValue, forKey: "pinnedScreen") }
    }

    /// Where the dock hangs, as an offset from the bottom-right corner.
    /// How wide the column is drawn.
    ///
    /// The dock is pinned by its right edge, so widening it grows leftwards
    /// into empty desktop rather than pushing the whole thing off screen.
    /// Titles are what the width buys: a long conversation name is elided at
    /// 288 and readable well before 400.
    var dockWidth: Double {
        get {
            let held = defaults.object(forKey: "dockWidth") as? Double ?? 288
            return min(max(held, Settings.widthRange.lowerBound),
                       Settings.widthRange.upperBound)
        }
        set {
            defaults.set(min(max(newValue, Settings.widthRange.lowerBound),
                             Settings.widthRange.upperBound),
                         forKey: "dockWidth")
        }
    }

    /// Narrow enough that a row still fits an icon, a title and a time; wide
    /// enough to be silly on a large display, which is the user's business.
    static let widthRange: ClosedRange<Double> = 220...620

    static let widthSteps: [(String, Double)] = [
        ("좁게", 240), ("보통", 288), ("넓게", 360), ("아주 넓게", 440),
    ]

    var anchorOffset: CGSize {
        get {
            CGSize(width: defaults.double(forKey: "anchorX"),
                   height: defaults.double(forKey: "anchorY"))
        }
        set {
            defaults.set(Double(newValue.width), forKey: "anchorX")
            defaults.set(Double(newValue.height), forKey: "anchorY")
        }
    }
}
