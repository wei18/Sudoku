// ASCClient achievements operations — split from ASCClient.swift to keep
// the main actor body within swiftlint type_body_length budget. Same actor,
// same isolation; this is purely a file split.

import Foundation

extension ASCClient {
    internal func listAchievements(detailId: String) async throws -> [APIResource] {
        try await getCollection(path: "/v1/gameCenterDetails/\(detailId)/gameCenterAchievements")
    }

    internal func createAchievement(
        detailId: String,
        config: AchievementConfig
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterAchievements",
                "attributes": [
                    "referenceName": config.shortId,
                    "vendorIdentifier": config.fullId,
                    "points": config.points,
                    "showBeforeEarned": !config.isHidden,
                    "repeatable": false
                ],
                "relationships": [
                    "gameCenterDetail": [
                        "data": ["type": "gameCenterDetails", "id": detailId]
                    ]
                ]
            ]
        ]
        return try await mutate(method: "POST", path: "/v1/gameCenterAchievements", body: body)
    }

    internal func updateAchievement(
        achievementId: String,
        config: AchievementConfig
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterAchievements",
                "id": achievementId,
                "attributes": [
                    "points": config.points,
                    "showBeforeEarned": !config.isHidden
                ]
            ]
        ]
        return try await mutate(method: "PATCH", path: "/v1/gameCenterAchievements/\(achievementId)", body: body)
    }

    internal func listAchievementLocalizations(achievementId: String) async throws -> [APIResource] {
        try await getCollection(path: "/v1/gameCenterAchievements/\(achievementId)/localizations")
    }

    internal func createAchievementLocalization(
        achievementId: String,
        locale: String,
        title: String,
        description: String,
        unearnedDescription: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterAchievementLocalizations",
                "attributes": [
                    "locale": locale,
                    "name": title,
                    "afterEarnedDescription": description,
                    "beforeEarnedDescription": unearnedDescription
                ],
                "relationships": [
                    "gameCenterAchievement": [
                        "data": ["type": "gameCenterAchievements", "id": achievementId]
                    ]
                ]
            ]
        ]
        return try await mutate(method: "POST", path: "/v1/gameCenterAchievementLocalizations", body: body)
    }

    internal func updateAchievementLocalization(
        localizationId: String,
        title: String,
        description: String,
        unearnedDescription: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterAchievementLocalizations",
                "id": localizationId,
                "attributes": [
                    "name": title,
                    "afterEarnedDescription": description,
                    "beforeEarnedDescription": unearnedDescription
                ]
            ]
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/gameCenterAchievementLocalizations/\(localizationId)",
            body: body
        )
    }
}
