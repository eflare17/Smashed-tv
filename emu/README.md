# The emulator behind the Mega Drive cabinet

This folder is [EmulatorJS](https://emulatorjs.org) 4.2.3 (GPL-3.0, see LICENSE), taken unchanged (its source files joined into emulator.min.js) from
the npm packages `@emulatorjs/emulatorjs`, `@emulatorjs/core-genesis_plus_gx` and `@emulatorjs/core-snes9x`. The Mega Drive core is
[Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX), which is free for non-commercial use only. The Super Nintendo core is
[Snes9x](https://github.com/snes9xgit/snes9x), also free for non-commercial use only.

No games are stored here. Players add their own game files, which stay in their own browser.

If this folder is missing (for example, Smashed.html opened on its own), the game loads the same
emulator from cdn.emulatorjs.org instead.
