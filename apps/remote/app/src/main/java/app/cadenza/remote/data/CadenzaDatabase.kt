package app.cadenza.remote.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction
import app.cadenza.remote.model.id
import org.json.JSONObject

class CadenzaDatabase(
    private val context: Context,
) : SQLiteOpenHelper(context, "cadence.sqlite", null, 2) {
    data class PendingLog(
        val id: Long,
        val level: String,
        val action: String,
        val message: String,
    )

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
        db.execSQL("PRAGMA synchronous=FULL")
        if (db.version == 0) db.execSQL("PRAGMA auto_vacuum=INCREMENTAL")
    }

    override fun onCreate(db: SQLiteDatabase) {
        migrate(db, "000-initial.sql")
    }

    override fun onUpgrade(
        db: SQLiteDatabase,
        oldVersion: Int,
        newVersion: Int,
    ) {
        if (oldVersion < 2) migrate(db, "001-recommendations.sql")
        if (newVersion > 2) error("Unsupported database version. Your existing data was preserved.")
    }

    override fun onDowngrade(
        db: SQLiteDatabase,
        oldVersion: Int,
        newVersion: Int,
    ) {
        error("This database needs a newer Cadenza Remote. No data was deleted.")
    }

    private fun migrate(
        db: SQLiteDatabase,
        name: String,
    ) {
        val sql =
            context.assets
                .open("storage/" + name)
                .bufferedReader()
                .use { it.readText() }
        SqlStatements.parse(sql).forEach(db::execSQL)
    }

    @Synchronized
    fun setting(key: String): String? {
        readableDatabase.rawQuery("SELECT value FROM settings WHERE key=?", arrayOf(key)).use {
            return if (it.moveToFirst()) it.getString(0) else null
        }
    }

    @Synchronized
    fun saveSettings(vararg changes: Pair<String, String?>) {
        val db = writableDatabase
        db.transaction {
            for ((key, value) in changes) {
                if (value == null) {
                    db.delete("settings", "key=?", arrayOf(key))
                } else {
                    db.execSQL("INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)", arrayOf(key, value))
                }
            }
        }
    }

    @Synchronized
    fun saveProfile(profile: HostProfile) {
        val values =
            ContentValues().apply {
                put("host_id", profile.hostId)
                put("display_name", profile.name)
                put("credential_reference", "host." + profile.hostId)
                put("address", profile.address)
                put("port", profile.port)
                put("fingerprint", profile.fingerprint)
                put("remote_id", profile.remoteId)
                put("certificate_der_base64", profile.certificateDerBase64)
            }
        val db = writableDatabase
        db.transaction {
            val previous = this@CadenzaDatabase.profile(profile.hostId)
            if (previous != null && previous.remoteId != profile.remoteId) {
                db.delete("playback_credits", "host_id=?", arrayOf(profile.hostId))
                values.put("last_credit_sequence", 0)
            }
            if (db.update("paired_hosts", values, "host_id=?", arrayOf(profile.hostId)) == 0) {
                db.insertOrThrow("paired_hosts", null, values)
            }
        }
    }

    @Synchronized
    fun savePending(
        profile: HostProfile,
        frame: JSONObject,
        key: String,
    ) {
        writableDatabase.execSQL(
            "INSERT INTO pending_commands VALUES(?,?,?,?,?,?)",
            arrayOf<Any>(
                profile.hostId,
                profile.remoteId,
                frame.getString("command_id"),
                frame.toString(),
                key,
                System.currentTimeMillis(),
            ),
        )
    }

    @Synchronized
    fun pending(profile: HostProfile): List<Pair<JSONObject, String>> {
        val result = mutableListOf<Pair<JSONObject, String>>()
        readableDatabase
            .rawQuery(
                "SELECT body_json,pending_key FROM pending_commands WHERE host_id=? AND remote_id=? ORDER BY created_at_ms",
                arrayOf(profile.hostId, profile.remoteId),
            ).use {
                while (it.moveToNext()) result.add(JSONObject(it.getString(0)) to it.getString(1))
            }
        return result
    }

    @Synchronized
    fun finishPending(
        profile: HostProfile,
        id: String,
    ) {
        writableDatabase.delete(
            "pending_commands",
            "host_id=? AND remote_id=? AND command_id=?",
            arrayOf(profile.hostId, profile.remoteId, id),
        )
    }

    @Synchronized
    fun profile(hostId: String): HostProfile? {
        readableDatabase
            .rawQuery(
                "SELECT host_id,display_name,address,port,fingerprint,remote_id,certificate_der_base64 FROM paired_hosts WHERE host_id=?",
                arrayOf(hostId),
            ).use {
                if (!it.moveToFirst()) return null
                return HostProfile(
                    it.getString(0),
                    it.getString(1),
                    it.getString(2),
                    it.getInt(3),
                    it.getString(4),
                    it.getString(5),
                    it.getString(6),
                )
            }
    }

    @Synchronized
    fun cachedState(hostId: String): HostSnapshot? {
        readableDatabase.rawQuery("SELECT body_json FROM host_snapshots WHERE host_id=?", arrayOf(hostId)).use {
            if (!it.moveToFirst()) return null
            return runCatching {
                val text = it.getString(0)
                require(text.toByteArray().size <= Wire.MAXIMUM_BYTES)
                Wire.snapshot(JSONObject(text)).also { snapshot -> require(snapshot.hostId == hostId) }
            }.getOrNull()
        }
    }

    @Synchronized
    fun saveState(
        hostId: String,
        value: JSONObject,
    ) {
        val body = value.toString()
        require(body.toByteArray().size <= Wire.MAXIMUM_BYTES)
        val values =
            ContentValues().apply {
                put("host_id", hostId)
                put("body_json", body)
                put("saved_at_ms", System.currentTimeMillis())
            }
        check(writableDatabase.insertWithOnConflict("host_snapshots", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }

    @Synchronized
    fun cursor(hostId: String): Long {
        readableDatabase.rawQuery("SELECT last_credit_sequence FROM paired_hosts WHERE host_id=?", arrayOf(hostId)).use {
            return if (it.moveToFirst()) it.getLong(0) else 0
        }
    }

    @Synchronized
    fun applyCredit(
        hostId: String,
        frame: JSONObject,
    ): Long {
        val sequence = frame.counter("sequence")
        val delta = frame.counter("played_ms_delta")
        val count = frame.counter("play_count_delta")
        require(sequence in 1..Wire.MAXIMUM_COUNTER && delta in 0..Wire.MAXIMUM_COUNTER && count in 0..1) { "Invalid playback credit." }
        val song = frame.getJSONObject("song")
        val db = writableDatabase
        return db.transaction {
            db.execSQL(
                "INSERT INTO playback_credits VALUES(?,?,?,?,?,?,?,?)",
                arrayOf<Any>(
                    hostId,
                    sequence,
                    frame.identifier("event_id"),
                    frame.identifier("occurrence_id"),
                    song.getString("source"),
                    song.getString("id"),
                    count,
                    delta,
                ),
            )
            cursor(hostId)
        }
    }

    @Synchronized
    fun remember(
        hostId: String,
        songs: List<Song>,
    ) {
        val db = writableDatabase
        db.transaction {
            for (song in songs) {
                val values =
                    ContentValues().apply {
                        put("host_id", hostId)
                        put("source", song.source)
                        put("song_id", song.id)
                        put("title", song.title.take(500))
                        put("artist", song.artist.take(500))
                    }
                db.insertWithOnConflict("song_metadata", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            }
        }
    }

    @Synchronized
    fun statistics(hostId: String): List<SongStatistic> {
        val sql =
            """
            SELECT s.source,s.song_id,coalesce(m.title,s.song_id),coalesce(m.artist,''),s.play_count,s.played_ms
            FROM song_statistics s LEFT JOIN song_metadata m
              ON m.host_id=s.host_id AND m.source=s.source AND m.song_id=s.song_id
            WHERE s.host_id=? ORDER BY s.play_count DESC,s.played_ms DESC LIMIT 200
            """.trimIndent()
        val result = mutableListOf<SongStatistic>()
        readableDatabase.rawQuery(sql, arrayOf(hostId)).use {
            while (it.moveToNext()) {
                result.add(
                    SongStatistic(it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getLong(4), it.getLong(5)),
                )
            }
        }
        return result
    }

    @Synchronized
    fun maintain() {
        val db = writableDatabase
        db.delete("playback_credits", null, null)
        db.rawQuery("PRAGMA optimize", null).use { while (it.moveToNext()) { /* Execute all maintenance rows. */ } }
        db.rawQuery("PRAGMA wal_checkpoint(PASSIVE)", null).use { while (it.moveToNext()) { /* Execute all maintenance rows. */ } }
        db.execSQL("PRAGMA incremental_vacuum(32)")
    }

    @Synchronized
    fun queueLog(
        level: String,
        action: String,
        message: String,
    ) {
        val values =
            ContentValues().apply {
                put("level", level.take(16))
                put("action", action.take(120))
                put("message", message.take(2_000))
                put("created_at_ms", System.currentTimeMillis())
            }
        writableDatabase.insert("remote_log_outbox", null, values)
        writableDatabase.execSQL(
            "DELETE FROM remote_log_outbox WHERE log_id NOT IN (SELECT log_id FROM remote_log_outbox ORDER BY log_id DESC LIMIT 200)",
        )
    }

    @Synchronized
    fun pendingLogs(limit: Int = 100): List<PendingLog> {
        val result = mutableListOf<PendingLog>()
        readableDatabase
            .rawQuery(
                "SELECT log_id,level,action,message FROM remote_log_outbox ORDER BY log_id LIMIT ?",
                arrayOf(limit.toString()),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    result.add(
                        PendingLog(cursor.getLong(0), cursor.getString(1), cursor.getString(2), cursor.getString(3)),
                    )
                }
            }
        return result
    }

    // One statement per accepted batch, so a delivered batch costs a single write.
    @Synchronized
    fun deleteLogs(ids: List<Long>) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        writableDatabase.delete("remote_log_outbox", "log_id IN ($placeholders)", ids.map { it.toString() }.toTypedArray())
    }

    @Synchronized
    fun saveRecommendationEvent(
        eventId: String,
        recommendationId: String?,
        source: String,
        songId: String,
        outcome: String,
        positionMs: Long?,
        durationMs: Long?,
        replacementJson: String?,
        occurredAtMs: Long,
    ) {
        require(source == "catalog" || source == "library")
        require(
            outcome in
                setOf(
                    "qualified_play",
                    "early_skip",
                    "late_skip",
                    "replay",
                    "favorite",
                    "manual_replacement",
                    "queue_removal",
                    "interruption",
                ),
        )
        val values =
            ContentValues().apply {
                put("event_id", eventId)
                recommendationId?.let { put("recommendation_id", it) }
                put("source", source)
                put("song_id", songId)
                put("outcome", outcome)
                positionMs?.let { put("position_ms", it) }
                durationMs?.let { put("duration_ms", it) }
                replacementJson?.let { put("replacement_json", it) }
                put("occurred_at_ms", occurredAtMs)
            }
        writableDatabase.insertOrThrow("recommendation_events", null, values)
        writableDatabase.execSQL(
            "DELETE FROM recommendation_events WHERE event_id NOT IN (SELECT event_id FROM recommendation_events ORDER BY occurred_at_ms DESC LIMIT 5000)",
        )
    }

    @Synchronized
    fun saveRecommendationPassport(
        sequence: Long,
        payload: String,
        publicKey: String,
        signature: String,
        createdAtMs: Long,
    ) {
        require(sequence > 0 && payload.length <= 131_072 && publicKey.length <= 1_024 && signature.length <= 1_024)
        val values =
            ContentValues().apply {
                put("sequence", sequence)
                put("payload_base64", payload)
                put("public_key_base64", publicKey)
                put("signature_base64", signature)
                put("created_at_ms", createdAtMs)
            }
        writableDatabase.insertOrThrow("recommendation_passports", null, values)
        writableDatabase.execSQL(
            "DELETE FROM recommendation_passports WHERE sequence < (SELECT max(sequence) - 2 FROM recommendation_passports)",
        )
    }
}
