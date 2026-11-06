import Foundation

enum CryptoCurrency: String, CaseIterable {
    case usd, brl, eur

    var code: String { rawValue.uppercased() }
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .brl: return "R$"
        case .eur: return "€"
        }
    }
}

struct CryptoMarket: Hashable {
    let symbol: String
    let currency: CryptoCurrency

    init?(symbol: String, currency: String) {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !symbol.isEmpty, symbol.count <= 20,
              symbol.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
              let currency = CryptoCurrency(rawValue: currency) else { return nil }
        self.symbol = symbol
        self.currency = currency
    }

    // Use real fiat pairs, never label a USDT quote as USD. Both feeds are
    // public/keyless; Binance supplies the BRL pairs Coinbase doesn't list.
    var provider: CryptoProvider { currency == .brl ? .binance : .coinbase }
    var productID: String {
        provider == .coinbase ? "\(symbol)-\(currency.code)" : "\(symbol)\(currency.code)"
    }
}

enum CryptoProvider: String, CaseIterable {
    case coinbase, binance

    var name: String { self == .coinbase ? "Coinbase" : "Binance" }
    var url: URL {
        switch self {
        case .coinbase: return URL(string: "wss://ws-feed.exchange.coinbase.com")!
        case .binance: return URL(string: "wss://data-stream.binance.vision:443/ws")!
        }
    }

    func subscription(for markets: Set<CryptoMarket>) -> String {
        let products = markets.map(\.productID).sorted()
        let message: [String: Any]
        switch self {
        case .coinbase:
            message = ["type": "subscribe", "product_ids": products,
                       "channels": ["ticker", "heartbeat"]]
        case .binance:
            message = ["method": "SUBSCRIBE", "params": products.map { "\($0.lowercased())@ticker" },
                       "id": 1]
        }
        // Only strings, arrays and integers built above, so serialization cannot fail.
        return String(decoding: try! JSONSerialization.data(withJSONObject: message), as: UTF8.self)
    }
}

struct CryptoPriceSnapshot {
    enum Status { case loading, live, stale, unavailable }
    let price: Decimal?
    let status: Status
}

/// A narrow transport seam keeps reconnection and decoding tests off the network.
protocol CryptoWebSocket: AnyObject {
    func resume()
    func send(_ text: String, completion: @escaping (Error?) -> Void)
    func receive(completion: @escaping (Result<String, Error>) -> Void)
    func ping(completion: @escaping (Error?) -> Void)
    func cancel()
}

private final class URLSessionCryptoWebSocket: CryptoWebSocket {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 64 * 1024
    }

    func resume() { task.resume() }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        task.send(.string(text), completionHandler: completion)
    }
    func receive(completion: @escaping (Result<String, Error>) -> Void) {
        task.receive { result in
            completion(result.map { message in
                switch message {
                case .string(let text): return text
                case .data(let data): return String(decoding: data, as: UTF8.self)
                @unknown default: return ""
                }
            })
        }
    }
    func ping(completion: @escaping (Error?) -> Void) { task.sendPing(pongReceiveHandler: completion) }
    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
    deinit { cancel() }
}

/// One socket per provider, shared by every layout/group/duplicate widget.
/// State is main-thread confined. Networking is asynchronous; tick() only
/// checks deadlines, and widgets read the cache on the app's existing ticker.
final class CryptoPriceService {
    static let shared = CryptoPriceService()
    typealias SocketFactory = (URL) -> CryptoWebSocket

    private let makeSocket: SocketFactory
    private let now: () -> Date
    private var connections: [CryptoProvider: CryptoPriceConnection] = [:]

    init(makeSocket: @escaping SocketFactory = { URLSessionCryptoWebSocket(url: $0) },
         now: @escaping () -> Date = Date.init) {
        self.makeSocket = makeSocket
        self.now = now
    }

    func configure(markets: Set<CryptoMarket>) {
        for provider in CryptoProvider.allCases {
            let wanted = Set(markets.filter { $0.provider == provider })
            // Appearance-only config reloads shouldn't open another connection.
            if connections[provider]?.markets == wanted, connections[provider]?.isStopped == false { continue }
            connections.removeValue(forKey: provider)?.stop()
            guard !wanted.isEmpty else { continue }
            let connection = CryptoPriceConnection(provider: provider, markets: wanted,
                                                   makeSocket: makeSocket, now: now)
            connections[provider] = connection
            connection.connect()
        }
    }

