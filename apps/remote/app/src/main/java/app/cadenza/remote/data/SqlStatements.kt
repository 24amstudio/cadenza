package app.cadenza.remote.data

object SqlStatements {
    fun parse(source: String): List<String> {
        val result = mutableListOf<String>()
        val statement = StringBuilder()
        var trigger = false
        for (line in source.lineSequence()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("--")) continue
            if (statement.isEmpty()) trigger = trimmed.startsWith("CREATE TRIGGER", ignoreCase = true)
            statement.appendLine(line)
            if ((!trigger && trimmed.endsWith(";")) || (trigger && trimmed.equals("END;", ignoreCase = true))) {
                val sql = statement.toString().trim()
                if (!sql.startsWith("PRAGMA", ignoreCase = true) &&
                    !sql.equals("BEGIN IMMEDIATE;", ignoreCase = true) &&
                    !sql.equals("COMMIT;", ignoreCase = true)
                ) {
                    result.add(sql)
                }
                statement.clear()
                trigger = false
            }
        }
        require(statement.isEmpty()) { "Incomplete database migration statement." }
        return result
    }
}
