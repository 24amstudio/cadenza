import Foundation

extension HostService {
    func startRecommendationQuery(_ frame: Frame, actor: String, peer: NetworkService.Peer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await receiveRecommendationQuery(frame, actor: actor, peer: peer) } catch {
                fail(error, request: frame, peer: peer)
            }
        }
    }

    func startRecommendationPlan(_ frame: Frame, actor: String, peer: NetworkService.Peer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await receiveRecommendationPlan(frame, actor: actor, peer: peer) } catch {
                fail(error, request: frame, peer: peer)
            }
        }
    }

    func receiveRecommendationPassport(
        _ frame: Frame, actor: String, peer: NetworkService.Peer
    ) throws {
        guard let signed = frame.recommendationPassport else {
            throw CadenzaError.failure("invalid_command", "A recommendation passport is required.")
        }
        if let existingKey = try store.recommendationPublicKey(remoteId: actor) {
            guard existingKey == signed.publicKeyBase64 else {
                throw CadenzaError.failure(
                    "forbidden", "The recommendation signing key changed; reset this Remote's learning data."
                )
            }
        }
        let previous = try store.database.query(
            "SELECT passport_sequence FROM recommendation_profiles WHERE remote_id=?", [.text(actor)]
        ).first?["passport_sequence"]?.integer ?? 0
        let passport = try recommendationVerifier.verify(signed, remoteId: actor, previousSequence: previous)
        let profile = try recommendationVerifier.materialize(passport, remoteId: actor)
        if try store.recommendationPublicKey(remoteId: actor) == nil {
            try store.saveRecommendationPublicKey(remoteId: actor, key: signed.publicKeyBase64)
        }
        try store.saveRecommendationProfile(profile)
        network.send(
            Frame(type: "recommendation.passport.accepted", sequence: passport.sequence), to: peer)
    }

    func receiveRecommendationQuery(
        _ frame: Frame, actor: String, peer: NetworkService.Peer
    ) async throws {
        guard let query = frame.recommendationQuery,
            let profile = try store.recommendationProfile(remoteId: actor)
        else {
            network.send(
                Frame(
                    type: "recommendation.result",
                    recommendationResult: nil,
                    errorCode: "profile_unavailable"
                ),
                to: peer)
            return
        }
        guard profile.expiresAtMs > wallMs() else {
            network.send(
                Frame(
                    type: "recommendation.result",
                    recommendationResult: nil,
                    errorCode: "profile_expired"
                ),
                to: peer)
            return
        }
        let mode = try store.recommendationMode
        guard try store.creeEnabled, mode != "disabled", mode != "paused" else {
            network.send(Frame(type: "recommendation.result", errorCode: "planning_paused"), to: peer)
            return
        }
        let effectiveMode: String
        if mode == "auto" {
            let ready = profile.recent.count >= 3 && profile.transitions.count >= 3
            if ready {
                try store.setRecommendationPhase(
                    "ready", reason: "Profile, transition history, and native queue policy are ready."
                )
                effectiveMode = "planning"
            } else {
                try store.setRecommendationPhase(
                    "learning",
                    reason: "Auto is observing until three qualified recent tracks and transitions are available."
                )
                effectiveMode = "shadow"
            }
        } else {
            effectiveMode = mode
            try store.setRecommendationPhase(
                mode == "planning" ? "planning" : "fallback",
                reason: mode == "planning"
                    ? "Planning is enabled by the Host operator."
                    : "Shadow mode observes without queue mutation."
            )
        }
        let snapshot = try queue.snapshot()
        let context = RecommendationContext(
            current: snapshot.current.map {
                RecommendationTrack(
                    source: $0.song.source,
                    id: $0.song.id,
                    artistId: $0.song.artist,
                    albumId: $0.song.album,
                    versionId: nil
                )
            },
            recent: profile.recent,
            queue: snapshot.queue.map {
                RecommendationTrack(
                    source: $0.song.source,
                    id: $0.song.id,
                    artistId: $0.song.artist,
                    albumId: $0.song.album,
                    versionId: nil
                )
            },
            intent: query.intent,
            queuePhase: snapshot.queue.isEmpty ? "empty" : "active",
            explicitAllowed: query.filters.explicitAllowed,
            locked: query.filters.locked,
            queueRevision: snapshot.revision,
            modelVersion: query.modelVersion
        )
        let queueCandidates = snapshot.queue.prefix(CREEConstants.maximumCandidates).map { entry in
            RecommendationCandidate(
                track: RecommendationTrack(
                    source: entry.song.source,
                    id: entry.song.id,
                    artistId: entry.song.artist,
                    albumId: entry.song.album,
                    versionId: nil
                ),
                song: entry.song,
                source: "cadenza",
                confidence: 0.65,
                evidence: ["already in the Host queue"],
                applePrior: nil,
                metadataCompleteness: entry.song.album.isEmpty ? 0.7 : 1,
                availability: true
            )
        }
        let recentCandidates = recommendationRetriever.retrieve(
            profile: profile, context: context, knownSongs: queue.knownSongs)
        let ranked = recommendationRanker.rank(
            candidates: queueCandidates + recentCandidates, profile: profile, context: context)
        let (_, chosen) = recommendationPlanner.choose(ranked: ranked, context: context, profile: profile)
        var result = chosen
        result?.mode = effectiveMode
        if let result {
            let operation: CommandAction?
            if let candidate = result.candidate {
                let identity = SongIdentity(source: candidate.source, id: candidate.id)
                if let song = queue.knownSongs[identity] {
                    queue.remember([song])
                    operation = CommandAction(kind: "queue.play_next", song: identity)
                } else {
                    operation = nil
                }
            } else {
                operation = nil
            }
            if let operation, effectiveMode == "planning" {
                let command = Frame(
                    type: "command", commandId: identifier(), hostEpoch: store.epoch,
                    expiresAtHostMs: monotonicMs() + 1_000, expectedRevision: snapshot.revision,
                    action: operation)
                try store.saveRecommendationPlan(
                    remoteId: actor, result: result, expectedRevision: snapshot.revision,
                    operation: String(decoding: try Wire.encode(operation), as: UTF8.self))
                let applied = try await queue.execute(command, actor: actor)
                let phase = applied.outcome == "applied" ? "confirmed" : (applied.outcome ?? "unconfirmed")
                try store.finishRecommendationPlan(
                    remoteId: actor, planId: result.planId, outcome: phase, receipt: applied)
                network.send(
                    Frame(
                        type: "recommendation.plan.result",
                        plan: RecommendationPlanEnvelope(
                            planId: result.planId,
                            recommendationId: result.recommendationId,
                            passportSequence: result.passportSequence,
                            modelVersion: result.modelVersion,
                            expectedRevision: snapshot.revision,
                            operation: operation
                        ),
                        outcome: applied.outcome
                    ),
                    to: peer)
            }
        }
        network.send(Frame(type: "recommendation.result", recommendationResult: result), to: peer)
        _ = await Task.yield()
    }

    func receiveRecommendationFeedback(_ frame: Frame, actor: String) throws {
        guard let feedback = frame.recommendationFeedback else {
            throw CadenzaError.failure("invalid_command", "Recommendation feedback is required.")
        }
        try store.saveRecommendationFeedback(remoteId: actor, feedback: feedback, replacement: feedback.replacement)
        if let profile = try store.recommendationProfile(remoteId: actor) {
            let plan = try store.database.query(
                "SELECT operation_json FROM recommendation_plans WHERE remote_id=? AND recommendation_id=?",
                [.text(actor), .text(feedback.recommendationId)]
            ).first
            let operationTrack: RecommendationTrack? = plan?["operation_json"]?.string
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? Wire.decode(CommandAction.self, from: $0) }
                .flatMap { $0.song }
                .map { RecommendationTrack(source: $0.source, id: $0.id) }
            guard let track = feedback.track ?? operationTrack else { return }
            let updated = recommendationFeedbackModel.update(profile: profile, feedback: feedback, track: track)
            try store.saveRecommendationProfile(updated)
        }
    }

    func receiveRecommendationShadowObservation(_ frame: Frame, actor: String) throws {
        guard let observation = frame.recommendationShadowObservation else {
            throw CadenzaError.failure("invalid_command", "A recommendation shadow observation is required.")
        }
        try store.saveShadowObservation(
            remoteId: actor, apple: observation.apple, cree: observation.cree, selected: observation.selected,
            confidence: observation.provenanceConfidence, outcome: observation.outcome)
    }

    func receiveRecommendationPlan(
        _ frame: Frame, actor: String, peer: NetworkService.Peer
    ) async throws {
        guard let envelope = frame.recommendationPlan,
            envelope.passportSequence == (try store.recommendationProfile(remoteId: actor))?.passportSequence,
            envelope.expectedRevision == (try store.revision)
        else {
            throw CadenzaError.failure("stale_revision", "The queue or recommendation profile changed.")
        }
        if let existing = try store.recommendationPlan(remoteId: actor, planId: envelope.planId),
            let phase = existing["phase"]?.string,
            phase == "confirmed" || phase == "rejected" || phase == "unconfirmed",
            let receipt = existing["receipt_json"]?.string,
            let data = receipt.data(using: .utf8), let saved = try? Wire.decode(Frame.self, from: data)
        {
            network.send(Frame(type: "recommendation.plan.result", plan: envelope, outcome: saved.outcome), to: peer)
            return
        }
        guard let saved = try store.recommendationPlan(remoteId: actor, planId: envelope.planId),
            saved["recommendation_id"]?.string == envelope.recommendationId,
            saved["phase"]?.string == "prepared"
        else { throw CadenzaError.failure("invalid_state", "The recommendation plan is unknown or already resolved.") }
        let command = Frame(
            type: "command", commandId: identifier(), hostEpoch: store.epoch,
            expiresAtHostMs: monotonicMs() + 1_000, expectedRevision: envelope.expectedRevision,
            action: envelope.operation)
        let result = try await queue.execute(command, actor: actor)
        network.send(Frame(type: "recommendation.plan.result", plan: envelope, outcome: result.outcome), to: peer)
    }

}