    func snapshot(for market: CryptoMarket, staleAfter: TimeInterval = 30) -> CryptoPriceSnapshot {
        connections[market.provider]?.snapshot(for: market, staleAfter: staleAfter)
            ?? CryptoPriceSnapshot(price: nil, status: .unavailable)
    }

    func stop() {
        connections.values.forEach { $0.stop() }
        connections.removeAll()
    }

    deinit { stop() }
}

private final class CryptoPriceConnection {
    let markets: Set<CryptoMarket>
    private let provider: CryptoProvider
    private let products: [String: CryptoMarket]
    private let makeSocket: CryptoPriceService.SocketFactory
    private let now: () -> Date
    private let decoder = JSONDecoder()
    private var socket: CryptoWebSocket?
    private var generation = 0
    private var failures = 0
    private var hasFailed = false
    private var openedAt: Date?
    private var lastMessageAt: Date?
    private var pendingPingAt: Date?
    private var unsupported: Set<CryptoMarket> = []
    private(set) var isStopped = false

    private struct Quote {
        let price: Decimal
        let receivedAt: Date
        let sequence: UInt64?
        let generation: Int
    }
    private var quotes: [CryptoMarket: Quote] = [:]

    init(provider: CryptoProvider, markets: Set<CryptoMarket>,
         makeSocket: @escaping CryptoPriceService.SocketFactory, now: @escaping () -> Date) {
        self.provider = provider
        self.markets = markets
        products = Dictionary(uniqueKeysWithValues: markets.map { ($0.productID, $0) })
        self.makeSocket = makeSocket
        self.now = now
    }

