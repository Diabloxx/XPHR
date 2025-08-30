# XPHR — Party XP/hour (MoP Classic)

Self-contained World of Warcraft addon for Mists of Pandaria Classic that tracks your XP per hour and shows your party’s XP/hr, TTL, and session XP in a compact, movable UI. No external libraries.

- Client: MoP Classic (Interface: 50400 placeholder)
- SavedVariables: `XPHRDB`
- Addon prefix: `XPHR`

## Features
- Session XP/hr for you and party members (your row is always shown and pinned first)
- TTL (time to level) based on your session rate
- Compact, movable frame with saved position and simple right-click menu
- Lightweight party comms (only PARTY, throttled, evicts stale entries)
- Robust to party changes and level-ups (XP wrap handled)
- CPU/GC friendly (no heavy polling; UI refresh every ~0.5s)

## Install
1. Download or clone this repo.
2. Copy the `XPHR` folder into your WoW Classic AddOns directory, for example:
   - Windows: `C:\\Program Files (x86)\\World of Warcraft\\_classic_\\Interface\\AddOns\\XPHR`
3. Restart the game or run `/reload`.

## Usage
- `/xphr` — Toggle the window on/off
- `/xphr reset` — Reset the current session
- `/xphr lock` / `/xphr unlock` — Lock/unlock frame movement

UI columns:
- Name (class-colored) • Lvl • XP/hr • TTL • Sess (total session XP)

Tips:
- XP/hr and TTL update once you gain XP in the current session.
- Right-click the frame for quick actions (reset, lock/unlock, hide).

## How XP/hr is calculated
- Session rate: `xpPerHour_session = totalSessionXP / (elapsedSeconds / 3600)`
- TTL: `ttlSeconds = (xpToLevel / xpPerHour_session) * 3600` (shows `--:--` if the rate is 0)
- Level-ups are handled by wrapping: `(lastXPMax - lastXP) + newXP`

Note: The UI intentionally shows the session rate only. Internal rolling estimators exist but are not displayed.

## Party comms
- Prefix: `XPHR`
- Channel: PARTY only (does not send in RAID)
- Throttle: send every 5s or within 0.5s after XP gains
- Payload: compact key/value string (versioned)
- Eviction: party entries older than ~15s or no longer grouped are removed
- Compatibility: supports both `C_ChatInfo` and legacy Classic APIs

## Files
- `XPHR.toc` — Addon manifest
- `XPHR.lua` — Core logic (events, XP tracking, session math, slash commands)
- `XPHR_UI.lua` — UI (frame, rows, sorting, right-click menu, persistence)
- `XPHR_Comms.lua` — Party communications (prefix, payloads, throttling, cleanup)
- `XPHR.xml` — Minimal stub (UI built in Lua)

## Development
- No build step required; edit files and `/reload`
- SavedVariables: `XPHRDB` stores window position, visibility, locked state
- Testing: verify `/xphr`, regroup/ungroup, level-up, zone changes, and XP events

## Known limitations
- TTL shows `--:--` until a non-zero session rate is established
- Only players running XPHR will broadcast their stats; others still appear by name/level
- Interface number may need adjustment based on the exact MoP Classic client build

## License
TBD by repository owner.
