# PerHour

A World of Warcraft Forever addon that shows your gold per hour and experience
per hour in a small window, and the time to your next level. Each counter has
its own Pause and Reset.

Only time spent logged in, unpaused and not AFK counts, and the totals survive
`/reload` and logout, so the rate holds across sessions until you reset it.

Gold is the money you make in the world: loot, quest rewards and vendor sales,
minus repairs and purchases. Money that moves while the mailbox, trade window,
auction house or guild bank is open is a transfer, not farming, and is not
counted. Time to level is the XP you still need at the session's rate. The
experience counter hides itself at max level.

Drag the window to move it; hover a counter for its totals. Closing the window
keeps it counting. If another addon has loaded LibDataBroker, the rates also
show on broker bars such as Titan Panel, and on a minimap button when LibDBIcon
is loaded too.

| Command | Does |
|---|---|
| `/goldxp` | Show or hide the window |
| `/goldxp gold`, `/goldxp xp` | Show or hide one counter |
| `/goldxp scale 0.8` | Resize the window (0.5 to 2) |
| `/goldxp minimap` | Show or hide the minimap button |
| `/goldxp reset` | Reset both counters |

`/perhour` and `/ph` work too, unless another addon already uses them: other
per-hour addons do, and whichever loads last would take them over. The addon
says so in chat when it leaves one alone.

## Install

Download the ZIP from [Releases](https://github.com/coylemichael/wow-perhour/releases)
and extract it into `World of Warcraft/_forever_/Interface/AddOns`.

## Releasing

Publishing a GitHub Release publishes the addon:

```sh
gh release create v1.1 --generate-notes
```

The [Release workflow](.github/workflows/release.yml) checks the Lua syntax,
packages the addon with the [BigWigsMods packager](https://github.com/BigWigsMods/packager),
which writes the tag into the TOC's `## Version`, uploads it to CurseForge and
attaches the ZIP to the release. Commits and tags alone publish nothing.
`gh workflow run release.yml` builds the ZIP as a workflow artifact without
uploading it anywhere.

CurseForge setup, once:

1. Create the project on [CurseForge](https://authors.curseforge.com/) and add
   `## X-Curse-Project-ID: <id>` to `PerHour.toc`. Until then, releases go to
   GitHub only.
2. Create an [API token](https://www.curseforge.com/account/api-tokens) and save
   it as this repository's `CF_API_KEY` secret.
