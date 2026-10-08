# Jira API surface (JiraClient / JiraViewModel)

Owner: Atlas (feat/jira-api). Everything below is `async throws` on `JiraClient`
unless noted; all of it is unit tested with a mock `URLProtocol` (no network).
`JiraClient(credentials:)` keeps working; tests inject
`JiraClient(credentials:, session:)`. Models live in `GitHalls/Jira/`.
Status: **shipped on feat/jira-api** (phases 1–5). Where this file and the code
differ, the code wins; the notes at the end list the deliberate differences.

## Models (all `Equatable, Hashable, Sendable`)

```swift
struct JiraUser        { accountID, displayName, email?, avatarURL?, active }
struct JiraProject     { id, key, name }
struct JiraIssueType   { id, name, isSubtask, hierarchyLevel }
struct JiraFieldOption { id, label }                      // priority, component, select option
struct JiraCreateField { key, name, required, kind: JiraFieldKind, allowed: [JiraFieldOption], hasDefault }
enum   JiraFieldKind   { string, number, date, dateTime, user, option, priority, labels, components, adf, other(String) }
struct JiraNewIssue    { projectKey, issueTypeID, summary, description: String?, priorityID?, labels, componentIDs,
                         assigneeAccountID?, parentKey?, dueDate: String? /* yyyy-MM-dd */, extra: [JiraFieldUpdate] }
struct JiraFieldUpdate { field: String, value: JiraJSON }   // builders: .summary .description .priority .labels
                                                          // .components .dueDate .storyPoints(fieldID:) .parent .custom
enum   JiraJSON        { string, number, bool, null, array, object }  // Sendable JSON for custom fields
struct JiraComment     { id, author: JiraUser?, body: String /*plain*/, created: Date?, updated: Date? }
struct JiraWorklog     { id, author, timeSpentSeconds, started: Date?, comment: String }
struct JiraAttachment  { id, filename, size, mimeType, contentURL, thumbnailURL?, author, created }
struct JiraLinkType    { id, name, inward, outward }
struct JiraIssueLink   { id, typeName, label, direction, issue: JiraIssueRef }
struct JiraIssueRef    { key, summary, status, statusCategory, type }
struct JiraVotes       { count, hasVoted }
struct JiraBoard       { id, name, type /*scrum|kanban*/, projectKey? }
struct JiraBoardColumn { name, statusIDs: [String], min?, max? }
struct JiraBoardConfiguration { boardID, name, columns, estimationFieldID?, rankFieldID? }
struct JiraSprint      { id, name, state: .future/.active/.closed, startDate?, endDate?, goal?, boardID? }
enum   JiraRankPosition { before(String), after(String) }
struct JiraPage<T>     { items, nextStart: Int?, nextPageToken: String?, isLast }
```

`JiraIssue` gains optional detail fields (all optional so restored windows still
decode): `statusID`, `dueDate`, `components`, `storyPoints`, `parentKey`,
`parentSummary`, `subtasks: [JiraIssueRef]?`, `links: [JiraIssueLink]?`.

`JiraADF.document(from: String) -> [String: Any]` is the inverse of
`JiraADF.plainText(from:)` (paragraphs, line breaks, bullet/ordered lists, nested lists
fences build).

## Phase 1 — create / edit / lookups
```swift
func projects() async throws -> [JiraProject]
func issueTypes(projectKey: String) async throws -> [JiraIssueType]
func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField]
func create(_ issue: JiraNewIssue) async throws -> String                    // new key (also creates subtasks via parentKey)
func edit(key: String, _ updates: [JiraFieldUpdate]) async throws
func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser]
func searchUsers(query: String) async throws -> [JiraUser]
func priorities() async throws -> [JiraFieldOption]
func labels(query: String?) async throws -> [String]
func components(projectKey: String) async throws -> [JiraFieldOption]
func fields() async throws -> [JiraFieldInfo]                                // JiraFieldInfo.storyPointsID(in:)
```
## Phase 2 — comments
```swift
func comments(key: String) async throws -> [JiraComment]
func addComment(key: String, text: String) async throws -> JiraComment
func editComment(key: String, id: String, text: String) async throws -> JiraComment
func deleteComment(key: String, id: String) async throws
```
## Phase 3 — Agile 1.0
```swift
func boards(projectKey: String?) async throws -> [JiraBoard]
func boardConfiguration(boardID: Int) async throws -> JiraBoardConfiguration
func sprints(boardID: Int, states: [JiraSprintState]) async throws -> [JiraSprint]
func boardIssues(boardID: Int, jql: String?, startAt: Int, limit: Int) async throws -> JiraPage<JiraIssue>
func sprintIssues(sprintID: Int, jql: String?, startAt: Int, limit: Int) async throws -> JiraPage<JiraIssue>
func backlogIssues(boardID: Int, jql: String?, startAt: Int, limit: Int) async throws -> JiraPage<JiraIssue>
func moveToSprint(_ sprintID: Int, keys: [String]) async throws
func moveToBacklog(keys: [String]) async throws
func rank(_ keys: [String], _ position: JiraRankPosition, rankFieldID: Int?) async throws
```
## Phase 4 — relations, people, time, files
```swift
func linkTypes() async throws -> [JiraLinkType]
func link(_ typeName: String, inward: String, outward: String) async throws
func deleteLink(id: String) async throws
func setParent(key: String, parentKey: String?) async throws                 // epic / parent / subtask parent
func watchers(key: String) async throws -> [JiraUser]
func addWatcher(key: String, accountID: String) async throws
func removeWatcher(key: String, accountID: String) async throws
func votes(key: String) async throws -> JiraVotes
func vote(key: String) async throws;  func unvote(key: String) async throws
func worklogs(key: String) async throws -> [JiraWorklog]
func addWorklog(key: String, seconds: Int, started: Date?, comment: String?) async throws -> JiraWorklog
func deleteWorklog(key: String, id: String) async throws
func attachments(key: String) async throws -> [JiraAttachment]
func uploadAttachment(key: String, filename: String, data: Data, mimeType: String) async throws -> [JiraAttachment]
func downloadAttachment(_ attachment: JiraAttachment) async throws -> Data
func deleteAttachment(id: String) async throws
```
## Phase 5 — transport
* 429 → waits `Retry-After` (capped) and retries up to 3 times before surfacing `JiraError.rateLimited`.
* `search` keeps its signature; `searchPage(jql:limit:pageToken:)` returns `JiraPage<JiraIssue>` (nextPageToken).

