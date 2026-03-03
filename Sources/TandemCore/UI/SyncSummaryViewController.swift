import AppKit

// MARK: - SyncSummaryViewController

/// Sheet that reports the outcome of a completed sync pass.
/// Presented via `presentAsSheet` from `MainWindowController`.
final class SyncSummaryViewController: NSViewController {

    // MARK: - Input
    private let result:   SyncResult
    private let pair:     SyncPair
    private let isManual: Bool

    /// Fired when the user taps "View Conflicts". Caller should dismiss self first.
    var onViewConflicts: (() -> Void)?

    // MARK: - Init
    init(result: SyncResult, pair: SyncPair, isManual: Bool) {
        self.result   = result
        self.pair     = pair
        self.isManual = isManual
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View
    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Build

    private func buildUI() {
        let hasProblems = result.clashes.count > 0 || result.errors.count > 0
        let nothingDone = result.totalChanges == 0 && !hasProblems

        // ── Icon + title ─────────────────────────────────────────────────────
        let iconName: String
        let iconColor: NSColor
        if hasProblems {
            iconName  = "exclamationmark.triangle.fill"
            iconColor = .systemOrange
        } else if nothingDone {
            iconName  = "checkmark.circle.fill"
            iconColor = .secondaryLabelColor
        } else {
            iconName  = "checkmark.circle.fill"
            iconColor = .systemGreen
        }

        let iconView = NSImageView()
        let cfg = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iconView.image           = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                                    .withSymbolConfiguration(cfg)
        iconView.contentTintColor = iconColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        iconView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let titleText: String
        if nothingDone {
            titleText = "Already in Sync"
        } else if hasProblems {
            titleText = "Sync Completed with Issues"
        } else {
            titleText = "Sync Complete"
        }

        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.lineBreakMode = .byTruncatingTail

        let pairLabel = NSTextField(labelWithString: pair.name)
        pairLabel.font      = .systemFont(ofSize: 12)
        pairLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [titleLabel, pairLabel])
        titleStack.orientation = .vertical
        titleStack.alignment   = .leading
        titleStack.spacing     = 2

        let headerStack = NSStackView(views: [iconView, titleStack])
        headerStack.orientation = .horizontal
        headerStack.alignment   = .centerY
        headerStack.spacing     = 12

        // ── Separator ────────────────────────────────────────────────────────
        let sep1 = makeSeparator()

        // ── Stat grid ────────────────────────────────────────────────────────
        let gridView = buildGrid()

        // ── Separator ────────────────────────────────────────────────────────
        let sep2 = makeSeparator()

        // ── Buttons ──────────────────────────────────────────────────────────
        let okButton = NSButton(title: "OK", target: self, action: #selector(okTapped))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        var buttonViews: [NSView] = []
        if result.clashes.count > 0 {
            let conflictBtn = NSButton(title: "View Conflicts (\(result.clashes.count))",
                                       target: self, action: #selector(conflictsTapped))
            conflictBtn.bezelStyle = .rounded
            buttonViews.append(conflictBtn)
        }
        let btnSpacer = NSView()
        btnSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonViews.insert(btnSpacer, at: 0)
        buttonViews.append(okButton)

        let buttonStack = NSStackView(views: buttonViews)
        buttonStack.orientation = .horizontal
        buttonStack.spacing     = 8

        // ── Outer vertical stack ─────────────────────────────────────────────
        let outerStack = NSStackView(views: [headerStack, sep1, gridView, sep2, buttonStack])
        outerStack.orientation  = .vertical
        outerStack.alignment    = .leading
        outerStack.spacing      = 16
        outerStack.edgeInsets   = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Pin stretched items to outerStack width
            headerStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor, constant: -40),
            sep1.widthAnchor.constraint(equalTo:     outerStack.widthAnchor, constant: -40),
            gridView.widthAnchor.constraint(equalTo: outerStack.widthAnchor, constant: -40),
            sep2.widthAnchor.constraint(equalTo:     outerStack.widthAnchor, constant: -40),
            buttonStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor, constant: -40),
            // Fixed sheet width
            view.widthAnchor.constraint(equalToConstant: 420),
        ])
    }

    // MARK: - Grid builder

    private func buildGrid() -> NSView {
        let hasProblems = result.clashes.count > 0 || result.errors.count > 0
        let nothingDone = result.totalChanges == 0 && !hasProblems

        // Duration string
        let durationStr: String?
        if result.wallTime > 0 {
            if result.wallTime < 1 {
                durationStr = String(format: "%.0f ms", result.wallTime * 1000)
            } else {
                durationStr = String(format: "%.2f s", result.wallTime)
            }
        } else {
            durationStr = nil
        }

        typealias Row = (label: String, value: String, color: NSColor)
        var rows: [Row] = []

        if nothingDone {
            rows.append(("Status", "Both folders are identical", .labelColor))
        } else {
            rows.append(("New files synced", count(result.newFiles.count),     .labelColor))
            rows.append(("Files updated",    count(result.updatedFiles.count), .labelColor))
            rows.append(("Files deleted",    count(result.deleted.count),      .labelColor))
            if result.backedUp.count > 0 {
                rows.append(("Backups created", count(result.backedUp.count),  .secondaryLabelColor))
            }
        }

        // Always show these so the user knows the outcome
        rows.append(("Unresolved conflicts",
                      result.clashes.count == 0 ? "None" : "\(result.clashes.count)",
                      result.clashes.count > 0 ? .systemOrange : .secondaryLabelColor))
        rows.append(("Errors",
                      result.errors.count == 0 ? "None" : "\(result.errors.count)",
                      result.errors.count > 0 ? .systemRed : .secondaryLabelColor))

        if let dur = durationStr {
            rows.append(("Duration", dur, .secondaryLabelColor))
        }

        // Build rows with fixed left column width
        let labelColumnWidth: CGFloat = 160
        var rowViews: [NSView] = []

        for row in rows {
            let lbl = NSTextField(labelWithString: row.label)
            lbl.font      = .systemFont(ofSize: 13)
            lbl.textColor = .secondaryLabelColor
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true

            let val = NSTextField(labelWithString: row.value)
            val.font      = .systemFont(ofSize: 13, weight: row.color == .labelColor ? .medium : .regular)
            val.textColor = row.color
            val.lineBreakMode = .byTruncatingTail

            let rowStack = NSStackView(views: [lbl, val])
            rowStack.orientation = .horizontal
            rowStack.alignment   = .centerY
            rowStack.spacing     = 12
            rowViews.append(rowStack)
        }

        let grid = NSStackView(views: rowViews)
        grid.orientation = .vertical
        grid.alignment   = .leading
        grid.spacing     = 10
        return grid
    }

    // MARK: - Helpers

    private func count(_ n: Int) -> String { n == 0 ? "—" : "\(n)" }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    // MARK: - Actions

    @objc private func okTapped() {
        presentingViewController?.dismiss(self)
    }

    @objc private func conflictsTapped() {
        onViewConflicts?()
    }
}
