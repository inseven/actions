//
//  GitHub.swift
//  Status
//
//  Created by Jason Barrie Morley on 31/03/2022.
//

import Foundation

enum GitHubError: Error {
    case invalidUrl
    case unauthorized
}

class GitHub {

    // TODO: Order alphabetically

    struct Authentication {
        let accessToken: String
    }

    private struct AccessToken: Codable {

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case scope = "scope"
            case tokenType = "token_type"
        }

        let accessToken: String
        let scope: String
        let tokenType: String
    }

    struct Workflow: Codable, Identifiable, Equatable {

        static func == (lhs: Workflow, rhs: Workflow) -> Bool {
            return lhs.id == rhs.id
        }

        let id: Int
        let node_id: String
        let name: String
        let path: String
        let state: String
    }

    struct Workflows: Codable {

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case workflows = "workflows"
        }

        let totalCount: Int
        let workflows: [Workflow]
    }

    struct Repositories: Codable {

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case incompleteResults = "incomplete_results"
            case items = "items"
        }

        let totalCount: Int
        let incompleteResults: Bool
        let items: [Repository]
    }

    struct Repository: Codable, Identifiable, Equatable {

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case nodeId = "node_id"
            case name = "name"
            case fullName = "full_name"
            case owner = "owner"
            case url = "url"
        }

        static func == (lhs: Repository, rhs: Repository) -> Bool {
            return lhs.id == rhs.id
        }

        let id: Int
        let nodeId: String
        let name: String
        let fullName: String
        let owner: User
        let url: URL
    }

    struct WorkflowRuns: Codable {

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case workflowRuns = "workflow_runs"
        }

        let totalCount: Int
        let workflowRuns: [WorkflowRun]
    }

    struct Branch: Codable, Identifiable {

        enum CodingKeys: String, CodingKey {
            case name = "name"
        }

        var id: String { return name }

        let name: String

    }

    struct WorkflowRun: Codable, Identifiable {

        enum Conclusion: String, Codable {
            case success
            case failure
        }

        enum Status: String, Codable {
            case inProgress = "in_progress"
            case completed = "completed"
        }

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case name = "name"
            case nodeId = "node_id"
            case checkSuiteId = "check_suite_id"
            case checkSuiteNodeId = "check_suite_node_id"
            case headBranch = "head_branch"
            case headSha = "head_sha"
            case runNumber = "run_number"
            case event = "event"
            case status = "status"
            case conclusion = "conclusion"
            case workflowId = "workflow_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        let id: Int
        let name: String
        let nodeId: String
        let checkSuiteId: Int
        let checkSuiteNodeId: String
        let headBranch: String
        let headSha: String
        let runNumber: Int
        let event: String
        let status: Status
        let conclusion: Conclusion?
        let workflowId: Int

        let createdAt: Date
        let updatedAt: Date
    }

    struct Organization: Codable, Identifiable {

        let login: String
        let id: Int
    }



    struct User: Codable {

        let login: String
        let id: Int
        let node_id: String
        let avatar_url: URL
    }

    // TODO: Paged fetch

    enum Path: String {
        case authorize = "/login/oauth/authorize"
        case accessToken = "/login/oauth/access_token"
    }

    let clientId: String
    let clientSecret: String
    let redirectUri: String

    let syncQueue = DispatchQueue(label: "GitHub.syncQueue")
    var _authentication: Authentication?  // Synchronized on syncQueue

    // TODO: Make this a method
    var authorizationUrl: URL {
        url(.authorize, parameters: [
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "scope": "workflow repo",
        ])!
    }

    init(clientId: String, clientSecret: String, redirectUri: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectUri = redirectUri
    }

    private func fetch<T: Decodable>(_ url: URL, authentication: Authentication) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("token \(authentication.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func fetch<T: Decodable>(_ url: URL,
                                     authentication: Authentication,
                                     page: Int,
                                     perPage: Int = 30) async throws -> T {
        guard let url = url.settingQueryItems([
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
        ]) else {
            throw GitHubError.invalidUrl
        }
        let response: T = try await fetch(url, authentication: authentication)
        return response
    }

    func workflowRuns(for repositoryName: String, authentication: Authentication) async throws -> [WorkflowRun] {
        // TODO: Assemble the path?
        let url = URL(string: "https://api.github.com/repos/\(repositoryName)/actions/runs")!
        let response: WorkflowRuns = try await fetch(url, authentication: authentication)
        return response.workflowRuns
    }

    // TODO: Paged fetch
    func repositories(authentication: Authentication) async throws -> [Repository] {
        var repositories: [Repository] = []
        for page in 1... {
            let url = URL(string: "https://api.github.com/user/repos")!
            let response: [Repository] = try await fetch(url, authentication: authentication, page: page, perPage: 100)
            repositories += response
            if response.isEmpty {
                break
            }
        }
        return repositories
    }

    // TODO: Owner and repo as parameters.
    func branches(for repository: Repository, authentication: Authentication) async throws -> [Branch] {
        let url = URL(string: "https://api.github.com/repos/\(repository.fullName)/branches")!
        let response: [Branch] = try await fetch(url, authentication: authentication)
        return response
    }

    // TODO: Use repositoryname
    func workflows(for repository: Repository, authentication: Authentication) async throws -> [Workflow] {
        let url = URL(string: "https://api.github.com/repos/\(repository.fullName)/actions/workflows")!
        let response: Workflows = try await fetch(url, authentication: authentication)
        return response.workflows
    }

    func organizations(authentication: Authentication) async throws -> [Organization] {
        let url = URL(string: "https://api.github.com/users/jbmorley/orgs")!
        let response: [Organization] = try await fetch(url, authentication: authentication)
        return response
    }

    // TODO: This could throw? Might be nicer?
    func authenticate(with code: String) async -> Result<Authentication, Error> {
        do {
            guard let url = url(.accessToken, parameters: [
                "client_id": clientId,
                "client_secret": clientSecret,
                "code": code
            ]) else {
                throw GitHubError.invalidUrl
            }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let accessToken = try decoder.decode(AccessToken.self, from: data)
            syncQueue.async {
                self._authentication = Authentication(accessToken: accessToken.accessToken)
            }
            return .success(Authentication(accessToken: accessToken.accessToken))
        } catch {
            return .failure(error)
        }
    }

    private func url(_ path: Path, parameters: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = path.rawValue
        components.queryItems = parameters.map { URLQueryItem(name: $0, value: $1) }
        return components.url
    }

}
