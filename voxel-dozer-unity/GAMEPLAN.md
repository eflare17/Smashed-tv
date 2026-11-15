# Mine game: the plan

One page. A new idea gets checked against this page. It either goes on the **Later** list, or it swaps
something out of **In**. Nothing gets built that isn't on here.

Status: draft, 16 Nov 2026. Items marked *(suggested)* are Claude's suggestions, not yet agreed.

## The game in one line

Dig out an old caved-in mine by hand, haul the dirt out in a cart for money, and spend it on upgrades
that let you dig faster and deeper. Play it with friends.

## The loop

1. Dig: pick to break ground, shovel to throw it.
2. Fill the cart and push it out of the mine.
3. Tip it at the dump to get paid. Every litre pays a little; gold pays more.
4. Open the upgrade tree (one key), click an upgrade, and it works straight away. There's no store.
5. Dig faster and deeper. Repeat.

**Feel:** the first upgrade comes within a couple of minutes, then each one takes a bit longer, like
incremental games. Every upgrade should make a difference you can feel at once.

## In (version 1)

- One mine: the one there now, with the cave-in.
- Pick, shovel, the hand cart on rails, and tipping at a dump.
- Money: paid when a cart is tipped at the dump.
- The upgrade tree, about 10 to 15 upgrades:
  - **Shovel:** bigger shovelfuls, faster swings, and a stronger pick. *(suggested: 4 or 5 steps)*
  - **Backpack:** unlocks when the shovel is maxed out. It starts weak: small, and only pulls dirt well.
    Then it gets bigger and stronger, with more suction power.
  - **Cart:** holds more, and pushes easier.
- Heavier ground needs more suction: soil is easiest, then clay, then rock rubble, quartz and gold
  (gold is the heaviest). Too heavy for your backpack means: *(to decide: it won't budge, or it trickles
  in slowly)*
- Multiplayer, built in from the start (see below).
- Saving (it's already there: F5 / F6).

## Multiplayer

Built in from the start, because adding it later means rewriting most of the game.

**How it would work** *(suggested)*:
- One player hosts and the others join. The host's game is the real one.
- The ground is never sent whole (it's 528 MB). Every game builds the same starting mine from the same
  recipe, the same way saving already works. After that, only the changes get sent: each pick hit,
  shovelful, suck and tip.
- The host runs the falling dirt. Everyone else is told where the clods are and where they settle.
- Players, the cart and the upgrades are kept in step by the host.
- Smashed already does host-and-join in Godot (ENet over the network, PeerJS in the browser). The
  idea carries over, but the code doesn't, because it's a different engine.
- **Decided:** hand-written on C#'s built-in network connections, like Smashed, with no Unity
  networking package and nothing to install.
- **Decided:** version 1 works over the same Wi-Fi first, but it has to work **over the internet** in
  the end. So the connection layer is kept separate from the game, and internet play gets added by
  swapping that layer, not by rewriting the game. To get past home routers, it'll need a go-between
  service (for example Unity's relay, with a free tier and a Unity account) or the host opening a
  router port. That gets chosen when we get there.

- **Decided:** up to **4 players**. The host sends the same changes to every guest, so 4 is only a little
  more work than 2.
- **Decided:** **PC and phone**, playing together. The look aims to push the owner's RTX 4090 on PC,
  and to get as much as the S25 Ultra can manage on the phone. So there's one game with quality
  settings that scale: on the phone, less draw distance, fewer flying clods and simpler lighting.
  The phone also needs touch controls, and Unity's Android build support, which is an install
  (needs an OK). **Decided:** build on PC. The phone gets proper work at the end, with a check-in on
  the phone now and then along the way, and nothing gets built in a way that rules it out.

- **Decided:** **one shared pot of money and one shared upgrade tree** for the whole team, for
  simplicity. Solo play works the same way.
- **Selling back** *(suggested, owner agreed with the idea)*: any player can sell back an upgrade for a
  **full refund**, as long as nothing they own depends on it. That means the newest step in a branch,
  so it works as an undo without resetting the whole tree. The tree shows which player bought each
  upgrade, so a disagreement is easy to sort out.
- Later, if wanted: shared money but each player upgrades their own tools.

## Later (not in version 1)

- Telling gold apart, and the filter machine
- A shop building
- Enemies (voxel style like Smashed, with limbs that come off)
- Finishing a mine, then a second shaft with machinery
- The dozer and the Dingo as things you earn (the dozer stays drivable for testing until then)
- Supports and shoring, and deeper, harder layers
- A motor for the cart, and better tracks
- Washing the dozer

## Open questions

1. Too heavy for the backpack: won't budge, or slow trickle?
2. What does a litre of dirt pay, and what does gold pay? *(Claude can suggest numbers to try.)*
3. The multiplayer questions above.
4. Where is the dump: outside the mine entrance, or at the end of the rails?
