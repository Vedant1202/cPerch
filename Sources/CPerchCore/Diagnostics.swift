import Foundation

// cPerch — diagnostics string for bug reports (v0.6 in-app Help). Pure and Foundation-only so the
// exact, identifier-free shape is unit-tested. The App layer passes the bundle's version and the OS
// version in, copies the result to the clipboard, then opens the GitHub issue form.

/// A small, identifier-free diagnostics block for an issue report, e.g.:
/// ```
/// cPerch 0.5.0
/// macOS 14.5 (23F79)
/// ```
public func diagnosticsText(appVersion: String, osVersion: String) -> String {
    "cPerch \(appVersion)\nmacOS \(osVersion)"
}
