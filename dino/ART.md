# Art spec and generation prompts

What the real sprites need to be so they drop into the game, and prompts for generating them (ChatGPT, Gemini,
Midjourney, whatever you use). The game animates by moving parts, so **no walk cycles or frame sheets**: each
dinosaur is a few separate pieces in one neutral pose, and the game swings legs, opens jaws, flaps wings and
turns heads itself. Bites tear pixels out of a part, so each part must be its own picture.

## Rules every sprite follows

- **Side view, facing right**, standing on flat ground, neutral pose (standing, mouth shut, legs straight-ish).
- **Pixel art**, flat colours, no anti-aliasing, no gradients, no outlines thicker than 1 px, limited palette
  (6-10 colours per creature). Think SNES / Metal Slug detail at a small size.
- **Plain flat background** in one colour nobody uses (magenta or bright green) so it can be keyed out.
- **Each part separately**, each on its own picture, same scale, with a little empty space round it. Or one
  picture with the parts laid out apart from each other, not overlapping.
- Generators won't hit exact pixel sizes: generate big and crisp, and I shrink with nearest-neighbour and clean
  up by hand. Ask for "a 64x32 pixel sprite scaled up 8x" and you'll get something usable.
- Lighting from above, slightly in front. A lighter belly and a darker back works at this size.

## The parts

| creature | parts | about (in game pixels) |
|---|---|---|
| **You, Hatchling** | body (with tail and neck), head, lower jaw, 2 legs | 26 wide, 13 tall |
| **You, Raptor** | body, head, lower jaw, 2 legs | 52 x 26 body, 27 x 13 head |
| **You, Allosaur** | body, head, lower jaw, 2 legs | 68 x 34 body, longer deeper head |
| **You, Tyrant** | body, head, lower jaw, 2 legs | 104 x 52 body, big head |
| **Hunter** (a rival meat-eater, raptor-sized) | body, head, lower jaw, 2 legs | as the raptor |
| **Grazer** (big long-necked plant-eater) | body (with neck, head and tail), 4 legs | 98 x 42 |
| **Runner** (small quick plant-eater) | body, 2 legs | 36 x 18 |
| **Charger** (horned, frilled plant-eater) | body (with head, frill and horns), 4 legs | 96 x 40 |
| **Pterodactyl** | body (with head, crest and beak), 2 wings | 44 x 16 body, 34 x 11 wing |

Legs: a thigh, shin and foot in one piece, hanging straight down, hip at the top. Two of the same for two-legged
ones (I darken the far one), four for four-legged. Jaws: the lower jaw as its own piece, hinge at the back.

## What I make from your sprites

- The **zone map** (which pixel is head, neck, body, tail, leg, wing), painted from the finished sprite.
- The **insides** (the dark red wound rim, flesh, the odd fleck of bone) the game paints when a chunk comes out.
- The far-side legs (darkened copies) and the **four forms' sizes**.
So the only thing to generate is the outside of each creature.

## Prompts

Paste the style block first, then one creature block. Change the words in brackets to taste.

### Style block (use with every prompt)

> Pixel art sprite of a dinosaur for a 16-bit side-scrolling game. Side view, facing right, standing on flat
> ground in a neutral pose with its mouth closed. Flat colours, no anti-aliasing, no gradients, 1-pixel dark
> outline, a palette of about 8 colours, lighter belly, darker back, small highlights on the top edges. Plain
> flat bright magenta background. Crisp pixels, scaled up 8x. Draw the body (with tail and neck), the head,
> the lower jaw, and one leg (hip to toes, hanging straight down) as SEPARATE pieces laid out side by side with
> gaps between them, all at the same scale, so they can be cut apart.

### You, four forms

- **Hatchling**: > A tiny newly hatched meat-eating dinosaur, compsognathus-like: big eyes, a slightly
  oversized head, thin legs, a long thin tail, soft sandy-tan scales with a pale cream belly and faint darker
  stripes down the back. Cute but with a row of needle teeth. About 26 by 13 pixels of game sprite.
- **Raptor**: > A velociraptor-style predator: lean and fast, a long stiff tail held out straight, strong legs
  with a raised sickle claw on each foot, a narrow head with a long snout full of teeth, two-tone olive green
  with a cream belly and dark green stripes across the back. About 52 by 26 pixels of game sprite.
- **Allosaur**: > An allosaurus-style predator: heavier than a raptor, deep chest, thick tail, a big deep
  head with a long toothy snout and small brow ridges, short arms, earthy brown with a tan belly and dark
  brown markings. About 68 by 34 pixels of game sprite.
- **Tyrant**: > A tyrannosaurus rex: massive, a huge deep skull with big teeth, thick neck, tiny two-fingered
  arms, powerful legs, a heavy tail, dark charcoal-grey scales with a dusty red-brown belly and black bands.
  Menacing. About 104 by 52 pixels of game sprite.

### The others

- **Hunter** (a rival that attacks you): > A rival raptor-sized predator, the same build as a velociraptor but
  in rust red and dark maroon with a pale orange belly, a mean narrow eye, teeth showing a little. About 52 by
  26 pixels of game sprite.
- **Grazer**: > A large long-necked plant-eating dinosaur, a small brachiosaurus-like sauropod: a barrel body,
  a long neck rising to a small head with a calm eye, a long tapering tail, four stout legs, mustard yellow
  with a pale belly and olive stripes. Draw the body with neck, head and tail as ONE piece, and one leg as a
  separate piece. About 98 by 42 pixels of game sprite.
- **Runner**: > A small two-legged plant-eating dinosaur, hypsilophodon-like: slim, built for speed, a small
  beaked head, big eye, long balancing tail, sandy brown with a cream belly. Draw the body (with head, neck
  and tail) as one piece and one leg separately. About 36 by 18 pixels of game sprite.
- **Charger**: > A triceratops: a huge low head with a bony frill, two long brow horns and a short nose horn,
  a beak, a heavy barrel body, four thick legs, a short thick tail, slate grey-blue with a pale belly and the
  frill rimmed in bone. Draw the body with head, frill and horns as ONE piece, and one leg separately. About
  96 by 40 pixels of game sprite.
- **Pterodactyl**: > A pteranodon in flight seen from the side: a small body, a long thin beak, a backswept
  head crest, a short tail, dusky mauve-brown with a pale pink-cream belly. Draw the body (with head and
  crest) as one piece, and ONE wing (fully spread, root at the shoulder) as a separate piece. About 44 by 16
  pixels of game sprite for the body and 34 by 11 for the wing.

### Optional extras (nice, not needed)

- **Open-mouth head** for each meat-eater: the same head with the jaw dropped, for reference when I cut the jaw.
- **A dead pose** isn't needed: the game slumps the body itself.
- **Scenery** later: palms, ferns, rocks, a signpost, hills, in the same style. Not yet.

## Hand-over

Put the pictures in `dino/art/raw/` named like `raptor_body.png`, `raptor_head.png`, `raptor_jaw.png`,
`raptor_leg.png`, `grazer_body.png`, `grazer_leg.png`, `flyer_body.png`, `flyer_wing.png`. One creature at a time
is fine: I'll fit it in, show you it running, and we adjust before doing the next.
