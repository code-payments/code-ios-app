//
//  ChatScrollBenchmark.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG && canImport(UIKit)
import UIKit
import FlipcashCore

/// Scrolls the *shipping* transcript at a fixed velocity over a synthetic window and reports the
/// frame times, so "the group chat is janky" can be answered with a number instead of a guess.
///
/// Like ``ChatMotionSandboxViewController`` it drives `ChatViewController` directly — no server, no
/// account, no owner. That is the point: nothing above the transcript can contribute, so a bad run
/// here convicts the UIKit layer and a clean run acquits it and moves the search up into the
/// SwiftUI/paging layer. Run a DM-shaped window and a group-shaped one of the same length and the
/// difference is attributable to attribution.
///
/// It drives ``ChatScreenViewController``, not the bare transcript, so the top fade, the bar clip
/// and the gate's blur are all in the frame the way they are in the app.
public final class ChatScrollBenchmarkViewController: UIViewController {

    /// What to build and how hard to drive it.
    public struct Configuration: Sendable {
        /// How many message rows the window holds.
        public var messageCount: Int
        /// How many distinct authors the rows round-robin over; 0 builds a DM-shaped window with no
        /// author attribution and no head card.
        public var authorCount: Int
        /// Points per second the scripted scroll travels at. 2000 is a hard flick.
        public var velocity: CGFloat
        /// How many rows a scripted prepend adds, mimicking one `loadOlder()` step.
        public var prependCount: Int
        /// Whether the scroll pass pages older rows in as it nears the top, the way the screen does.
        /// Off measures the transcript alone; on measures the transcript under the owner's paging.
        public var pages: Bool
        /// Whether the gate's blur sits over the transcript — a full-screen material composited
        /// over scrolling content, which only a group ever shows.
        public var obscured: Bool

        public init(
            messageCount: Int = 400,
            authorCount: Int = 8,
            velocity: CGFloat = 2000,
            prependCount: Int = 40,
            pages: Bool = false,
            obscured: Bool = false
        ) {
            self.messageCount = messageCount
            self.authorCount = authorCount
            self.velocity = velocity
            self.prependCount = prependCount
            self.pages = pages
            self.obscured = obscured
        }
    }

    private let configuration: Configuration
    private let screen: ChatScreenViewController

    private var items: [ChatItem] = []
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var intervals: [CFTimeInterval] = []
    /// How far the paging mode has grown the window, in rows.
    private var pagedRows = 0
    /// Mirrors `MessageLoader.growthInterval` — the screen accepts at most one growth step per beat.
    private var lastGrowth: CFTimeInterval = 0

    public init(configuration: Configuration) {
        self.configuration = configuration
        // A plain view stands in for the composer: the bar's own content is not under test, but its
        // height and the clip over it are part of every frame the transcript draws into.
        let bar = UIView()
        bar.backgroundColor = .clear
        bar.heightAnchor.constraint(equalToConstant: 56).isActive = true
        self.screen = ChatScreenViewController(bar: bar)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(screen)
        screen.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen.view)
        screen.didMove(toParent: self)

