// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

#if !canImport(Combine)

/// Observation support for platforms without Combine.
///
/// Four types in this app are `ObservableObject`s purely so the UI redraws when
/// their data changes: `SiteEngine`, `Builder`, `PreviewServer`, and the
/// preview state. The logic in those types — reading a site, running Hugo,
/// managing a process — has nothing to do with Combine, and
/// swift-corelibs-foundation has no Combine, so a Linux client would not compile
/// them as written.
///
/// Rather than fork those types or scatter `#if` through their bodies, the two
/// Combine spellings are provided here. On Apple this file compiles to nothing
/// at all. Off Apple it supplies just enough for the same source to build, with
/// the limitation stated below.
///
/// - Important: `Published` stores the value and does not notify anyone. A
///   non-Apple client therefore gets correct *behaviour* but no change
///   notification, so a UI built on it must re-read explicitly. That is a real
///   limitation, recorded here rather than papered over: removing it needs a
///   notification mechanism for the target platform, which is that UI's choice
///   to make, not this file's.

/// A stored property, standing in for `@Published`.
///
/// The wrapped value behaves identically; only the observation is missing.
@propertyWrapper
struct Published<Value> {
    private var storage: Value

    init(wrappedValue: Value) {
        self.storage = wrappedValue
    }

    var wrappedValue: Value {
        get { storage }
        set { storage = newValue }
    }

    /// Exists so `$property` still type-checks at a use site. It returns the
    /// wrapper itself, because there is no publisher to hand back.
    var projectedValue: Published<Value> { self }
}

/// Marker standing in for `ObservableObject`.
///
/// It carries no behaviour, so an empty class is the entire requirement.
class ObservableObjectBase {}

#endif  // !canImport(Combine)

#if canImport(Combine)

/// On Apple platforms the real `ObservableObject` protocol.
typealias ObservationBase = ObservableObject

#else

/// Elsewhere, the empty stand-in. The logic of the types that inherit this is
/// unchanged; only the redraw notification is missing.
typealias ObservationBase = ObservableObjectBase

#endif
