//
//  CodeSettingsView.swift
//  GitHalls
//

import AppKit
import Highlightr
import SwiftUI

/// Shared Settings window metrics so every tab opens at the same size.
enum SettingsLayout {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 500
    static let codeHeight: CGFloat = 640
}

/// Theme, font and size of the code in diffs, with a live preview.
struct CodeSettingsView: View {
    @AppStorage(CodeAppearance.lightThemeKey) private var lightTheme = CodeAppearance.defaultLightTheme
    @AppStorage(CodeAppearance.darkThemeKey) private var darkTheme = CodeAppearance.defaultDarkTheme
    @AppStorage(CodeAppearance.fontKey) private var fontID = CodeAppearance.defaultFontID
    @AppStorage(CodeAppearance.sizeKey) private var fontSize = CodeAppearance.defaultSize

    @State private var previewScheme: ColorScheme = .light

    private let fonts = CodeFontCatalog.installedOptions()
    private let themes = CodeThemeCatalog.organize(available: Highlightr()?.availableThemes() ?? [])

    var body: some View {
        Form {
            Section("Theme") {
                themePicker("Light appearance", selection: $lightTheme)
                themePicker("Dark appearance", selection: $darkTheme)
            }

            Section("Font") {
                Picker("Font", selection: $fontID) {
                    ForEach(fonts) { font in
                        Text(font.name).tag(font.id)
                    }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: CodeAppearance.sizeRange, step: 1)
                        Stepper(value: $fontSize, in: CodeAppearance.sizeRange, step: 1) {
                            Text("\(Int(fontSize)) pt").monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
            }

            Section("Preview") {
                Picker("Preview as", selection: $previewScheme) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)

                DiffTextViewRepresentable(
                    diff: Self.sampleDiff,
                    presentation: .intrinsic(maxHeight: 320),
                    colorScheme: previewScheme
                )
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }

            Button("Reset to Defaults") {
                lightTheme = CodeAppearance.defaultLightTheme
                darkTheme = CodeAppearance.defaultDarkTheme
                fontID = CodeAppearance.defaultFontID
                fontSize = CodeAppearance.defaultSize
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width, height: SettingsLayout.codeHeight)
    }

    private func themePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(themes.popular, id: \.self) { id in
                Text(CodeThemeCatalog.prettyName(id)).tag(id)
            }
            Section("More themes") {
                ForEach(themes.more, id: \.self) { id in
                    Text(CodeThemeCatalog.prettyName(id)).tag(id)
                }
            }
        }
    }

    private static let sampleDiff = DiffParser.parse("""
        diff --git a/Greeter.swift b/Greeter.swift
        --- a/Greeter.swift
        +++ b/Greeter.swift
        @@ -1,7 +1,8 @@
         struct Greeter {
             let name: String
        -    func greet() -> String {
        -        return "Hello, " + name
        +    /// Builds the greeting shown on launch.
        +    func greet(loudly: Bool = false) -> String {
        +        let text = "Hello, \\(name)!"
        +        return loudly ? text.uppercased() : text
             }
         }
        """)
}
