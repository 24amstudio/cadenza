import Foundation

@MainActor
extension HostStore {
    var creeEnabled: Bool {
        get throws {
            try database.query("SELECT cree_enabled FROM host_state").first?["cree_enabled"]?.integer == 1
        }
    }

    func setCREEEnabled(_ enabled: Bool) throws {
        try database.run("UPDATE host_state SET cree_enabled=?", [.integer(enabled ? 1 : 0)])
    }

    var recommendationMode: String {
        get throws {
            try database.query(
                "SELECT recommendation_mode FROM host_state"
            ).first?["recommendation_mode"]?.string ?? "auto"
        }
    }

    func setRecommendationMode(_ mode: String) throws {
        guard ["auto", "shadow", "planning", "paused"].contains(mode) else {
            throw CadenzaError.failure("invalid_command", "Unknown recommendation mode.")
        }
        try database.run("UPDATE host_state SET recommendation_mode=?", [.text(mode)])
        let phase =
            mode == "planning" ? "planning" : (mode == "shadow" || mode == "paused" ? "fallback" : "learning")
        let phaseReason =
            mode == "planning" ? "Planning was enabled by the Host operator." : "Waiting for Auto readiness gates."
        try database.run(
            "UPDATE host_state SET recommendation_phase=?, recommendation_phase_reason=?",
            [
                .text(phase),
                .text(phaseReason),
            ])
    }

    var recommendationPhase: String {
        get throws {
            try database.query(
                "SELECT recommendation_phase FROM host_state"
            ).first?["recommendation_phase"]?.string ?? "learning"
        }
    }

    var recommendationPhaseReason: String {
        get throws {
            try database.query(
                "SELECT recommendation_phase_reason FROM host_state"
            ).first?["recommendation_phase_reason"]?.string
                ?? "Waiting for a valid profile."
        }
    }

    func setRecommendationPhase(_ phase: String, reason: String) throws {
        guard ["learning", "ready", "planning", "fallback"].contains(phase), reason.count <= 240 else {
            throw CadenzaError.failure("invalid_command", "Invalid recommendation readiness state.")
        }
        try database.run(
            "UPDATE host_state SET recommendation_phase=?, recommendation_phase_reason=?",
            [.text(phase), .text(reason)])
    }

    func recommendationProfile(remoteId: String) throws -> RecommendationProfile? {
        guard let row = try database.query(
            "SELECT profile_json FROM recommendation_profiles WHERE remote_id=?",
            [.text(remoteId)]
        ).first,
            let json = row["profile_json"]?.string,
            let data = json.data(using: .utf8)
        else { return nil }
        return try Wire.decode(RecommendationProfileEnvelope.self, from: data).profile
    }

    func recommendationPublicKey(remoteId: String) throws -> String? {
        try database.query(
            "SELECT public_key_base64 FROM recommendation_keys WHERE remote_id=?", [.text(remoteId)]
        ).first?["public_key_base64"]?.string
    }

    func saveRecommendationPublicKey(remoteId: String, key: String) throws {
        guard key.count <= 1024 else {
            throw CadenzaError.failure("invalid_command", "The recommendation signing key is too large.")
        }
        try database.run(
            "INSERT INTO recommendation_keys(remote_id,public_key_base64,created_at_ms) VALUES(?,?,?)",
            [.text(remoteId), .text(key), .integer(wallMs())])
    }

    func saveRecommendationProfile(_ profile: RecommendationProfile) throws {
        let envelope = RecommendationProfileEnvelope(profile: profile)
        let data = try Wire.encode(envelope)
        guard data.count <= CREEConstants.maximumPayloadBytes else {
            throw CadenzaError.failure("invalid_command", "The derived recommendation profile is too large.")
        }
        try database.transaction {
            try database.run(
                """
                INSERT INTO recommendation_profiles(remote_id,passport_sequence,expires_at_ms,model_version,profile_json,updated_at_ms)
                VALUES(?,?,?,?,?,?)
                ON CONFLICT(remote_id) DO UPDATE SET passport_sequence=excluded.passport_sequence,
                  expires_at_ms=excluded.expires_at_ms,model_version=excluded.model_version,
                  profile_json=excluded.profile_json,updated_at_ms=excluded.updated_at_ms
                """,
                [
                    .text(profile.remoteId), .integer(profile.passportSequence), .integer(profile.expiresAtMs),
                    .integer(Int64(CREEConstants.modelVersion)), .text(String(decoding: data, as: UTF8.self)),
                    .integer(wallMs()),
                ])
            try database.run("DELETE FROM recommendation_transitions WHERE remote_id=?", [.text(profile.remoteId)])
            for transition in profile.transitions.prefix(CREEConstants.maximumTransitions) {
                try database.run(
                    """
                    INSERT INTO recommendation_transitions(remote_id,source_key,target_key,weight,confidence,source,freshness_ms)
                    VALUES(?,?,?,?,?,?,?)
                    """,
                    [
                        .text(profile.remoteId), .text(transition.from.key), .text(transition.to.key),
                        .text(String(transition.weight)), .text(String(transition.confidence)),
                        .text(transition.source),
                        .integer(transition.freshnessMs),
                    ])
            }
        }
    }

