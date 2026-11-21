# A rough pace model for the Digger Game's upgrade ladder (a read-through, not a voxel simulation).
# python pace_model.py  prints when a greedy player would buy each upgrade, with the prices in P below
# (kept by hand in step with Upgrades.cs: the 22 Nov 2026 tuning).  Assumptions: cave-in 1 is about 22 m3 and
# cave-in 2 about 33 m3 (from GoalsTest), gold only past cave-in 2, a real player about 2.2x slower than the
# shovel animation, 12 s of handling per cart load.  Treat the minutes as rough; the shape is what matters.
# A "greedy" player always buys the cheapest useful upgrade they can afford, and digs in between.
# Income is modelled from the real numbers in Upgrades.cs / Worker.cs / MineCart.cs, with a human slow-down factor.
import sys, json

L_PER_VOX = 1000.0 / 4096           # litres per voxel
COIN_PER_L = 0.1
GOLD_COIN_PER_L = COIN_PER_L * 50

def steps(prices):
    return prices

PRICES = json.loads(sys.argv[1]) if len(sys.argv) > 1 else None

# (name, coins, gold litres) per branch, in order; from Upgrades.cs
P = PRICES or {
  "pick":  [("Pick 2",60,0),("Pick 3",110,0),("Pick 4",190,0),("Pick 5",320,0),("Jackhammer",600,8),("Jackhammer 2",260,0),("Jackhammer 3",420,0),("Jackhammer 4",670,0),("Jackhammer 5",1070,0)],
  "shovel":[("Shovel 2",40,0),("Shovel 3",75,0),("Shovel 4",135,0),("Shovel 5",230,0),("Shovel 6",380,0)],
  "pack":  [("Backpack",400,5),("Backpack 2",150,0),("Backpack 3",240,0),("Backpack 4",384,0),("Backpack 5",614,0),("Backpack 6",983,0),("Backpack 7",1400,0),("Backpack 8",1900,0)],
  "cart":  [("Cart 2",450,0),("Motor cart",800,0),("Motor cart 2",400,0),("Motor cart 3",640,0),("Bigger cart",900,0),("Automatic cart",1200,20)],
}
SHOVEL_HOLDS = [480,640,800,980,1180,1400]
SHOVEL_SPEED = [1.0,1.1,1.2,1.3,1.45,1.6]
PACK_RATE = [1.0,1.4,1.8,2.2,2.6,3.0,3.5,4.0]
CART_L = [1000,1500,1500,1500,1500,2000,2000]
MOTOR = [0,0,3,4,5,5,5]
SLOW = 2.2            # a real player's cycle vs the animation's (aiming, walking a step, missed scoops)
OVERHEAD = 12.0       # seconds per load: grab, line up, tip, let go
GOLD_SHARE = [0.0, 0.0, 0.004, 0.006, 0.008]   # share of a load that is gold, by depth stage (0 = cave-in 1 .. 4 = far chamber)

def income(lv, stage):
    """coins a minute and gold litres a minute, for these levels at this depth stage"""
    sh = lv["shovel"]; c = lv["cart"]; pk = lv["pack"]; pi = lv["pick"]
    scoop = SHOVEL_HOLDS[sh] * L_PER_VOX
    cyc = (0.36 + 0.42) / SHOVEL_SPEED[sh] * SLOW
    shovel_lps = scoop / cyc
    if pk > 0:
        pack_lps = 32 * PACK_RATE[pk - 1] * 0.55      # sucking, minus the squirting back out
        shovel_lps = max(shovel_lps, pack_lps)
    # deeper stages are firmer: the pick (or jackhammer) has to break it first, which slows the loading
    hard = [0.0, 0.25, 0.45, 0.6, 0.7][stage]
    break_lps = (40 + 25 * min(pi, 4)) if pi < 5 else (110 + 30 * (pi - 5))
    lps = 1.0 / ((1 - hard) / shovel_lps + hard * (1 / shovel_lps + 1 / break_lps))
    cartL = CART_L[c]
    fill = cartL / lps
    dist = [16, 24, 34, 40, 44][stage]     # face to the dump, metres
    speed = MOTOR[c] or 2.0
    auto = c >= 6
    travel = 0 if auto else 2 * dist / speed
    t = fill + travel + (4 if auto else OVERHEAD)
    gold_l = cartL * GOLD_SHARE[stage]
    return (cartL * (1 - GOLD_SHARE[stage]) * COIN_PER_L) / t * 60, gold_l / t * 60

def run(verbose=True):
    lv = {"pick": 0, "shovel": 0, "pack": 0, "cart": 0}
    idx = {"pick": 0, "shovel": 0, "pack": 0, "cart": 0}
    coins = 0.0; gold = 0.0; t = 0.0; dug_m3 = 0.0
    log = []
    while True:
        stage = 0 if dug_m3 < 22 else 1 if dug_m3 < 55 else 2 if dug_m3 < 80 else 3 if dug_m3 < 110 else 4
        # the next thing to buy: the cheapest available (the backpack only after Shovel 6)
        opts = []
        for b in P:
            i = idx[b]
            if i >= len(P[b]): continue
            if b == "pack" and idx["shovel"] < len(P["shovel"]): continue
            name, cost, g = P[b][i]
            if g > 0 and stage < 2 and any(P[bb][idx[bb]][2] == 0 for bb in P if idx[bb] < len(P[bb]) and not (bb == 'pack' and idx['shovel'] < len(P['shovel']))): continue
            opts.append((cost + g * GOLD_COIN_PER_L, b, name, cost, g))
        if not opts: break
        opts.sort()
        _, b, name, cost, g = opts[0]
        cpm, gpm = income(lv, stage)
        # wait until affordable; gold needed is dug alongside
        need_c = max(0.0, cost - coins) / cpm
        need_g = max(0.0, g - gold) / gpm if g > gold and gpm > 0 else (0 if g <= gold else 1e9)
        wait = max(need_c, need_g) * 60
        if wait > 1e7:
            log.append((t, name, ""))
            # dig until the gold stage
            idle = 0.0
            while stage < 2:
                t += 10; idle += 10; coins += cpm / 6; dug_m3 += cpm / 6 / COIN_PER_L / 1000
                stage = 0 if dug_m3 < 22 else 1 if dug_m3 < 55 else 2
                cpm, gpm = income(lv, stage)
            log[-1] = (t, name, "nothing to buy for %.1f min (needs gold; banked %d coins)" % (idle / 60, coins))
            continue
        t += wait
        coins += cpm * wait / 60 - cost
        gold += gpm * wait / 60 - g
        dug_m3 += cpm * wait / 60 / COIN_PER_L / 1000
        idx[b] += 1
        lv[b] += 1
        log.append((t, name, "%5.0f coins/min at stage %d, waited %4.0f s" % (cpm, stage, wait)))
    if verbose:
        prev = 0
        for (tt, n, why) in log:
            print("%6.1f min  (+%4.1f)  %-15s %s" % (tt / 60, (tt - prev) / 60, n, why))
            prev = tt
    return log

if __name__ == "__main__":
    run()
