import Foundation

/// Creates a demo site through the app's own SiteCreator and SiteEngine, then
/// fills it with real content — the same code path the wizard uses, so the
/// screenshots show the app's actual output rather than a hand-built mock.

@main
struct SampleSiteDriver {
    @MainActor
    static func main() async {
        let root = URL(fileURLWithPath: "DEST_PLACEHOLDER", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let siteRoot = root.appendingPathComponent("the-deep-dive")

        // ---- Step 1: the wizard -------------------------------------------------
        var request = NewSiteRequest()
        request.title = "The Deep Dive"
        request.description = "Notes from a man who read the footnotes, then kept going."
        request.folderName = "the-deep-dive"
        request.destinationFolder = root
        request.theme = ThemeCatalog.theme(named: "PaperMod") ?? ThemeCatalog.all[0]
        request.installTheme = true
        request.initGit = true
        // The seeded placeholder post says "Write here in plain language" — which
        // would look like an unfinished demo. The real posts below replace it.
        request.createFirstPost = false
        request.createAboutPage = true
        request.author = "Gerald Voss"
        request.copyright = "Gerald Voss"
        request.languageCode = "en-us"

        let creator = SiteCreator()
        let created = await creator.begin(with: request, kind: .blog)
        if let error = creator.error {
            print("FAILED to create site: \(error)")
            exit(1)
        }
        print("created: \(created?.lastPathComponent ?? "?")")

        // ---- Step 2: open it and write the real content -------------------------
        let engine = SiteEngine()
        engine.openSite(at: siteRoot)

        let posts: [(String, String, String, [String])] = [
            ("the-tape-that-does-not-add-up",
             "The Tape That Doesn't Add Up",
             """
             I have watched the footage four hundred times. Not because I believe it — because it *works*, and that is the part nobody warns you about.

             Here is what the tapes show. Here is what the telemetry recorded independently. Here is the frame-by-frame arithmetic. Every number below is one I typed myself, from data other people collected, and I still had to sit down afterwards.

             ## The receipts

             | Claim | Standard account | What the numbers show |
             |---|---|---|
             | Object size | Consistent | Varies 12% across frames |
             | Motion blur | Fixed exposure | Shifts with light source |
             | Shadows | Single source | Two sources, second is fixed to rig |

             A single fixed light source attached to the rig. The sun does not do that.

             ## Where I stopped

             I want to be honest about something, because this blog is not a performance. Somewhere around year nine, the research stopped being about the evidence and started being about the *feeling* of not having been told. Those are not the same thing, and I conflated them for a long time.

             That is the part worth writing down.
             """,
             ["evidence", "method", "moonlanding"]),

            ("chemtrails-ive-been-counting-for-six-years",
             "Chemtrails: I've Been Counting for Six Years",
             """
             The official explanation is contrails. Fine. So I counted.

             I logged the sky from my kitchen window every morning for six years, one entry a day, because I wanted a number that wasn't mine. Around 4,200 entries later I have something nobody has ever asked me for: a data set with a hole in it.

             ## The hole

             Between March and June of year three, my entries stop. Not missing at random — a clean three-month gap. I still have the notebook. The pages are there. The dates jump from the 14th to the 2nd and nothing explains it.

             I do not know what that means. I spent a long time hoping it would mean something, and then I realised that hoping is not a method.
             """,
             ["chemtrails", "longterm", "data"]),

            ("the-reptilian-problem",
             "The Reptilian Problem",
             """
             Everyone thinks the reptilian stuff is the crazy end of the rabbit hole. I thought so too, for about a year, and I was wrong about the order of things.

             The evidence is thin. I mean that seriously — it is thin, and I say that as someone who has read all of it more than once. But the *theory* is elegant, and elegance is a trap I have watched a lot of smart people walk into with my own face on.

             ## Why I am writing this

             Not to debunk it. I am not qualified and the genre is flooded with people who are.

             I am writing it because I have watched this thing evolve from a joke I told at parties into a genuine architecture of belief, complete with sourcing, with internal debate, with people who disagree about the details. That is what a *movement* looks like. A bad idea does not do that. A bad idea stays a bad idea.

             That is the part that should worry you, and it is not the lizards.
             """,
             ["reptilians", "belief", "epistemics"]),

            ("everything-is-a-spreadsheet-i-am-behind",
             "Everything Is a Spreadsheet and I Am Behind It",
             """
             Short one. I got into this by accident, by the way. I was not radicalised. I was *vetted*.

             Somewhere in the last fifteen years the cost of being wrong went to zero and the cost of being right about something everyone else had settled went very high. That trade is the whole pipeline. Nobody hands you a leaflet. You just notice the gap, and then you are the person with the gap.
             """,
             ["meta", "epistemics"]),

            ("against-the-alien-thing-yes-really",
             "Against the Alien Thing. Yes, Really.",
             """
             I built a considerable part of my identity on this. I am putting it down.

             Not because someone debunked it — people have been debunking it for sixty years and the debunkings are, if anything, the strongest evidence for the believers. No. I am putting it down because I caught myself doing the thing: reaching for the *most* interesting explanation when the boring one is already sufficient.

             Boring explanations are the ones that survive contact with other people. I do not want to be the person whose ideas can only be checked by other people with the same idea.
             """,
             ["aliens", "belief", "changeofmind"])
        ]

        for (slug, title, body, tags) in posts {
            let created = await engine.createPage(section: "posts", name: slug)
            guard let item = created else {
                print("could not create post \(slug)")
                continue
            }
            var updated = item
            updated.frontMatter["title"] = .string(title)
            updated.frontMatter["date"] = .string(Self.dateFor(index: posts.firstIndex { $0.0 == slug } ?? 0, total: posts.count))
            updated.frontMatter["draft"] = .bool(false)
            updated.frontMatter["tags"] = .list(tags)
            updated.frontMatter["description"] = .string(body.split(separator: "\n").first.map(String.init) ?? "")
            updated.frontMatter.body = body
            try? engine.save(updated)
            print("post: \(title)")
        }

        // ---- Step 3: a second section, the way "Add Section" does it --------------
        _ = await engine.createPage(section: "method", name: "how-i-check-things")
        if var method = engine.items.first(where: { $0.section == "method" }) {
            method.frontMatter["title"] = .string("How I Check Things")
            method.frontMatter["body"] = .string("")
            method.frontMatter.body = """
            Everything on this site is written down, including the parts that make me look foolish. That is the entire method.

            ## 1. Write the standard account first

            Not the debunking. The *actual* strongest version, the one the experts in the field would defend. If I cannot state it well, I have no standing to disagree with it.

            ## 2. Then find the weakest link in *my own* case

            Not theirs. Mine. Every time, the thing that finally moved me was someone doing this to me.

            ## 3. Screenshot the trail

            Sources, dates, what changed and when. The archive goes up, not down.

            ## 4. Publish the wrong ones

            The post about the alien thing stays up. I did not quietly delete it when I changed my mind, because a blog that only ever contains your current opinions is not a record of anything. It is a mood.
            """
            try? engine.save(method)
            print("section: How I Check Things")
        }

        // ---- Step 4: the about page ----------------------------------------------
        if var about = engine.items.first(where: { $0.relativePath.hasPrefix("about") }) {
            about.frontMatter["title"] = .string("About")
            about.frontMatter.body = """
            I am Gerald Voss. I have been wrong publicly, at length, for fifteen years, and I have kept the receipts the whole time.

            This is not a call to action. I do not think you should believe any of this. I think you should notice what it costs a person to be wrong in public, and then notice what that says about which of our beliefs are actually held.

            Everything here is written in public and dated. If I am wrong about something, you can find the post where I was wrong about it, because I did not delete it.
            """
            try? engine.save(about)
        }

        // ---- Step 5: build -------------------------------------------------------
        let builder = Builder()
        let status = await builder.build(root: siteRoot, engine: engine)
        print("build: \(status)")
        print("items: \(engine.items.count)")
        print("sections: \(engine.sections.map { $0.name }.joined(separator: ", "))")
        print("SITE_ROOT: \(siteRoot.path)")
    }

    /// Datestamps posts newest-first so the archive reads correctly.
    static func dateFor(index: Int, total: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let daysAgo = (total - index) * 11
        return formatter.string(from: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }
}
