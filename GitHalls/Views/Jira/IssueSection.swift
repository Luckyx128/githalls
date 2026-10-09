//
//  IssueSection.swift
//  GitHalls
//

import SwiftUI

/// The heading every section of the issue window starts with: an icon, a
/// title, and the section's own buttons on the right.
struct IssueSectionHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    let accessory: Accessory

    init(_ title: String, systemImage: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(IssueSectionLabelStyle())
            Spacer(minLength: 8)
            accessory
        }
    }
}

struct IssueSectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: 18)
            configuration.title
        }
    }
}

extension View {
    /// One section of the issue window: a rounded card, so where one ends and
    /// the next begins needs no reading.
    func issueCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06))
            }
    }
}