    func connect() {
        guard !isStopped, socket == nil, !markets.subtracting(unsupported).isEmpty else { return }
        generation += 1
        let token = generation
        openedAt = now()
        lastMessageAt = nil
        pendingPingAt = nil
        let socket = makeSocket(provider.url)
        self.socket = socket
        socket.resume()
        receive(token: token)
        schedulePing(token: token)
        socket.send(provider.subscription(for: markets.subtracting(unsupported))) { [weak self] error in
            Self.onMain {
                guard let self, self.isCurrent(token), let error else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    func snapshot(for market: CryptoMarket, staleAfter: TimeInterval) -> CryptoPriceSnapshot {
        guard markets.contains(market), !unsupported.contains(market), !isStopped else {
            return CryptoPriceSnapshot(price: nil, status: .unavailable)
        }
        if let quote = quotes[market] {
            let fresh = socket != nil && quote.generation == generation
                && now().timeIntervalSince(quote.receivedAt) <= staleAfter
            return CryptoPriceSnapshot(price: quote.price, status: fresh ? .live : .stale)
        }
        let waitingTooLong = openedAt.map { now().timeIntervalSince($0) >= 15 } ?? true
        return CryptoPriceSnapshot(price: nil, status: hasFailed || waitingTooLong ? .unavailable : .loading)
    }

    func stop() {
        isStopped = true
        generation += 1
        socket?.cancel()
        socket = nil
    }

    /// One-shot main-queue work keeps protocol heartbeats and reconnects
    /// independent of the user's Touch Bar redraw interval.
    private func schedulePing(token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            // Coinbase sends an application heartbeat every second. A healthy
            // TCP connection alone doesn't prove its ticker subscription lives.
            if self.provider == .coinbase,
               let lastContact = self.lastMessageAt ?? self.openedAt,
               self.now().timeIntervalSince(lastContact) >= 30 {
                self.fail("market feed went silent")
                return
            }
            // Binance closes sockets at 24h; rotate proactively.
            if self.provider == .binance, let openedAt = self.openedAt,
               self.now().timeIntervalSince(openedAt) >= 23 * 3600 + 50 * 60 {
                self.fail("rotating market connection")
                return
            }
            guard let socket = self.socket else { return }
            let sentAt = self.now()
            self.pendingPingAt = sentAt
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, self.isCurrent(token), self.pendingPingAt == sentAt else { return }
                self.fail("heartbeat timed out")
            }
            socket.ping { [weak self] error in
                Self.onMain {
                    guard let self, self.isCurrent(token), self.pendingPingAt == sentAt else { return }
                    self.pendingPingAt = nil
                    if let error {
                        self.fail(error.localizedDescription)
                    } else {
                        self.schedulePing(token: token)
                    }
                }
            }
        }
    }

    private func receive(token: Int) {
        socket?.receive { [weak self] result in
            Self.onMain {
                guard let self, self.isCurrent(token) else { return }
                switch result {
                case .success(let text):
                    self.lastMessageAt = self.now()
                    self.consume(text)
                    if self.isCurrent(token) { self.receive(token: token) }
                case .failure(let error): self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func consume(_ text: String) {
        let data = Data(text.utf8)
        switch provider {
        case .coinbase:
            guard let message = try? decoder.decode(CoinbaseMessage.self, from: data) else { return }
            switch message.type {
            case "ticker":
                accept(product: message.productID, price: message.price, sequence: message.sequence)
            case "subscriptions":
                guard let channels = message.channels else { return }
                let subscribed = Set(channels.filter { $0.name == "ticker" }.flatMap(\.productIDs))
                unsupported = Set(markets.filter { !subscribed.contains($0.productID) })
                if unsupported == markets { stop() }
            case "error":
                // Invalid products are omitted from the following subscription
                // acknowledgement; don't disconnect valid products alongside them.
                Log.widget.error("Coinbase crypto feed: \(message.message ?? "unknown error", privacy: .public), \(message.reason ?? "", privacy: .public)")
            default: break
            }
        case .binance:
            guard let message = try? decoder.decode(BinanceMessage.self, from: data) else { return }
            if let code = message.code, code != 0 {
                fail(message.message ?? "subscription rejected (\(code))")
            } else if message.eventType == "24hrTicker" {
                // Binance's event timestamp can repeat for trades in the same
                // millisecond; arrival order on this socket is authoritative.
                accept(product: message.symbol, price: message.lastPrice, sequence: nil)
            }
        }
    }

    private func accept(product: String?, price: String?, sequence: UInt64?) {
        guard let product, let market = products[product], !unsupported.contains(market),
              let price, price.count <= 64,
              price.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value > 0 else { return }
        if let previous = quotes[market], previous.generation == generation,
           let oldSequence = previous.sequence, let sequence, sequence <= oldSequence { return }
        quotes[market] = Quote(price: value, receivedAt: now(), sequence: sequence, generation: generation)
        failures = 0
        hasFailed = false
    }

    private func fail(_ reason: String) {
        guard !isStopped, socket != nil else { return }
        generation += 1 // Invalidate pending send/receive/ping completions before canceling.
        socket?.cancel()
        socket = nil
        pendingPingAt = nil
        hasFailed = true
        let delay = min(60.0, pow(2.0, Double(min(failures, 6))))
        failures += 1
        Log.widget.error("\(self.provider.name, privacy: .public) crypto feed: \(reason, privacy: .public); retry in \(delay)s")
        // Generation invalidates queued ping/receive work if config reloads or
        // app shutdown happens during the delay.
        let failedGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopped, self.socket == nil,
                  self.generation == failedGeneration else { return }
            self.connect()
        }
    }

    private func isCurrent(_ token: Int) -> Bool { !isStopped && socket != nil && generation == token }

    private static func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    private struct CoinbaseMessage: Decodable {
        let type: String
        var productID: String?
        var price: String?
        var sequence: UInt64?
        var message: String?
        var reason: String?
        var channels: [Channel]?

        enum CodingKeys: String, CodingKey {
            case type
            case productID = "product_id"
            case price
            case sequence
            case message
            case reason
            case channels
        }

        struct Channel: Decodable {
            let name: String
            let productIDs: [String]

            enum CodingKeys: String, CodingKey {
                case name
                case productIDs = "product_ids"
            }
        }
    }

    private struct BinanceMessage: Decodable {
        var eventType: String?
        var symbol: String?
        var lastPrice: String?
        var code: Int?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case eventType = "e"
            case symbol = "s"
            case lastPrice = "c"
            case code
            case message = "msg"
        }
    }
}
