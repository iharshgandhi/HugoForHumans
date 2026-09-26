// swift-tools-version: 5.9
import PackageDescription

// A single executable target holds the whole app: models, Hugo plumbing, SwiftUI
// views, and the @main entry point. One module, because a module boundary would
// force `public` onto hundreds of view members and leak internals for no benefit —
// this is an application, not a framework.
//
// The test suite is not a SwiftPM target. Executing an XCTest bundle needs a full
// Xcode install, and the Command Line Tools alone cannot run one, so the tests are
// compiled and run by Scripts/test.sh instead. That keeps `swift test` from being
// a trap and gives a suite that works everywhere the app builds.
// Hugo for Humans — a native front end for Hugo.
//
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
//
// Licensed under the GNU General Public License v3.0 or later. See LICENSE.
let package = Package(
    name: "HugoForHumans",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HugoForHumans",
            path: "Sources/HugoForHumans"
        ),
    ]
)
