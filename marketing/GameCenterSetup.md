# Game Center Setup — Tub Pirates

Code side is done: `AchievementReporter` submits progress after every recorded
battle, leaderboard scores post automatically, and the menu's record chip
(trophy icon) opens the native Game Center dashboard. This checklist is the
App Store Connect configuration. Everything must use these EXACT IDs.

## Leaderboards (App Store Connect → Your App → Game Center)

| ID | Name | Type | Format | Sort |
|---|---|---|---|---|
| `tubpirates.leaderboard.wins` | Most Victories | Classic | Integer | High to low |
| `tubpirates.leaderboard.doubloons` | Lifetime Doubloons Plundered | Classic | Integer | High to low |

## Achievements

Points must total ≤ 1000. Images: upload the matching file from
`marketing/achievements/` (transparent PNG, displayed in a circle).

| ID | Name | Description (player-facing) | Pts | Hidden | Image |
|---|---|---|---|---|---|
| `tubpirates.achievement.firstwin` | First Splash | Win your first battle. | 25 | No | ach_first_win.png |
| `tubpirates.achievement.wins10` | Seasoned Sailor | Win 10 battles. | 50 | No | ach_wins_10.png |
| `tubpirates.achievement.wins25` | The Tub King | Win 25 battles and claim the crown. | 100 | No | ach_wins_25.png |
| `tubpirates.achievement.pugbeard` | Pugbeard's Bane | Sink Captain Pugbeard's fleet 3 times. | 50 | No | ach_pugbeard.png |
| `tubpirates.achievement.sal` | Cat Overboard | Sink Soapy Sal's fleet 4 times. | 75 | No | ach_sal.png |
| `tubpirates.achievement.bess` | Eight Arms Undone | Sink Barnacle Bess's fleet 5 times. | 100 | No | ach_bess.png |
| `tubpirates.achievement.champion` | Tub Champion | Conquer the entire captain ladder. | 200 | No | ach_champion.png |
| `tubpirates.achievement.flawless` | Squeaky Clean | Win a battle without losing a single ship cell. | 100 | No | ach_flawless.png |
| `tubpirates.achievement.broadside` | Full Broadside | Fire every special cannon at least once. | 100 | No | ach_broadside.png |
| `tubpirates.achievement.fleetadmiral` | Fleet Admiral | Own every fleet in the Shipyard. | 200 | No | ach_fleet_admiral.png |

Total: 1000 points.

Progressive achievements (Game Center shows a progress bar automatically —
the app reports fractional percentComplete): wins10, wins25, all three
captain rungs, broadside, fleetadmiral.

## Notes
- Turn-based multiplayer is already enabled from the online-battle work;
  leaderboards/achievements ride the same Game Center capability.
- Reporting is fire-and-forget and auth-gated; players who skip Game Center
  sign-in simply accumulate locally and the achievements catch up the next
  time they play a battle while signed in (reporter recomputes everything
  from the profile each battle — nothing is lost).
- Flawless is defined as zero enemy hits landed (`hitCells.isEmpty`), and the
  tutorial battle is excluded.
- Sandbox test: sign into a sandbox account on device → win one battle →
  First Splash banner should drop + both leaderboards populate.
