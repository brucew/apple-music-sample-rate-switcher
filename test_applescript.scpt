#!/usr/bin/osascript
tell application "Music"
    if it is running then
        try
            set curTrack to current track
            set trackName to name of curTrack
            set trackArtist to artist of curTrack
            set trackRate to sample rate of curTrack
            return "Track: " & trackName & " by " & trackArtist & " | Sample Rate: " & (trackRate as string) & " Hz"
        on error errStr
            return "Error: " & errStr
        end try
    else
        return "Music is not running"
    end if
end tell
