Drop App Store screenshots here, named so they sort in the order you want them shown
(`01_wallet.png`, `02_card.png`, ...).

Required sizes — one iPhone set and, because the app ships universal, one iPad set:

| Device class | Pixels |
|---|---|
| 6.9" iPhone | 1320 × 2868 |
| 6.5" iPhone | 1242 × 2688 |
| 13" iPad    | 2064 × 2752 |

`fastlane release` skips screenshot upload while this directory holds no PNGs, so the lane
stays usable before they exist.
