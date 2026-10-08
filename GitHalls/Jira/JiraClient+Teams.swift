//
//  JiraClient+Teams.swift
//  GitHalls
//

import Foundation

extension JiraClient {
    /// Teams matching `query`, for the Team field.
    ///
    /// Jira publishes where to search in the field's own createmeta entry
    /// (`JiraCreateField.autoCompleteURL`), so pass that; the fallback path is
    /// the one Jira's own Team picker has used and is not part of the public
    /// REST reference. The URL must be on the Jira site: it is sent credentials.
    func teams(query: String, autoCompleteURL: String? = nil) async throws -> [JiraFieldOption] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let request: URLRequest

        if let autoCompleteURL {
            guard let url = Self.suggestionURL(autoCompleteURL, query: text),
                  url.host?.lowercased() == credentials.site.host?.lowercased()
            else { throw JiraError.malformedResponse }

            var plain = URLRequest(url: url)
            plain.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
            plain.setValue("application/json", forHTTPHeaderField: "Accept")
            plain.timeoutInterval = 20
            request = plain
        } else {
            request = self.request(path: Self.path("/rest/teams/1.0/teams/find", query: ["query": text]))
        }

        return Self.options(from: try await send(request))
    }

    /// The autocomplete URL with the query filled in: many end in `query=`.
    static func suggestionURL(_ template: String, query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        if template.hasSuffix("=") { return URL(string: template + encoded) }
        let joiner = template.contains("?") ? "&" : "?"
        return URL(string: template + joiner + "query=" + encoded)
    }

    /// Picker answers come as an array or wrapped in one of a few keys, with an
    /// id that is a string or a number and a name under `name`, `title`…
    static func options(from json: Any) -> [JiraFieldOption] {
        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let object = json as? [String: Any],
                  let wrapped = ["teams", "results", "values", "suggestions", "items"]
                      .lazy.compactMap({ object[$0] as? [[String: Any]] }).first {
            list = wrapped
        } else {
            return []
        }

        return list.compactMap { raw in
            let id = (raw["id"] as? String) ?? (raw["id"] as? Int).map(String.init) ?? (raw["teamId"] as? String)
            let label = ["name", "title", "displayName", "label", "value"].lazy.compactMap { raw[$0] as? String }.first
            guard let id, let label else { return nil }
            return JiraFieldOption(id: id, label: label)
        }
    }
}
