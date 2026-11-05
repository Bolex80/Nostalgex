# Personal and new channels — 31/10/2026

Built from **actual Plex watch history**, not from guesses. Source:
`GET /status/sessions/history/all` on the Plex server (35,090 entries, 5,945 video plays), grouped
by `accountID` and mapped to names via `/accounts`.

## What each person actually watches

| Person | Account | Evidence |
|---|---|---|
| Alex | `alexbenthem` (1,540 plays) | South Park 52, Baywatch 48, Mr. Robot 36, House of the Dragon 25, El encargado 25, Counterpart 20, Your Friends & Neighbors 19, Entrevías 15 |
| Marcos | `Marcos Benthem` (45 plays) | Coco 17, The Boss Baby 13, Sing: Thriller 8, Alice in Wonderland 3, Sing 2 3 |
| Sofía | `Sofia Benthem` (4 plays) | Sing: Thriller 2, Zootopia 1, Lava 1 — almost no history, so the channel is Disney/princess-led |
| Hugo | two accounts, `Hugo` + `Hugo Benthem Balbuena` (25 plays) | Primal 23 — one show dominates |

## Channels created

| CH | Name | id | How it is built | Measured content |
|---|---|---|---|---|
| 35 | ALEX'S SERIES | 500 | His watched shows + premium drama and the Spanish series still in the library | 666+ episodes |
| 36 | MARCOS | 501 | Animated family films: Coco, Sing, Boss Baby, Despicable Me, and similar | 65 films, 62 titles |
| 37 | SOFÍA | 502 | Disney and princess films: Frozen, Moana, Encanto, Tangled, Aladdin… | 13 films |
| 38 | HUGO | 503 | Primal is gone from the library, so action/animation/sci-fi that exists: One Piece, Rick and Morty, X-Men '97, The Flash, Umbrella Academy… | 722 episodes, 29 shows |
| 39 | CURRENT SERIES | 504 | Episodes whose show started in 2020 or later | 670 episodes, 61 shows |
| 56 | SERIES ES | 505 | Spanish series: ANHQV, Vis a Vis, Isabel, La casa de papel… | 293 episodes, 14 shows |
| 57 | DISNEY CLASSICS | 506 | Disney studio films up to 1999 | 12 films |
| 58 | TOON TIME | 507 | Cartoons in the library: Paw Patrol, Mazinger Z, Dragon Ball | 162 episodes |

**Numbering:** he asked for 4–7, but those numbers already belong to SAT MORNING CARTOONS,
90S SITCOMS, AFTER SCHOOL TV and VHS VAULT. The new channels took the free numbers 35–39 and
56–58 instead; renumbering the existing channels was not done without asking.

## What the measurement caught (and why the rules look like this)

- **Episodes carry no genres and no network in raw Plex data**, so a rule like
  `genres.include: [Drama]` or `networks: [Netflix]` matches **nothing**. "STREAMING ORIGINALS"
  was dropped for that reason and replaced by SERIES ES.
- **`ratingMin` filtered out everything**: on the tuner an episode takes the *show's* rating, and
  Plex often leaves that at 0. Removed from both year-based channels.
- **Some favourites are no longer in the library**: Primal (Hugo's whole history), El encargado and
  Entrevías (Alex). They cannot be channelled until the media exists again — a request in Seerr
  would fix that.
- **Generic single words matched unrelated films**: "Up" caught *Up in the Air*, "Wish" caught
  *Those Who Wish Me Dead*, "Brave" caught *Captain America: Brave New World*, "Monsters" caught
  *Godzilla: King of the Monsters*. Those words were removed.
- **A US content-rating allow-list silently excluded Spanish-rated films**, so the kids' channels
  are title-curated instead — the list itself is the safety gate.

## Reproduce the measurement

```sh
node research/measure-channels.mjs            # the eight new channels
node research/measure-channels.mjs 500 504    # or just some
```

It fetches the real library (cached in `research/library-cache.json` after the first run) and runs
the repo's own `scripts/nostalgex-channel-filter.cjs` — the same code the tuner uses — so a channel
that measures empty here would have been empty on the television.

Verified on the box afterwards: all eight channels enabled, each with a populated schedule.
