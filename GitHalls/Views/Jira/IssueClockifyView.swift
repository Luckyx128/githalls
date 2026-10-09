//
//  IssueClockifyView.swift
//  GitHalls
//

import SwiftUI

/// Clockify on the issue: start a timer and stop it later, or log a finished
/// stretch by hand. The description, project, task and tags come prefilled —
/// "[KEY]: summary", the project and tags last used for this Jira project, and
/// the task named after the key — and every one of them can be changed.
struct IssueClockifyView: View {
    let issueKey: String
    let summary: String
    @Bindable var clockify: ClockifyViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case timer = "Timer"
        case manual = "Manual"
        var id: Self { self }
    }

    @State private var mode: Mode = .timer
    @State private var entryDescription = ""
    @State private var projectID: String?
    @State private var taskID: String?
    @State private var tagIDs: [String] = []
    @State private var tasks: [ClockifyTask] = []
    @State private var taskSearch = ""
    @State private var isSearchingTasks = false
    @State private var day = Date.now
    @State private var startTime = Date.now.addingTimeInterval(-3600)
    @State private var endTime = Date.now
    @State private var result: String?

    private var jiraProject: String { ClockifyViewModel.jiraProjectKey(of: issueKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !clockify.isConfigured {
                HStack {
                    Text("Connect Clockify to log time from here.").foregroundStyle(.secondary)
                    SettingsLink { Text("Open Settings") }
                }
                .font(.callout)
            } else if clockify.user == nil {
                if clockify.isLoading { ProgressView().controlSize(.small) }
            } else {
                runningBanner
                form
            }

            if let error = clockify.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if let result {
                Text(result).font(.callout).foregroundStyle(.secondary)
            }
        }
        .task(id: issueKey) {
            entryDescription = ClockifyViewModel.description(key: issueKey, summary: summary)
            await clockify.load()
            await clockify.refreshRunning()
            applyRemembered()
        }
        // Projects arrive after the workspace does; what to preselect needs them.
        .onChange(of: clockify.projects) { _, _ in applyRemembered() }
        .task(id: projectID) { await findTasks(matching: issueKey, autoSelect: true) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Clockify", systemImage: "timer").font(.headline).labelStyle(IssueSectionLabelStyle())
            Spacer()
            if clockify.workspaces.count > 1 {
                Picker("Workspace", selection: Binding(
                    get: { clockify.workspaceID ?? "" },
                    set: { id in Task { await clockify.selectWorkspace(id) } }
                )) {
                    ForEach(clockify.workspaces) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: - Running timer

    @ViewBuilder
    private var runningBanner: some View {
        if let running = clockify.running {
            HStack(spacing: 10) {
                Image(systemName: "record.circle").foregroundStyle(.red).symbolEffect(.pulse)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ClockifyViewModel.clock(context.date.timeIntervalSince(running.start)))
                        .font(.title3.monospacedDigit())
                }
                Text(running.description.isEmpty ? "No description" : running.description)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") {
                    Task {
                        let elapsed = Date.now.timeIntervalSince(running.start)
                        if await clockify.stopTimer() {
                            result = "Stopped at \(ClockifyViewModel.clock(elapsed)) and saved to Clockify."
                        }
                    }
                }
                .disabled(clockify.isWriting)
                .help("Stop the timer and save the entry")
            }
            .padding(8)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            TextField("What are you working on?", text: $entryDescription)
                .textFieldStyle(.roundedBorder)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Project").foregroundStyle(.secondary)
                    Picker("Project", selection: $projectID) {
                        Text("No project").tag(String?.none)
                        ForEach(clockify.projects) { Text($0.label).tag(String?.some($0.id)) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Task").foregroundStyle(.secondary)
                    taskRow
                }
                GridRow {
                    Text("Tags").foregroundStyle(.secondary)
                    tagMenu
                }
            }
            .font(.callout)

            switch mode {
            case .timer: timerControls
            case .manual: manualControls
            }
        }
    }

    private var taskRow: some View {
        HStack {
            Picker("Task", selection: $taskID) {
                Text("No task").tag(String?.none)
                ForEach(tasks) { Text($0.name).tag(String?.some($0.id)) }
            }
            .labelsHidden()
            .disabled(projectID == nil)

            TextField("Find task", text: $taskSearch)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .disabled(projectID == nil)
                .onSubmit { Task { await findTasks(matching: taskSearch, autoSelect: false) } }

            if isSearchingTasks { ProgressView().controlSize(.small) }
        }
    }

    private var tagMenu: some View {
        Menu {
            ForEach(clockify.tags) { tag in
                Toggle(tag.name, isOn: Binding(
                    get: { tagIDs.contains(tag.id) },
                    set: { on in
                        if on { tagIDs.append(tag.id) } else { tagIDs.removeAll { $0 == tag.id } }
                    }
                ))
            }
        } label: {
            let names = clockify.tags.filter { tagIDs.contains($0.id) }.map(\.name)
            Text(names.isEmpty ? "No tags" : names.joined(separator: ", "))
        }
        .fixedSize()
        .disabled(clockify.tags.isEmpty)
    }

    private var isTimingThisIssue: Bool {
        clockify.running?.description.contains("[\(issueKey)]") == true
    }

    private var timerControls: some View {
        HStack {
            Button {
                Task {
                    if await clockify.startTimer(entry(end: nil)) {
                        remember()
                        result = "Timer started."
                    }
                }
            } label: {
                Label(clockify.running == nil ? "Start Timer" : "Switch Timer to This", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(clockify.isWriting || isTimingThisIssue)
            .help(clockify.running == nil
                  ? "Start a Clockify timer for this issue"
                  : "Stop the running timer and start one for this issue")

            if clockify.isWriting { ProgressView().controlSize(.small) }
        }
    }

    private var manualInterval: (start: Date, end: Date)? {
        let start = Self.combine(day: day, time: startTime)
        let end = Self.combine(day: day, time: endTime)
        return end > start ? (start, end) : nil
    }

    private var manualControls: some View {
        HStack(spacing: 8) {
            DatePicker("Date", selection: $day, displayedComponents: .date).labelsHidden()
            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute).labelsHidden()
            Text("–")
            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute).labelsHidden()

            if let interval = manualInterval {
                Text(ClockifyViewModel.clock(interval.end.timeIntervalSince(interval.start)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button("Add Time") {
                guard let interval = manualInterval else { return }
                Task {
                    var new = entry(end: interval.end)
                    new.start = interval.start
                    if await clockify.addTime(new) {
                        remember()
                        result = "Logged \(ClockifyViewModel.clock(interval.end.timeIntervalSince(interval.start))) to Clockify."
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(clockify.isWriting || manualInterval == nil)
            .help(manualInterval == nil ? "The end has to come after the start" : "Send this time to Clockify")
        }
    }

    // MARK: - Actions

    private func entry(end: Date?) -> ClockifyNewEntry {
        ClockifyNewEntry(
            description: entryDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: projectID,
            taskID: taskID,
            tagIDs: tagIDs,
            start: .now,
            end: end
        )
    }

    /// The project and tags this Jira project used last time, when they still exist.
    private func applyRemembered() {
        guard let workspaceID = clockify.workspaceID else { return }
        let project = ClockifyPreferences.projectID(forJiraProject: jiraProject, workspaceID: workspaceID)
        projectID = clockify.projects.contains { $0.id == project } ? project : nil
        let known = Set(clockify.tags.map(\.id))
        tagIDs = ClockifyPreferences.tagIDs(forJiraProject: jiraProject, workspaceID: workspaceID).filter(known.contains)
    }

    private func remember() {
        guard let workspaceID = clockify.workspaceID else { return }
        ClockifyPreferences.remember(projectID: projectID, tagIDs: tagIDs, forJiraProject: jiraProject, workspaceID: workspaceID)
    }

    private func findTasks(matching name: String, autoSelect: Bool) async {
        guard let projectID else {
            tasks = []
            taskID = nil
            return
        }

        isSearchingTasks = true
        defer { isSearchingTasks = false }

        let found = (try? await clockify.tasks(projectID: projectID, matching: name)) ?? []
        // Keep the chosen task listed even when a new search no longer finds it.
        let chosen = tasks.first { $0.id == taskID }
        tasks = found + (chosen.map { found.contains($0) ? [] : [$0] } ?? [])

        if autoSelect {
            taskID = ClockifyViewModel.task(for: issueKey, in: found)?.id
        }
    }

    nonisolated static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? day
    }
}
