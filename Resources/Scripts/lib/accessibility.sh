# Run from Terminal. macOS may ask to allow Terminal to control System Events.
# If blocked, enable Terminal in System Settings > Privacy & Security > Accessibility.
/usr/bin/osascript - "$AX_ID" "$PANE" "$LABEL" <<'APPLESCRIPT'
on findSwitch(wantedID)
    tell application "System Events"
        tell process "System Settings"
            if not (exists window 1) then return missing value
            set matches to {}
            repeat with candidate in (entire contents of window 1)
                try
                    if (value of attribute "AXIdentifier" of candidate as text) is wantedID then
                        set end of matches to contents of candidate
                    end if
                end try
            end repeat
            if (count of matches) > 1 then error "More than one matching switch. Nothing clicked."
            if (count of matches) is 1 then return item 1 of matches
        end tell
    end tell
    return missing value
end findSwitch

on switchValue(targetSwitch)
    tell application "System Events"
        set currentValue to value of targetSwitch
    end tell
    if currentValue is 1 or currentValue is true then return 1
    if currentValue is 0 or currentValue is false then return 0
    error "Could not read the switch state. Nothing clicked."
end switchValue

on run argv
    set wantedID to item 1 of argv
    set paneID to item 2 of argv
    set settingName to item 3 of argv
    if wantedID is not in {"AX_SPOKEN_HOTKEY", "AX_VIRTUAL_KEYBOARD"} then error "Unknown setting."
    tell application "System Settings"
        activate
        open location ("x-apple.systempreferences:com.apple.preference.universalaccess?" & paneID)
    end tell
    set targetSwitch to missing value
    repeat 40 times
        set targetSwitch to my findSwitch(wantedID)
        if targetSwitch is not missing value then exit repeat
        delay 0.25
    end repeat
    if targetSwitch is missing value then error "Switch not found. Use the manual option; this macOS layout may differ."
    if my switchValue(targetSwitch) is 1 then return settingName & " is already on. No click needed."
    tell application "System Events" to click targetSwitch
    repeat 40 times
        delay 0.25
        set targetSwitch to my findSwitch(wantedID)
        if targetSwitch is not missing value then
            if my switchValue(targetSwitch) is 1 then return settingName & " is now on (verified)."
        end if
    end repeat
    error "Clicked once, but could not verify the switch is on. Check System Settings; no second click was sent."
end run
APPLESCRIPT
