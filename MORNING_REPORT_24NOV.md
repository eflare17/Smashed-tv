# Digger Game: overnight fixes (24 Nov 2026)

**The short version:** you picked "fix what's broken", so that's all I did. Five fixes, nothing new added. All the
game's tests pass (bar the old TreeTest UI-size check). The new build is in
`.claude/worktrees/voxel-blade-auto-e7e360/voxel-dozer-unity/Builds/DiggerGameOvernight2/DiggerGame.exe`.

## What changed

| Fix | What you'll notice |
|---|---|
| **The rifle and bow show in his hands** | From behind, his body was hiding them: both were held right in front of his chest. Now the rifle and freeze gun are carried off his right shoulder, angled down, and snap up to aim when you fire. The bow is held out on his left. Through his eyes, the bow sits left of the cross so it doesn't block your aim. |
| **The freeze gun is ice blue** | It was drawing bracken green: the colour list stopped one short. |
| **F6 asks first** | One press says "Load your last save? Press F6 again." A second press within 3 seconds loads. No more losing play to a slip. |
| **Test keys are off unless you turn them on** | F7 (trailer mode), F8 (free coins and gold) and F9 (break or fix the dozer) do nothing now unless **Esc > Settings > Test keys** is On. It remembers your choice. Turn it on if you want F8 back. |
| **E at the gold shed** | An arrow lying by the counter no longer gets in the way: E hands your gold in first. With no gold, E picks the arrow up. (The hopper and the cart already came before arrows.) |

## Tests

Two new tests: **ToolsLookTest** (every tool is in view, over the shoulder and through his eyes, with a picture each
in `voxel-dozer-unity/Logs/tool_*.png`) and **FixesTest** (test-keys switch, gold before arrows at the shed, F6 asks).
Then all 33 tests were run again; all pass except TreeTest's old `uiSize125Scale`.

## Not done (you didn't pick them)

Giving the extras a job, balancing the tools, and the morning video. The fresh-eyes review is in `REVIEW_23NOV.md`
if you want to look at it again.

## Your save

Backed up before the tests and put back after each one.

## Rollback

`git revert 920d9d5` takes out just these fixes.