    func saveRecommendationFeedback(
        remoteId: String, feedback: RecommendationFeedback, replacement: RecommendationTrack? = nil
    ) throws {
        let data = try replacement.map { try Wire.encode($0) }
        try database.run(
            """
            INSERT INTO recommendation_feedback(remote_id,recommendation_id,outcome,position_ms,duration_ms,replacement_json,occurred_at_ms)
            VALUES(?,?,?,?,?,?,?)
            """,
            [
                .text(remoteId), .text(feedback.recommendationId), .text(feedback.outcome.rawValue),
                feedback.positionMs.map(SQLValue.integer) ?? .null, feedback.durationMs.map(SQLValue.integer) ?? .null,
                data.map { .text(String(decoding: $0, as: UTF8.self)) } ?? .null,
                .integer(feedback.occurredAtMs),
            ])
    }

    func saveRecommendationPlan(
        remoteId: String, result: RecommendationResult, expectedRevision: Int64, phase: String = "prepared",
        operation: String
    ) throws {
        guard ["prepared", "dispatched", "confirmed", "rejected", "unconfirmed", "expired"].contains(phase) else {
            throw CadenzaError.failure("invalid_state", "Unknown recommendation plan phase.")
        }
        try database.run(
            """
            INSERT INTO recommendation_plans(remote_id,plan_id,recommendation_id,passport_sequence,model_version,expected_revision,operation_json,phase,created_at_ms)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(remote_id,plan_id) DO UPDATE SET phase=excluded.phase,operation_json=excluded.operation_json
            """,
            [
                .text(remoteId), .text(result.planId), .text(result.recommendationId),
                .integer(result.passportSequence),
                .integer(Int64(result.modelVersion)), .integer(expectedRevision), .text(operation), .text(phase),
                .integer(wallMs()),
            ])
    }

    func recommendationPlan(remoteId: String, planId: String) throws -> SQLRow? {
        try database.query(
            "SELECT * FROM recommendation_plans WHERE remote_id=? AND plan_id=?",
            [.text(remoteId), .text(planId)]
        ).first
    }

    func finishRecommendationPlan(remoteId: String, planId: String, outcome: String, receipt: Frame) throws {
        guard ["confirmed", "rejected", "unconfirmed", "expired"].contains(outcome) else {
            throw CadenzaError.failure("invalid_state", "Unknown recommendation receipt phase.")
        }
        let data = try Wire.encode(receipt)
        try database.run(
            "UPDATE recommendation_plans SET phase=?,receipt_json=? WHERE remote_id=? AND plan_id=?",
            [.text(outcome), .text(String(decoding: data, as: UTF8.self)), .text(remoteId), .text(planId)])
    }

    func saveShadowObservation(
        remoteId: String, apple: RecommendationTrack?, cree: RecommendationTrack?, selected: RecommendationTrack?,
        confidence: Double, outcome: String?
    ) throws {
        guard confidence.isFinite, (0...1).contains(confidence), outcome == nil || outcome!.count <= 80 else {
            throw CadenzaError.failure("invalid_command", "Invalid recommendation shadow observation.")
        }
        try database.run(
            """
            INSERT INTO recommendation_shadow_observations(
              remote_id,observation_id,apple_key,cree_key,selected_key,provenance_confidence,outcome,observed_at_ms
            ) VALUES(?,?,?,?,?,?,?,?)
            """,
            [
                .text(remoteId), .text(identifier()), apple.map { .text($0.key) } ?? .null,
                cree.map { .text($0.key) } ?? .null, selected.map { .text($0.key) } ?? .null,
                .text(String(confidence)), outcome.map(SQLValue.text) ?? .null, .integer(wallMs()),
            ])
    }
}

private struct RecommendationProfileEnvelope: Codable, Sendable {
    var profile: RecommendationProfile
}

extension RecommendationTrack {
    var key: String { source + ":" + id }
}
