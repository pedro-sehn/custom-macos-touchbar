import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "com.pedro.touchbarapp", category: "app")
    static let dfr = Logger(subsystem: "com.pedro.touchbarapp", category: "dfr")
    static let config = Logger(subsystem: "com.pedro.touchbarapp", category: "config")
    static let widget = Logger(subsystem: "com.pedro.touchbarapp", category: "widget")
}
