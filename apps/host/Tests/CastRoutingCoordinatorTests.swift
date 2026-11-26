import Testing

@testable import CadenzaHost

struct CastRoutingCoordinatorTests {
    private func route(
        _ target: CastRoutingCoordinator.Target,
        _ content: CastRoutingCoordinator.Content,
        _ mode: CastPresentationMode
    ) -> CastRoutingCoordinator.Route {
        CastRoutingCoordinator.route(for: target, content: content, presentation: mode)
    }

    @Test func aSpeakerOrUnknownScreenNeverReceivesVideo() {
        for mode in CastPresentationMode.allCases {
            #expect(route(.googleCast(.none), .localMusicVideo, mode) == .defaultReceiverAudio)
            #expect(route(.googleCast(.unknown), .localMusicVideo, mode) == .defaultReceiverAudio)
        }
    }

    @Test func aCatalogVideoNeverReachesACastDevice() {
        for display in [CastDisplay.none, .display, .unknown] {
            for mode in CastPresentationMode.allCases {
                #expect(route(.googleCast(display), .protectedMusicVideo, mode) == .defaultReceiverAudio)
            }
        }
    }

    @Test func aScreenDeviceShowsADRMFreeLocalVideoUnlessAudioOnlyIsChosen() {
        #expect(route(.googleCast(.display), .localMusicVideo, .auto) == .defaultReceiverVideo)
        #expect(route(.googleCast(.display), .localMusicVideo, .fullSuite) == .defaultReceiverVideo)
        #expect(route(.googleCast(.display), .localMusicVideo, .audioOnly) == .defaultReceiverAudio)
        #expect(route(.googleCast(.display), .song, .fullSuite) == .defaultReceiverAudio)
    }

    @Test func stageReceiversAndAirPlayTakeTheirOwnRoutes() {
        #expect(route(.stage, .song, .auto) == .stageFullSuite)
        #expect(route(.stage, .song, .audioOnly) == .stageAudio)
        #expect(route(.airPlay, .protectedMusicVideo, .auto) == .airPlayKaraokeProxy)
        #expect(route(.airPlay, .song, .auto) == .airPlayAudio)
    }
}
