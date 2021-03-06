import Authentication
import Manifest
import Vapor

final class PackageController: RouteCollection {
    func boot(router: Router) throws {
        let packages = router.grouped("packages")
        
        packages.get("search", use: search)
        packages.get(String.parameter, String.parameter, use: get)
        packages.get(String.parameter, String.parameter, "readme", use: readme)
        packages.get(String.parameter, String.parameter, "manifest", use: manifest)
        packages.get(String.parameter, String.parameter, "releases", use: releases)
    }
    
    func get(_ request: Request)throws -> Future<Response> {
        let owner = try request.parameters.next(String.self)
        let repo = try request.parameters.next(String.self)
        let client = try request.make(Client.self)
        
        let manifest = client.get("https://raw.githubusercontent.com/\(owner)/\(repo)/master/Package.swift")
        return manifest.flatMap(to: Response.self) { response in
            let status = response.http.status
            guard status.code / 100 == 2 else {
                if status.code == 404 { throw Abort(.notFound, reason: "No package found with name '\(owner)/\(repo)'") }
                throw Abort(HTTPStatus.custom(code: status.code, reasonPhrase: status.reasonPhrase))
            }
            return client.get("https://api.github.com/repos/\(owner)/\(repo)")
        }.map(to: Response.self) { response in
            guard let data = response.http.body.data else {
                throw Abort(.notFound, reason: "No package found with name '\(owner)/\(repo)'")
            }
            let response = request.makeResponse()
            response.http.body = HTTPBody(data: data)
            response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
            return response
        }
    }
    
    func search(_ request: Request)throws -> Future<SearchResult> {
        guard let token = request.http.headers.bearerAuthorization else {
            throw Abort(
                .unauthorized,
                reason: "GitHub requires an access token with the proper scopes to use the GraphQL API: https://developer.github.com/v4/guides/forming-calls/#authenticating-with-graphql. Add the token to the 'Authorization' header as a bearer token"
            )
        }
        
        let name = try request.query.get(String.self, at: "name")
        let limit = try request.query.get(Int?.self, at: "limit") ?? 100
        var searchOptions: [String: String] = [:]
        
        if let topic = try request.query.get(String?.self, at: "topic") { searchOptions["topic"] = topic }
        
        guard limit <= 100 else {
            throw Abort(.badRequest, reason: "Query limit exceeded 100 elements. Please pass in a value less than or equal to 100")
        }
        
        return try GitHub.repos(on: request, with: name, limit: limit, accessToken: token.token, searchOptions: searchOptions).map { search in
            return SearchResult(repositories: search.repos, metadata: search.meta)
        }.catch { error in
            print(error)
        }
    }
    
    func readme(_ request: Request)throws -> Future<Response> {
        guard let token = request.http.headers.bearerAuthorization else {
            throw Abort(
                .unauthorized,
                reason: "GitHub requires an access token with the proper scopes to use the GraphQL API: https://developer.github.com/v4/guides/forming-calls/#authenticating-with-graphql. Add the token to the 'Authorization' header as a bearer token"
            )
        }
        
        let owner = try request.parameters.next(String.self)
        let repo = try request.parameters.next(String.self)
        let query = READMEQuery(owner: owner, repo: repo, token: token.token)
        return try GitHub.send(query: query, on: request).map(to: Response.self) { readme in
            let response = request.makeResponse()
            response.http.body = HTTPBody(data: Data(readme.text.utf8))
            response.http.headers.replaceOrAdd(name: .contentType, value: "text/markdown; charset=UTF-8")
            return response
        }
    }
    
    func manifest(_ request: Request)throws -> Future<Manifest> {
        guard let token = request.http.headers.bearerAuthorization else {
            throw Abort(
                .unauthorized,
                reason: "GitHub requires an access token with the proper scopes to use the GraphQL API: https://developer.github.com/v4/guides/forming-calls/#authenticating-with-graphql. Add the token to the 'Authorization' header as a bearer token"
            )
        }
        
        let owner = try request.parameters.next(String.self)
        let repo = try request.parameters.next(String.self)
        let query = ManifestQuery(owner: owner, repo: repo, token: token.token)
        return try GitHub.send(query: query, on: request).map(to: Manifest.self) { $0.manifest }
    }
    
    func releases(_ request: Request)throws -> Future<Response> {
        guard let token = request.http.headers.bearerAuthorization else {
            throw Abort(
                .unauthorized,
                reason: "GitHub requires an access token with the proper scopes to use the GraphQL API: https://developer.github.com/v4/guides/forming-calls/#authenticating-with-graphql. Add the token to the 'Authorization' header as a bearer token"
            )
        }
        
        let owner = try request.parameters.next(String.self)
        let repo = try request.parameters.next(String.self)
        let query = ReleasesQuery(owner: owner, repo: repo, token: token.token)
        return try GitHub.send(query: query, on: request).map(to: Response.self) { queryResult in
            let response = request.makeResponse()
            try response.content.encode(queryResult.releases, as: .json)
            response.http.headers.replaceOrAdd(name: .contentType, value: "application/json")
            return response
        }
    }
}

extension Manifest: Content {}

struct SearchResult: Content {
    let repositories: [Repository]
    let metadata: GitHub.MetaInfo
}
