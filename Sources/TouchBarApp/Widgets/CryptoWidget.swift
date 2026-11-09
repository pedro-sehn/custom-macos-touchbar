import AppKit

/// A quiet, fixed-width price readout. Network events update the shared cache,
/// not AppKit; the normal ticker coalesces trades into at most one redraw/tick.
final class CryptoWidget: TextWidget {
    let market: CryptoMarket?
    private let service: CryptoPriceService
    private let formatter = NumberFormatter()
    private let caption: String
    private let width: CGFloat
    private let staleAfter: TimeInterval
    private var lastStatus: CryptoPriceSnapshot.Status?

    init(id: String, options: Options, service: CryptoPriceService = .shared) {
        let symbol = options.string("symbol", "btc").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let currency = options.string("currency", "usd").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        market = CryptoMarket(symbol: symbol, currency: currency)
        caption = "\(symbol.prefix(20)) \(currency.uppercased().prefix(8))"
        self.service = service

        let requestedWidth = options.double("width", 180)
        width = CGFloat(requestedWidth.isFinite ? min(400, max(90, requestedWidth)) : 180)
        let requestedStaleAfter = options.double("staleAfter", 30)
        staleAfter = requestedStaleAfter.isFinite ? max(5, requestedStaleAfter) : 30
        let requestedDecimals = options.double("decimals", 2)
        let decimals = requestedDecimals.isFinite ? Int(min(8, max(0, requestedDecimals))) : 2
        formatter.locale = L10n.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = market?.currency.code ?? "USD"
        formatter.currencySymbol = market?.currency.symbol ?? "$"
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals

        super.init(id: id)
        if market == nil {
            Log.config.error("crypto \(id, privacy: .public): invalid symbol or currency; use an asset symbol and usd/brl/eur")
        }
    }

    override func makeItem() -> NSTouchBarItem? {
        guard let item = super.makeItem(), let label else { return nil }
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let market {
            label.toolTip = "\(market.provider.name) · \(market.symbol)/\(market.currency.code)"
        }
        lastStatus = nil
        applyStatus()
        return item
    }

    override func render() -> String? {
        guard let market else { return "\(caption) —" }
        let snapshot = service.snapshot(for: market, staleAfter: staleAfter)
        guard let price = snapshot.price,
              let formatted = formatter.string(from: NSDecimalNumber(decimal: price)) else {
            return "\(caption) \(snapshot.status == .loading ? "…" : "—")"
        }
        let marker = snapshot.status == .stale ? "~" : ""
        return "\(marker)\(market.symbol) \(formatted)"
    }

    override func tick() {
        super.tick()
        applyStatus()
    }

    private func applyStatus() {
        guard let label else { return }
        let status = market.map { service.snapshot(for: $0, staleAfter: staleAfter).status } ?? .unavailable
        guard status != lastStatus else { return }
        lastStatus = status
        label.textColor = status == .live ? .labelColor : .secondaryLabelColor
        label.setAccessibilityLabel(caption)
        label.setAccessibilityValue(label.stringValue)
    }
}