## JiraViewModel (`@Observable @MainActor`)
Writes are optimistic on the board copy and roll back on failure (message via
`actionMessage`/`actionFailed`, same as `move`/`assign`). Return `true` on success.
```swift
func edit(_ issue: JiraIssue, _ updates: [JiraFieldUpdate]) async -> Bool      // + setSummary/setPriority/setLabels/setDueDate/setDescription/setStoryPoints sugar
func create(_ draft: JiraNewIssue) async -> String?                           // new key; invalidates board
func comments(for key: String) async throws -> [JiraComment]; addComment/editComment/deleteComment(key:...) async -> Bool   // cached in `commentsByIssue[key]`, optimistic
func loadBoards() async;  private(set) var boards, selectedBoard, boardConfiguration, sprints
func moveToSprint(_ issue:, _ sprint:) async -> Bool;  moveToBacklog(_ issue:) async -> Bool
func rank(_ issue: JiraIssue, _ position: JiraRankPosition) async -> Bool     // reorders the column optimistically
func link/unlink, setParent, watch/unwatch, vote/unvote, logWork, attach/download/deleteAttachment — same pattern
func assignableUsers(query:, projectKey:) async throws -> [JiraUser]
```

## As shipped — differences from the plan above
* `JiraClient.rank(issueKey:before:after:rankFieldID:)` exists next to `rank(_:_:rankFieldID:)`.
* `searchAssignableUsers(query:issueKey:)` (existing issue) next to `(query:projectKey:)`.
* `labels(query:)`; `JiraViewModel.labels(matching:)`.
* `boardIssues/sprintIssues/backlogIssues` take `storyPointsField:` (from `storyPointsFieldID()`) to fill `JiraIssue.storyPoints`.
* `search(jql:limit:)` now follows `nextPageToken` up to `limit`; `searchPage(jql:limit:pageToken:)` is one page.
* `JiraIssue` is also `summary`/`priority` mutable, gains `subtasks`, `links`.
* View model shipped names (all `async -> Bool` unless noted, optimistic with rollback where the board shows the field):
  `create(_:) -> String?`, `edit(_:_:patch:)`, `setSummary/Description/Priority/Labels/Components/DueDate/StoryPoints`,
  `loadComments(for:)`, `addComment(to:text:)`, `editComment(on:id:text:)`, `deleteComment(on:id:)` (state: `commentsByIssue`),
  `loadBoards(projectKey:)`, `selectBoard(_:)` (state: `boards`, `selectedBoard`, `boardConfiguration`, `sprints`),
  `moveToSprint(_:_:)`, `moveToBacklog(_:)`, `rank(_:_:)`,
  `link(_:_:direction:to:)`, `unlink(_:_:)`, `setParent(_:_:)`,
  `setVote(_:on:)`, `setWatching(_:on:)`, `setWatcher(_:watching:on:)` (state: `votesByIssue`, `watchersByIssue`),
  `logWork(on:seconds:started:comment:)`, `deleteWorklog(on:id:)` (`worklogsByIssue`),
  `attach(to:filename:data:mimeType:)`, `download(_:)`, `deleteAttachment(on:id:)` (`attachmentsByIssue`),
  loaders `loadVotes/loadWatchers/loadWorklogs/loadAttachments(for:)`.
* Tests inject `JiraViewModel.clientFactory` and `JiraClient(credentials:session:)` (see `GitHallsTests/JiraMock.swift`).
* 429: retried twice when `Retry-After` <= 30s (`maxRetries`, `maxRetryWait`); otherwise `JiraError.rateLimited`.
* Descriptions/comments go through `JiraADF.document(from:)` = `JiraMarkdownADF` (nested plain-text lists fall back to a plain builder).