        NSLayoutConstraint.activate([
            screen.view.topAnchor.constraint(equalTo: view.topAnchor),
            screen.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        items = Self.window(configuration, offset: 0)
        screen.isTranscriptObscured = configuration.obscured
        screen.update(items: items)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard link == nil else { return }
        report("start", [
            "messages": "\(configuration.messageCount)",
            "authors": "\(configuration.authorCount)",
            "velocity": "\(Int(configuration.velocity))pt/s",
            "pages": "\(configuration.pages)",
            "obscured": "\(configuration.obscured)",
        ])
        // One runloop turn to let the opening scroll-to-bottom land before the scripted pass starts;
        // measuring across it would time the open, not the scroll.
        DispatchQueue.main.async { [weak self] in self?.startScrollPass() }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        link?.invalidate()
        link = nil
    }

    // MARK: - Scroll pass

    private func startScrollPass() {
        intervals.removeAll(keepingCapacity: true)
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else { finishScrollPass(); return }
        if lastTimestamp > 0 {
            intervals.append(link.timestamp - lastTimestamp)
        }
        lastTimestamp = link.timestamp

        let top = -scrollView.adjustedContentInset.top
        let delta = configuration.velocity * CGFloat(link.targetTimestamp - link.timestamp)
        let next = scrollView.contentOffset.y - delta
        guard next > top else {
            scrollView.contentOffset.y = top
            finishScrollPass()
            return
        }
        scrollView.contentOffset.y = next
        if configuration.pages { pageIfNearTop(scrollView, now: link.timestamp) }
    }

    /// The owner's reverse-paging loop, reproduced: within one screen of the top, at most one growth
    /// per `growthInterval`, each growth rebuilding the whole window and pushing it as an animated
    /// update. This is the work that lands *while the finger is still moving*, so it is charged to
    /// the same frames the scroll is.
    private func pageIfNearTop(_ scrollView: UIScrollView, now: CFTimeInterval) {
        guard scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + scrollView.bounds.height else { return }
        guard now - lastGrowth >= Self.growthInterval else { return }
        lastGrowth = now
        pagedRows += configuration.prependCount
        items = Self.window(configuration, offset: pagedRows)
        screen.update(items: items)
    }

    /// The transcript's own scroll view, found by walking the screen's hierarchy — the screen keeps
    /// its child transcript private, and a DEBUG harness has no business widening that.
    private var scrollView: UIScrollView? {
        func find(_ view: UIView) -> UIScrollView? {
            if let scrollView = view as? UICollectionView { return scrollView }
            for subview in view.subviews {
                if let found = find(subview) { return found }
            }
            return nil
        }
        return find(screen.view)
    }

    private static let growthInterval: CFTimeInterval = 0.3

    private func finishScrollPass() {
        link?.invalidate()
        link = nil
        var stats = frameStats(intervals)
        stats["pagedRows"] = "\(pagedRows)"
        stats["windowAfter"] = "\(items.count)"
        report("scroll", stats)
        measurePrepend()
    }

    // MARK: - Prepend

    /// Times the synchronous half of one `loadOlder()` step — the deep push compare, the
    /// DifferenceKit stage and the batch update kickoff — which lands while the finger is still
    /// moving and so is charged to the same frame budget as the scroll.
    private func measurePrepend() {
        let grown = Self.window(configuration, offset: pagedRows + configuration.prependCount)
        let start = CACurrentMediaTime()
        screen.update(items: grown)
        let elapsed = CACurrentMediaTime() - start
        items = grown
        report("prepend", [
            "rows": "\(configuration.prependCount)",
            "windowAfter": "\(grown.count)",
            "ms": Self.milliseconds(elapsed),
        ])
        report("done", [:])
    }

    // MARK: - Reporting

    private func frameStats(_ intervals: [CFTimeInterval]) -> [String: String] {
        guard !intervals.isEmpty else { return ["frames": "0"] }
        let sorted = intervals.sorted()
        // The device's own cadence, not a hardcoded 60Hz — the simulator and ProMotion both differ.
        let budget = 1.0 / Double(view.window?.screen.maximumFramesPerSecond ?? 60)
        let overBudget = intervals.filter { $0 > budget * 1.5 }.count
        return [
            "frames": "\(intervals.count)",
            "budgetMs": Self.milliseconds(budget),
            "p50Ms": Self.milliseconds(sorted[sorted.count / 2]),
            "p95Ms": Self.milliseconds(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]),
            "maxMs": Self.milliseconds(sorted[sorted.count - 1]),
            "hitches": "\(overBudget)",
            "hitchRate": String(format: "%.1f%%", Double(overBudget) / Double(intervals.count) * 100),
        ]
    }

    private func report(_ phase: String, _ fields: [String: String]) {
        let body = fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: " ")
        print("\(Self.marker) \(phase) \(body)")
    }

    private static func milliseconds(_ seconds: CFTimeInterval) -> String {
        String(format: "%.2f", seconds * 1000)
    }

    /// Grepped out of the launch console; every line the benchmark prints carries it.
    public static let marker = "[chat-scroll-benchmark]"

    // MARK: - Synthetic window

    /// A window of `messageCount + offset` rows, oldest first, deterministic in both the text and
    /// the author each row gets so two runs are comparable. `offset` extends it at the *head*, which
    /// is what paging back does.
    private static func window(_ configuration: Configuration, offset: Int) -> [ChatItem] {
        let total = configuration.messageCount + offset
        let authors = self.authors(count: configuration.authorCount)

        var items: [ChatItem] = []
        items.reserveCapacity(total + 1)
        if !authors.isEmpty {
            items.append(.groupCard(ChatGroupCard(
                title: "Flipcash Staff",
                avatarID: "benchmark-group",
                requirement: "Minimum Balance: $1.00 of Jeffy"
            )))
        }

        // Runs of three, so continuation grouping and author changes are both exercised the way a
        // real group transcript exercises them.
        for index in 0..<total {
            let run = index / 3
            let author = authors.isEmpty ? nil : authors[run % authors.count]
            let sender: ChatMessage.Sender = author == nil ? (run % 2 == 0 ? .other : .me) : (run % 5 == 0 ? .me : .other)
            let isContinuation = index % 3 != 0
            let isContinued = index % 3 != 2 && index < total - 1
            items.append(.message(ChatMessage(
                id: "bench-\(index)",
                text: texts[index % texts.count],
                sender: sender,
                isContinuationFromPrevious: isContinuation,
                isContinuedByNext: isContinued,
                author: sender == .me ? nil : author
            )))
        }
        return items
    }

    /// Stable synthetic identities — the ids are derived from the index so the per-person tint and
    /// the avatar cache key are the same on every run.
    private static func authors(count: Int) -> [ChatAuthor] {
        (0..<max(0, count)).map { index in
            ChatAuthor(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
                name: names[index % names.count]
            )
        }
    }

    private static let names = [
        "Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson",
        "Barbara Liskov", "Donald Knuth", "Margaret Hamilton", "Edsger Dijkstra",
    ]

    private static let texts = [
        "Hey!",
        "How's it going?",
        "Pretty good — shipping a thing.",
        "Want to grab lunch later?",
        "Sure, around noon?",
        "This one is intentionally much longer so the bubble wraps across multiple lines and proves the cell self-sizes to its content under load.",
        "👍",
        "See you then.",
    ]
}
#endif
