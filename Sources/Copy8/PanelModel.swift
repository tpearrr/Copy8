import AppKit
import Observation

@MainActor
protocol PanelActions: AnyObject {
    func paste(_ item: ClipItem, plain: Bool)
    func copy(_ item: ClipItem)
    func delete(_ item: ClipItem)
    func openSettings()
    func focusSearch()
}

/// Stato della finestra: ricerca, risultati raggruppati per giorno, selezione.
@MainActor
@Observable
final class PanelModel {
    struct Row: Identifiable {
        let index: Int
        let item: ClipItem
        var id: Int64 { item.id }
    }

    struct Section: Identifiable {
        let id: Date
        let label: String
        var rows: [Row]
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            refresh()
            selection = 0
            requestScrollToTop()
        }
    }
    var selection = 0
    var appeared = false
    private(set) var results: [ClipItem] = []
    private(set) var sections: [Section] = []
    private(set) var terms: [String] = []
    private(set) var poolCount = 0
    /// Id della riga da rendere visibile; -1 significa "torna in cima".
    private(set) var scrollTarget: Int64 = -1
    private(set) var scrollTick = 0

    @ObservationIgnored weak var actions: PanelActions?
    @ObservationIgnored private let history: History
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private var lastMouse = NSPoint(x: -1, y: -1)

    init(history: History, settings: Settings) {
        self.history = history
        self.settings = settings
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func refresh() {
        let cutoff = Date().addingTimeInterval(-Double(settings.days) * 86_400)
        let pool = history.visible.prefix { $0.copiedAt >= cutoff }
        poolCount = pool.count
        terms = Search.terms(query)
        let needles = terms.map { Array($0.utf8) }
        results = needles.isEmpty ? Array(pool) : pool.filter { item in needles.allSatisfy(item.matches) }

        var built: [Section] = []
        for (index, item) in results.enumerated() {
            let day = DayFormat.dayKey(item.copiedAt)
            if built.last?.id != day {
                built.append(Section(id: day, label: DayFormat.dayLabel(item.copiedAt), rows: []))
            }
            built[built.count - 1].rows.append(Row(index: index, item: item))
        }
        sections = built
        if selection >= results.count { selection = max(0, results.count - 1) }
    }

    func prepareForShow() {
        appeared = false
        if query.isEmpty { refresh() } else { query = "" }
        selection = 0
        lastMouse = NSEvent.mouseLocation
        requestScrollToTop()
    }

    func move(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
        scrollTarget = results[selection].id
        scrollTick += 1
    }

    /// Il passaggio del mouse seleziona solo se il mouse si è mosso davvero,
    /// non quando è la lista a scorrere sotto un puntatore fermo.
    func hover(_ index: Int) {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse else { return }
        lastMouse = mouse
        if selection != index { selection = index }
    }

    private func requestScrollToTop() {
        scrollTarget = -1
        scrollTick += 1
    }
}
