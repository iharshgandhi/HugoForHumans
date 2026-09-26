// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// A theme that has been verified to build with the bundled Hugo.
/// Sourced from gohugoio/hugoThemes + the GitHub theme search, then filtered by
/// actually running a build against Hugo v0.166.0 extended.
struct Theme: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var repo: String
    var tagline: String
    var category: Category
    var accent: String          // hex, used for the swatch in the gallery
    var stars: Int?

    enum Category: String, CaseIterable, Identifiable {
        case blog = "Blog"
        case docs = "Documentation"
        case portfolio = "Portfolio"
        case minimal = "Minimal"
        var id: String { rawValue }
    }

    var repoURL: URL? { URL(string: "https://github.com/\(repo)") }
    var starsLabel: String {
        guard let stars else { return "" }
        return stars >= 1000 ? String(format: "%.1fk", Double(stars) / 1000) : "\(stars)"
    }
}

enum ThemeCatalog {

    /// Every entry here was cloned and built successfully against Hugo v0.166.0
    /// extended during development. Verified: 2026-09.
    static let all: [Theme] = [
        Theme(name: "PaperMod", repo: "adityatelange/hugo-PaperMod",
              tagline: "A fast, clean, responsive theme.", category: .blog,
              accent: "#5B8DEF", stars: 13944),
        Theme(name: "hugo-theme-stack", repo: "CaiJimmy/hugo-theme-stack",
              tagline: "Card-style theme designed for bloggers.", category: .blog,
              accent: "#F2704B", stars: 6471),
        Theme(name: "LoveIt", repo: "dillonzq/LoveIt",
              tagline: "A clean, elegant but advanced theme.", category: .blog,
              accent: "#E85D75", stars: 3869),
        Theme(name: "hugo-coder", repo: "luizdepra/hugo-coder",
              tagline: "A minimalist blog theme.", category: .minimal,
              accent: "#2BB3A3", stars: 3113),
        Theme(name: "blowfish", repo: "nunocoracao/blowfish",
              tagline: "Personal website and blog theme.", category: .blog,
              accent: "#F4A259", stars: 2900),
        Theme(name: "terminal", repo: "panr/hugo-theme-terminal",
              tagline: "A simple, retro theme.", category: .minimal,
              accent: "#5BE49B", stars: 2809),
        Theme(name: "hugo-paper", repo: "nanxiaobei/hugo-paper",
              tagline: "A simple, clean, customizable theme.", category: .blog,
              accent: "#8E7CFF", stars: 2416),
        Theme(name: "hextra", repo: "imfing/hextra",
              tagline: "Modern, batteries-included theme.", category: .docs,
              accent: "#0EA5A4", stars: 2362),
        Theme(name: "doks", repo: "thuliteio/doks",
              tagline: "Everything you need to build a documentation site.", category: .docs,
              accent: "#3B82F6", stars: 2359),
        Theme(name: "congo", repo: "jpanther/congo",
              tagline: "A powerful, lightweight Tailwind theme.", category: .blog,
              accent: "#7C6BF7", stars: 1654),
        Theme(name: "bearblog", repo: "janraasch/hugo-bearblog",
              tagline: "Based on the Bear Blog: no-nonsense, super fast.", category: .minimal,
              accent: "#B08968", stars: 1506),
        Theme(name: "archie", repo: "athul/archie",
              tagline: "A minimal theme.", category: .minimal,
              accent: "#D4A373", stars: 1434),
        Theme(name: "ananke", repo: "gohugo-ananke/ananke",
              tagline: "The theme used by the official quick start.", category: .blog,
              accent: "#4CAF93", stars: 1394),
        Theme(name: "beautifulhugo", repo: "halogenica/beautifulhugo",
              tagline: "A beautiful, readable theme.", category: .portfolio,
              accent: "#E76F51", stars: 1233),
        Theme(name: "mainroad", repo: "Vimux/Mainroad",
              tagline: "Responsive, simple, content-focused.", category: .blog,
              accent: "#6A994E", stars: 1049),
        Theme(name: "xmin", repo: "yihui/hugo-xmin",
              tagline: "Extremely minimal, around 140 lines of CSS.", category: .minimal,
              accent: "#1D3557", stars: 975),
    ]

    static func themes(in category: Theme.Category?) -> [Theme] {
        guard let category else { return all }
        return all.filter { $0.category == category }
    }

    static func theme(named name: String) -> Theme? {
        all.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Themes that are known to need extra configuration, so the UI can warn
    /// instead of letting the user hit a wall at build time.
    static func notes(for theme: Theme) -> [String] {
        var notes: [String] = []
        switch theme.name {
        case "hugo-theme-stack":
            notes.append("Stack asks for a few TOML parameters. Edit hugo.toml after installing to add your menu and social links.")
        case "blowfish", "congo", "hextra":
            notes.append("Tailwind-based themes rebuild the whole CSS on first build, so the first preview takes a few seconds.")
        default:
            break
        }
        return notes
    }
}
