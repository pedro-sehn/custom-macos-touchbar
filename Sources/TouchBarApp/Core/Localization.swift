import Foundation

/// App-chrome translations.
///
/// Deliberately a plain table rather than `.lproj` bundles + `NSLocalizedString`:
/// the app is assembled by a shell script with no Xcode build phase to compile
/// `.strings` files, and the string count is small enough that a dictionary is
/// easier to audit than a scattered set of resource files.
///
/// Adding a language means one entry in `tables` — the key set is checked
/// against English at startup, so a partial translation logs what it's missing
/// and falls back per-key instead of showing blanks.
enum L10n {
    /// Language code in effect: a config override, or the system's preference.
    private(set) static var code = "en"
    /// Locale used for date and number formatting.
    private(set) static var locale = Locale.current

    private static let english: [String: String] = [
        "menu.toggle": "Toggle Touch Bar",
        "menu.reload": "Reload Config",
        "menu.edit": "Edit Config…",
        "menu.launchAtLogin": "Launch at Login",
        "menu.quit": "Quit",
        "bar.back": "‹ Back",
        "pomodoro.title": "Pomodoro",
        "pomodoro.workDone": "Pomodoro done — take a break",
        "pomodoro.breakDone": "Break over — back to work"
    ]

    private static let tables: [String: [String: String]] = [
        "en": english,
        "pt": [
            "menu.toggle": "Alternar Touch Bar",
            "menu.reload": "Recarregar configuração",
            "menu.edit": "Editar configuração…",
            "menu.launchAtLogin": "Abrir ao iniciar",
            "menu.quit": "Sair",
            "bar.back": "‹ Voltar",
            "pomodoro.title": "Pomodoro",
            "pomodoro.workDone": "Pomodoro concluído — faça uma pausa",
            "pomodoro.breakDone": "Pausa encerrada — de volta ao trabalho"
        ],
        "ja": [
            "menu.toggle": "Touch Bar を切り替え",
            "menu.reload": "設定を再読み込み",
            "menu.edit": "設定を編集…",
            "menu.launchAtLogin": "ログイン時に起動",
            "menu.quit": "終了",
            "bar.back": "‹ 戻る",
            "pomodoro.title": "ポモドーロ",
            "pomodoro.workDone": "ポモドーロ終了 — 休憩しましょう",
            "pomodoro.breakDone": "休憩終了 — 作業に戻りましょう"
        ],
        "es": [
            "menu.toggle": "Alternar Touch Bar",
            "menu.reload": "Recargar configuración",
            "menu.edit": "Editar configuración…",
            "menu.launchAtLogin": "Abrir al iniciar",
            "menu.quit": "Salir",
            "bar.back": "‹ Atrás",
            "pomodoro.title": "Pomodoro",
            "pomodoro.workDone": "Pomodoro terminado — toma un descanso",
            "pomodoro.breakDone": "Descanso terminado — de vuelta al trabajo"
        ]
    ]

    /// `language` is a config value: a code like "pt", "pt-BR", "es", or
    /// "auto"/nil to follow the system.
    static func configure(language: String?) {
        let requested = (language?.isEmpty == false ? language! : "auto").lowercased()

        if requested == "auto" {
            locale = Locale.current
            code = Self.resolve(Locale.current.identifier) ?? "en"
        } else {
            // "jp" is a country code, not a language: Locale would resolve it to
            // something unrelated, so canonicalise before building the locale.
            locale = Locale(identifier: Self.canonicalIdentifier(requested))
            if let resolved = Self.resolve(requested) {
                code = resolved
            } else {
                code = "en"
                Log.config.error("no translations for '\(requested, privacy: .public)', using English")
            }
        }

        warnAboutGaps()
        Log.config.notice("language: \(code, privacy: .public), locale: \(locale.identifier, privacy: .public)")
    }

    /// Country codes people reach for instead of the ISO 639 language code.
    private static let aliases = [
        "jp": "ja",   // Japan vs. Japanese
        "br": "pt",
        "cn": "zh",
        "gb": "en", "uk": "en", "us": "en"
    ]

    /// Matches "pt-BR" / "pt_BR" to the "pt" table; region variants share strings.
    private static func resolve(_ identifier: String) -> String? {
        let base = identifier.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? identifier.lowercased()
        let resolved = aliases[base] ?? base
        return tables[resolved] != nil ? resolved : nil
    }

    /// Swaps an aliased country code for its language code, keeping any region
    /// suffix: "jp" → "ja", "br-BR" → "pt-BR", "pt-BR" → "pt-BR".
    private static func canonicalIdentifier(_ identifier: String) -> String {
        var parts = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = parts.first, let mapped = aliases[first.lowercased()] else { return identifier }
        parts[0] = mapped
        return parts.joined(separator: "-")
    }

    private static func warnAboutGaps() {
        guard code != "en", let table = tables[code] else { return }
        let missing = Set(english.keys).subtracting(table.keys).sorted()
        guard !missing.isEmpty else { return }
        Log.config.error("translation '\(code, privacy: .public)' missing \(missing.count) key(s): \(missing.joined(separator: ", "), privacy: .public)")
    }

    /// Falls back to English per key, so a partial translation degrades
    /// gracefully rather than rendering an empty button.
    static func string(_ key: String) -> String {
        tables[code]?[key] ?? english[key] ?? key
    }
}
