# MazDu Audio Assets

Assets only: no Swift, playback, haptic, or Xcode-project wiring has been added.

## Folder contract

- `source/` holds the unmodified originals downloaded from their licensed sources.
- `processed/` holds the implementation-ready files: 44.1 kHz, 16-bit PCM WAV.
- Every SFX is rendered with a tiny click-safe fade-in and a tailored fade-out already baked into the file. Do not loop any SFX below.

## BGM

| File | Screen / timing | Runtime in / out |
|---|---|---|
| `processed/bgm_menu_game_boi_2.wav` | Main menu only | Start once the menu is visible; fade in 250 ms. On confirmed PLAY, fade out 350 ms. Silent during search, ready-check, intro tour, and countdown. |
| `processed/bgm_race_itty_bitty_8_bit.wav` | Race only | Start transport exactly on `MULAI`, with a 40 ms gain ramp. On result/finish beat, fade out 350 ms. It is 193.8 s, longer than the 180 s race, so do not loop it. |

## SFX cue sheet

| File | Trigger | In / out handling |
|---|---|---|
| `processed/sfx_ui_select.wav` | Menu move or quick skill-selector tap | One-shot; 1 ms in, 10 ms out baked. Never play during a held input. |
| `processed/sfx_countdown_tick.wav` | `3`, `2`, `1` | One-shot; 3 ms in, 15 ms out baked. Pitch may rise per number, but do not stack retries. |
| `processed/sfx_countdown_go.wav` | `MULAI` | One-shot; 3 ms in, 25 ms out baked. It starts together with the race BGM. |
| `processed/sfx_dice_pickup.wav` | Dice pickup succeeds | One-shot; 3 ms in, 30 ms out baked. |
| `processed/sfx_roll_reveal.wav` | Roll result is revealed | One-shot; 3 ms in, 30 ms out baked. |
| `processed/sfx_attack_cast.wav` | Attacker sends a skill | One-shot; 3 ms in, 15 ms out baked. Never play it again for a cancelled skill. |
| `processed/sfx_attack_warning.wav` | Receiver telegraph begins | One-shot; 3 ms in, 20 ms out baked. Do not repeat while the warning remains active. |
| `processed/sfx_freeze_hit.wav` | Freeze resolves successfully | One-shot; 3 ms in, 45 ms out baked. |
| `processed/sfx_darken_impact.wav` | Darken resolves successfully | One-shot, never loop; 3 ms in, 60 ms out baked. Duck race BGM for about 250 ms, then restore it smoothly. |
| `processed/sfx_switch_resolve.wav` | Both players finish switching places | One-shot; 3 ms in, 30 ms out baked. Play only after the board state resolves. |
| `processed/sfx_shield_block.wav` | Shield blocks an incoming skill | One-shot; 3 ms in, 20 ms out baked. Suppress the blocked skill’s impact SFX. |
| `processed/sfx_obstacle_hit.wav` | Obstacle stun lands | One-shot; 3 ms in, 15 ms out baked. |
| `processed/sfx_result_win.wav` | Winner result is shown | One-shot; 3 ms in, 80 ms out baked. Start after race BGM begins its exit. |
| `processed/sfx_result_loss.wav` | Loss or opponent-disconnect result is shown | One-shot; 3 ms in, 25 ms out baked. Start after race BGM begins its exit. |

## Source ledger

| Final file | Original source | License |
|---|---|---|
| `sfx_ui_select.wav` | https://freesound.org/people/phiIRaco/sounds/572626/ | CC0 |
| `sfx_countdown_tick.wav` | https://freesound.org/people/jeckkech/sounds/391650/ | CC0 |
| `sfx_countdown_go.wav` | https://freesound.org/people/jeckkech/sounds/391649/ | CC0 |
| `sfx_dice_pickup.wav` | https://freesound.org/people/OwlStorm/sounds/404722/ | CC0 |
| `sfx_roll_reveal.wav` | https://freesound.org/people/OwlStorm/sounds/404770/ | CC0 |
| `sfx_attack_cast.wav` | https://freesound.org/people/petenice/sounds/9509/ | CC0 |
| `sfx_attack_warning.wav` | https://freesound.org/people/furbyguy/sounds/365641/ | CC0 |
| `sfx_freeze_hit.wav` | https://freesound.org/people/j_p_higgins/sounds/262635/ | CC0 |
| `sfx_darken_impact.wav` | https://freesound.org/people/qubodup/sounds/442825/ | CC0 |
| `sfx_switch_resolve.wav` | https://freesound.org/people/OwlStorm/sounds/404761/ | CC0 |
| `sfx_shield_block.wav` | https://freesound.org/people/OwlStorm/sounds/404786/ | CC0 |
| `sfx_obstacle_hit.wav` | https://freesound.org/people/OwlStorm/sounds/404792/ | CC0 |
| `sfx_result_win.wav` | https://freesound.org/people/EVRetro/sounds/535840/ | CC0 |
| `sfx_result_loss.wav` | https://freesound.org/people/OwlStorm/sounds/404743/ | CC0 |

## Music credits

`bgm_menu_game_boi_2.wav` — “Game BOI 2” by HoliznaCC0, CC0 1.0:\
https://freemusicarchive.org/music/holiznacc0/gamer-soundtrack-game-boi/game-boi-2/

`bgm_race_itty_bitty_8_bit.wav` — “Itty Bitty 8 Bit” by Kevin MacLeod\
(incompetech.com), licensed under CC BY 4.0:\
https://creativecommons.org/licenses/by/4.0/

Before shipping, expose the Kevin MacLeod attribution on an in-app credits surface.
