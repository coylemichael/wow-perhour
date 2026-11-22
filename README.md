# PerHour

A World of Warcraft Forever addon that shows your gold per hour and experience
per hour in a small window. Each counter has its own Pause and Reset.

Only time spent logged in and unpaused counts, and the totals survive `/reload`
and logout, so the rate holds across sessions until you reset it. Gold is the
net change in your money: loot, quest rewards and vendor sales, minus repairs
and purchases. Drag the window to move it; hover a counter for its totals.

| Command | Does |
|---|---|
| `/perhour` or `/ph` | Show or hide the window |
| `/perhour reset` | Reset both counters |

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
