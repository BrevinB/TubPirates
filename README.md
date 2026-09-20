# Tub Pirates

A bathtub-themed naval battle game for iOS — Battleship mechanics with special shot types,
an AI opponent, and Game Center multiplayer.

## Architecture

The game rules live in **`BathtubEngine`**, a standalone Swift package with no UI dependencies:
board state, ship placement, shot resolution, and the AI all sit behind a pure Swift API, and are
unit tested on their own. The app target is a SwiftUI layer on top of that engine.

```
Packages/BathtubEngine/    Pure Swift game engine + tests
  Sources/                 Board, Ship, Move, ShotType, GameState, BattleAI
  Tests/                   Placement, shot pattern, turn resolution, AI tests
TubPirates/                SwiftUI app
  Match/                   Match flow, AI opponent, save/restore
  GameCenter/              Matchmaking, achievements, Hall of Fame, quick chat
  Audio/, App/             Sound, haptics, routing
scripts/, metadata/        Build and App Store tooling
```

## Features

- **Solo play** against a tiered AI opponent
- **Game Center multiplayer** with turn-based matches, quick chat, and achievements
- **Special shot types** beyond the classic single-tile shot
- **Match saving** so a game survives being backgrounded
- **Localized** content models

## Tech

SwiftUI · Swift Package Manager · GameKit · AVFoundation · Core Haptics
