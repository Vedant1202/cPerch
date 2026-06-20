import AppKit
import SwiftUI
import CPerchCore

// cPerch — in-app Help (v0.6), shown inside the popover in place of the session list. Reached via
// the "?" in the RosterView footer; `onBack` returns to the list. Concise reference, not docs:
// it explains the icons, the shortcut, the settings, accessibility, privacy, and how to report an
// issue, and it links out for depth. External links open in the browser (NSWorkspace) and the
// diagnostics copy uses NSPasteboard — cPerch itself makes no network request and needs no new
// permission. The status colors/names live in CPerchCore so the legend can't drift from the app.

struct HelpView: View {
    var onBack: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Cap the scroll height to the same screen-relative bound the list uses.
    var maxHeight: CGFloat = 420

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var copied = false

    private let privacyURL = "https://vedant1202.github.io/cPerch/privacy.html"
    private let issueURL = "https://github.com/Vedant1202/cPerch/issues/new/choose"

    /// The bundle's marketing version (e.g. "0.5.0"); "unknown" under a bare `swift run`.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(TokenColors.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    iconsSection
                    openSection
                    settingsSection
                    accessibilitySection
                    privacySection
                    issueSection
                    aboutSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: maxHeight)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Help").font(TokenFonts.ui(13, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var iconsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("What the icons mean")
            legendRow(.needsInput, "Needs input", "A session is waiting on you.")
            legendRow(.running, "Running", "Actively working — nothing needed from you.")
            legendRow(.concluded, "Concluded", "Finished, with nothing pending.")
            Text("In the menu bar, the dot sits on a white plate so it stays visible on any wallpaper, "
                 + "shows a number when more than one session needs you, and turns into the green check "
                 + "when everything is done.")
                .font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legendRow(_ status: DerivedStatus, _ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Tokens.symbolName(for: statusSymbol(for: status)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Tokens.statusColor(status,
                                                          highContrast: contrast == .increased,
                                                          dark: colorScheme == .dark)))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(TokenFonts.ui(12, weight: .medium))
                Text(desc).font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
            }
        }
    }

    private var openSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Open cPerch")
            Text("Click the cPerch icon in the menu bar, or press ⌘⌥` from any app.")
                .font(TokenFonts.ui(12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Settings")
            bullet("General", "Theme, list layout, how long finished sessions stay, and launch at login.")
            bullet("Notifications", "Which events notify you, Focus / Do Not Disturb behavior, and how long banners stay.")
            bullet("Accessibility", "Status shapes, high contrast, and reduced motion / transparency.")
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Accessibility")
            Text("cPerch shows each status with a shape and a color, so states are clear even in "
                 + "grayscale or with color blindness. It also offers a high-contrast mode, VoiceOver "
                 + "labels, and respects Reduce Motion and Reduce Transparency. Adjust these in "
                 + "Settings → Accessibility.")
                .font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Privacy")
            Text("cPerch works entirely on your Mac and sends nothing over the network.")
                .font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            externalLink("Privacy policy", privacyURL)
        }
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Report an issue")
            Text("Copy a short diagnostics summary (cPerch and macOS versions only — no personal data), "
                 + "then open the issue form and paste it in.")
                .font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy diagnostics", action: copyDiagnostics)
                    .buttonStyle(.bordered).controlSize(.small)
                externalLink("Open issue form", issueURL)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("About")
            Text("cPerch \(appVersion)").font(TokenFonts.ui(12, weight: .medium))
            Text("A perch for your Claude sessions.").font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
            Text("MIT License").font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
        }
    }

    // MARK: - Bits

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(TokenFonts.ui(10, weight: .semibold))
            .foregroundStyle(TokenColors.secondaryText)
    }

    private func bullet(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(TokenFonts.ui(12, weight: .medium))
            Text(desc).font(TokenFonts.ui(11)).foregroundStyle(TokenColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A link that leaves the app — opens in the default browser, marked with `arrow.up.right`.
    private func externalLink(_ label: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(TokenFonts.ui(12, weight: .medium))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(TokenColors.running)
    }

    private func copyDiagnostics() {
        let text = diagnosticsText(appVersion: appVersion,
                                   osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}
