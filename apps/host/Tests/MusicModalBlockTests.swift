import Testing

@testable import CadenzaHost

struct MusicModalBlockTests {
    @Test func aSheetOrDialogOnMusicsWindowBlocksIt() {
        #expect(MusicModalBlock.isBlocked(roleNames: ["AXWindow", "AXSheet"]))
        #expect(MusicModalBlock.isBlocked(roleNames: ["AXWindow", "AXDialog"]))
    }

    @Test func aWindowWithOnlyItsContentDoesNotBlockIt() {
        #expect(!MusicModalBlock.isBlocked(roleNames: ["AXWindow", "AXScrollArea", "AXTable", ""]))
    }
}
