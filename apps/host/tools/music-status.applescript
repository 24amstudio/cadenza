-- Read-only diagnostic. It does not start Music or change playback.
if application "Music" is not running then
    return "music_running=false"
end if

with timeout of 1 seconds
    tell application "Music"
        set reportLines to {"music_running=true", "player_state=" & (player state as text)}
        try
            set end of reportLines to "position_seconds=" & (player position as text)
        on error
            set end of reportLines to "position_seconds=unavailable"
        end try
        try
            set end of reportLines to "track_name=" & (name of current track as text)
            set end of reportLines to "artist=" & (artist of current track as text)
            set end of reportLines to "duration_seconds=" & (duration of current track as text)
            set end of reportLines to "persistent_id=" & (persistent ID of current track as text)
        on error errorMessage number errorNumber
            set end of reportLines to "track_metadata_error=" & (errorNumber as text)
        end try
    end tell
end timeout

set originalDelimiters to AppleScript's text item delimiters
set AppleScript's text item delimiters to linefeed
set reportText to reportLines as text
set AppleScript's text item delimiters to originalDelimiters
return reportText
