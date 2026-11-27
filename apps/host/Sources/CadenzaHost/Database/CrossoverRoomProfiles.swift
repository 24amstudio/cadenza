import Foundation

/// The acoustic delay measured for one room, kept across launches. The key pairs the Host's output device with the
/// Remote's browser. The Wi-Fi network is left out, because its BSSID needs Location permission, which Cadenza Host
/// does not request.
extension HostStore {
    static let maximumRoomOffsetUs: Int64 = 50_000

    func roomAcousticOffsetUs(profileKey: String) throws -> Int64? {
        try database.query(
            "SELECT acoustic_offset_us FROM crossover_room_profiles WHERE profile_key=?", [.text(profileKey)]
        ).first?["acoustic_offset_us"]?.integer
    }

    func saveRoomAcousticOffsetUs(_ offset: Int64, profileKey: String, measuredAtMs: Int64) throws {
        guard abs(offset) <= Self.maximumRoomOffsetUs else {
            throw CadenzaError.failure("calibration", "The room measurement is outside the allowed ±50 ms.")
        }
        try database.run(
            """
            INSERT INTO crossover_room_profiles(profile_key,acoustic_offset_us,measured_at_ms) VALUES(?,?,?)
            ON CONFLICT(profile_key) DO UPDATE SET
              acoustic_offset_us=excluded.acoustic_offset_us, measured_at_ms=excluded.measured_at_ms
            """,
            [.text(profileKey), .integer(offset), .integer(measuredAtMs)])
    }

    func clearRoomProfile(profileKey: String) throws {
        try database.run("DELETE FROM crossover_room_profiles WHERE profile_key=?", [.text(profileKey)])
    }
}
