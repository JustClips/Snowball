# Roll the Snowball

Roblox game (third JustClips game). Design: `GAME_PLAN.md` and `BUILD_PROMPT.md` in the
project folder `game-ideas/roll-the-snowball/`. Code layout and how to add things:
`docs/ARCHITECTURE.md`.

Synced into Studio with LiveSync (same setup as JustClips/Dev and JustClips/tulevo). Push to
`main` and the change shows up in the open Studio place within a few seconds.

| Folder | Goes to |
|---|---|
| `src/shared` | ReplicatedStorage.Shared |
| `src/server` | ServerScriptService.Server |
| `src/client` | StarterPlayer.StarterPlayerScripts.Client |
| `src/gui` | StarterGui |
| `src/workspace` | Workspace |

File names: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript,
a folder with `init.luau` becomes that script. `.model.json` and `.meta.json` work like in Rojo.

## Connect Studio

1. Open the Roll the Snowball place in Studio (a new, empty Baseplate place is fine).
2. Open the LiveSync panel, set the repository to `JustClips/Snowball`, branch `main`, press Connect.
   The place remembers it. The plugin and server live in JustClips/Dev (`studio-plugin/`, `sync-server/`).
3. Game Settings > Security: turn on **Enable Studio Access to API Services** to test saving
   (without it the game uses an in-memory save that resets every test).

The world (summit, bases, launch deck, track) is graybox, built by `WorldService` at server start
from `Config/World` and `Config/Track`, until the Blender models are uploaded.

## Checks before pushing

`stylua --syntax luau --check src` must pass (parse check). Configs hold all balance numbers.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): where things live in code
- [docs/PLAYTEST.md](docs/PLAYTEST.md): sync steps, test commands and a playtest checklist
