-- Fixed Music boundary: writes the artwork of the current track to the one POSIX path it is given.
-- It reads artwork only. It does not change playback, the queue, or the library.
on run argv
	set outputPath to item 1 of argv
	tell application "Music"
		-- A radio station can have no artwork, and a stopped Music has no current track. Both end without a file.
		set artworkCount to 0
		try
			set artworkCount to count of artworks of current track
		end try
		if artworkCount is 0 then return
		set artwork_ to artwork 1 of current track
		set artworkData to raw data of artwork_
		set outputFile to open for access (POSIX file outputPath) with write permission
		try
			set eof of outputFile to 0
			write artworkData to outputFile
			close access outputFile
		on error errorMessage
			try
				close access outputFile
			end try
			error errorMessage
		end try
	end tell
end run
