import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from sfx import *
"""The dig mode's sounds (scripts/voxel/mine), made from noise and tones like sfx.py's:
    python3 -I godot/assets/voxel/tools/sfx_mine.py
writes godot/assets/voxel/sound/: mine_drill (the drill's grinding whine, looped; the game pitches it by how hard the
rock is), mine_engine (the ship's motor and thrusters, looped), mine_clink (ore into the hold), mine_hit (the hull
taking a knock), mine_alarm (the low-fuel beeps), mine_register (the trader's till: ka-ching), mine_boom (dynamite, a
gas pocket), mine_siren (the cops, looped), mine_rat (a squeak), mine_roar (the rock worm), mine_door (the roller door
rattling up), mine_crumble (fool's gold, lost ore), mine_zap (the teleport), mine_lava (a hiss), mine_crunch_0..4\n(the drill biting off rock, played as it chews), mine_prop and mine_booster (the lift, looped), mine_squirt and
mine_clunk (unloading into the ore box), mine_suck and mine_spray (the water hose, looped), mine_steam (water on lava), mine_groan and mine_collapse (a cave-in), mine_splash. Owned by the voxel
session."""


def build():
    # the drill: a whine with grinding under it, wobbling with the bit's teeth
    secs = 1.0
    tt = t(secs)
    whine = tone(330 + 14 * np.sin(2 * np.pi * 9 * tt), secs, "saw") * 0.35 + tone(660 + 20 * np.sin(2 * np.pi * 9 * tt), secs) * 0.25
    grind = band(noise(secs), 300, 3500) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 18 * tt)))
    rumble = lowpass(noise(secs), 180) * 2.0
    save("mine_drill", mix(band(whine, 200, 4000), grind * 0.9, rumble * 0.6), peak=0.7, loop=True)
    # the engine: a low throb and a jet's hiss
    thr = lowpass(tone(55, secs, "square"), 400) * (0.7 + 0.3 * np.sin(2 * np.pi * 14 * tt))
    hiss = band(noise(secs), 600, 5000) * 0.35
    save("mine_engine", mix(thr * 0.9, hiss, lowpass(noise(secs), 120) * 1.2), peak=0.6, loop=True)
    # ore into the hold: a bright metallic clink and a little rattle
    c = mix(metal([1850, 2730, 4100], 0.4, 0.18) * 0.8, at(click(0.02, 3000, 0.003), 0.05) * 0.6, at(click(0.02, 2400, 0.003), 0.09) * 0.4)
    save("mine_clink", c, peak=0.75)
    # a knock on the hull: a thud and a clang
    n = int(0.45 * SR)
    thud = lowpass(noise(0.45), 260) * env(n, 0.002, 0.12, 5) * 3.0
    clang = metal([180, 410, 690, 1130], 0.45, 0.3) * 0.7
    save("mine_hit", mix(thud, clang), peak=0.85)
    # the low-fuel alarm: two beeps
    b = tone(880, 0.12, "square") * env(int(0.12 * SR), 0.002, 0.2, 1)
    save("mine_alarm", lowpass(mix(b, at(b, 0.2)), 3000), peak=0.5)
    # the till: a drawer and a bell
    drawer = band(noise(0.15), 400, 2500) * env(int(0.15 * SR), 0.005, 0.08, 4)
    bell = metal([2093, 2637, 3136, 4186], 1.0, 0.7)
    save("mine_register", mix(drawer * 0.7, at(bell, 0.08) * 0.8, at(click(0.03, 1500, 0.006), 0.0) * 0.5), peak=0.8)
    # a blast: a crack, a boom, rubble falling after
    n = int(1.6 * SR)
    boom = lowpass(noise(1.6), np.linspace(1800, 120, n)) * env(n, 0.002, 0.9, 4) * 3.0
    crack = band(noise(0.1), 800, 6000) * env(int(0.1 * SR), 0.0005, 0.05, 6)
    rubble = band(noise(1.6), 300, 2500) * (env(n, 0.3, 1.2, 3)) * 0.35
    save("mine_boom", mix(crack, boom, at(rubble, 0.1)), peak=0.95)
    # the siren: wee-woo
    secs = 1.6
    tt = t(secs)
    f = np.where((tt % 0.8) < 0.4, 960, 720)
    siren = band(tone(lowpass(f.astype(float), 40), secs, "saw"), 300, 3000)
    save("mine_siren", siren, peak=0.5, loop=True)
    # a rat's squeak
    n = int(0.18 * SR)
    sq = tone(np.linspace(2600, 3600, n) + 300 * np.sin(np.linspace(0, 40, n)), 0.18) * env(n, 0.01, 0.12, 2)
    save("mine_rat", sq, peak=0.5)
    # the worm's roar: a deep growl and a grinding through rock
    secs = 1.8
    tt = t(secs)
    n = int(secs * SR)
    growl = lowpass(tone(48 + 10 * np.sin(2 * np.pi * 3 * tt), secs, "saw") * (0.6 + 0.4 * band(noise(secs), 10, 40) * 8), 500)
    rasp = band(noise(secs), 120, 900) * 0.8
    e = np.clip(tt / 0.25, 0, 1) * np.exp(-1.6 * np.maximum(tt - 0.6, 0))
    save("mine_roar", mix(growl * 1.2, rasp) * e, peak=0.9)
    # the roller door going up: a rattle of slats
    secs = 1.1
    tt = t(secs)
    rattle = band(noise(secs), 500, 4000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 22 * tt))) * np.clip(1 - tt / secs, 0, 1)
    motor = lowpass(tone(90, secs, "saw"), 300) * 0.4
    save("mine_door", mix(rattle, motor, at(metal([300, 520], 0.3, 0.2), secs - 0.25) * 0.6), peak=0.7)
    # crumbling: dry grit falling
    n = int(0.6 * SR)
    save("mine_crumble", mix(band(noise(0.6), 400, 3000) * env(n, 0.01, 0.4, 3), lowpass(noise(0.6), 300) * env(n, 0.005, 0.2, 4) * 1.5), peak=0.6)
    # the teleport: a rising shimmer
    n = int(0.9 * SR)
    zap = tone(np.linspace(300, 2400, n), 0.9) * (0.5 + 0.5 * np.sin(np.linspace(0, 120, n))) * env(n, 0.05, 0.8, 2)
    save("mine_zap", mix(zap, band(noise(0.9), 2000, 8000) * env(n, 0.1, 0.6, 3) * 0.3), peak=0.6)
    # lava: a hiss and pops
    n = int(1.0 * SR)
    hs = band(noise(1.0), 1500, 7000) * env(n, 0.02, 0.8, 2)
    pops = mix(*[at(click(0.03, 900 + 200 * k, 0.01), 0.1 + k * 0.17) for k in range(5)])
    save("mine_lava", mix(hs * 0.7, pops), peak=0.6)

    # crunches: the drill biting off a bit of rock (several, played as it chews, pitched by how hard it is)
    for v in range(5):
        n = int(0.16 * SR)
        grit = band(noise(0.16), 300 + v * 80, 2800 + v * 300) * env(n, 0.001, 0.05 + v * 0.01, 5)
        pops = mix(*[at(click(0.012, 1200 + 400 * ((v + k) % 3), 0.003) * rng.uniform(0.4, 1.0), rng.uniform(0.0, 0.09)) for k in range(4)])
        thud = lowpass(noise(0.16), 220) * env(n, 0.001, 0.04, 6) * 1.6
        save("mine_crunch_%d" % v, mix(grit, pops * 0.8, thud), peak=0.7)

    # the propeller: whup-whup-whup, blade passes chopping a breathy roar (looped)
    secs = 1.0
    tt = t(secs)
    chop = 0.35 + 0.65 * np.abs(np.sin(np.pi * 12 * tt)) ** 3
    save("mine_prop", mix(lowpass(noise(secs), 500) * chop * 1.8, band(noise(secs), 300, 1500) * chop * 0.4,
                          lowpass(tone(48, secs, "square"), 200) * 0.3), peak=0.55, loop=True)
    # the boosters: a rocket's roar, crackling (looped)
    crack = mix(*[at(click(0.01, rng.uniform(800, 2400), 0.002) * rng.uniform(0.2, 0.7), rng.uniform(0, 0.97), secs) for k in range(40)])
    save("mine_booster", mix(lowpass(noise(secs), 700) * 2.0, band(noise(secs), 1000, 6000) * 0.5, crack * 0.6), peak=0.65, loop=True)
    # the hose squirting ore: a pneumatic shoop
    n = int(0.22 * SR)
    shoop = band(noise(0.22), 500, 3000) * env(n, 0.01, 0.12, 3) + tone(np.linspace(500, 180, n), 0.22) * env(n, 0.005, 0.1, 4) * 0.4
    save("mine_squirt", shoop, peak=0.6)
    # a nugget landing in the box: a hollow steel clunk
    n = int(0.3 * SR)
    save("mine_clunk", mix(metal([210, 470, 760], 0.3, 0.12) * 0.8, lowpass(noise(0.3), 300) * env(n, 0.001, 0.05, 6) * 1.5), peak=0.75)
    # the hose sucking water up: a gurgling slurp (looped)
    gurg = band(noise(secs), 200, 1200) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 7 * tt + 2 * np.sin(2 * np.pi * 3 * tt))))
    save("mine_suck", mix(gurg * 1.2, lowpass(noise(secs), 150) * 0.8), peak=0.55, loop=True)
    # spraying water: a hiss of spray (looped)
    save("mine_spray", mix(band(noise(secs), 2000, 9000) * 0.8, band(noise(secs), 400, 1500) * 0.3), peak=0.45, loop=True)
    # water on lava: a big steam hiss going to stone
    n = int(1.2 * SR)
    steam = band(noise(1.2), 1200, 8000) * env(n, 0.005, 0.9, 2)
    save("mine_steam", mix(steam, at(click(0.04, 400, 0.02), 0.0) * 0.8, lowpass(noise(1.2), 200) * env(n, 0.005, 0.3, 4)), peak=0.65)

    # a roof about to go: a low wooden-stony groan, creaks, grit trickling
    n = int(1.2 * SR)
    tt = t(1.2)
    groan = lowpass(tone(70 + 18 * np.sin(2 * np.pi * 1.3 * tt), 1.2, "saw"), 300) * env(n, 0.25, 0.9, 1.5)
    creaks = mix(*[at(band(noise(0.08), 600, 2400) * env(int(0.08 * SR), 0.005, 0.05, 3) * rng.uniform(0.4, 0.9), rng.uniform(0.1, 1.0), 1.2) for k in range(6)])
    grit = band(noise(1.2), 1500, 6000) * env(n, 0.3, 0.8, 2) * 0.25
    save("mine_groan", mix(groan * 1.2, creaks * 0.7, grit), peak=0.7)
    # the roof coming down: a crack, a roar of rock, rubble settling
    n = int(2.0 * SR)
    crack = at(click(0.05, 900, 0.02), 0.0) * 1.2
    roar = lowpass(noise(2.0), 260) * env(n, 0.02, 1.2, 2.5) * 3.0
    rub = band(noise(2.0), 400, 3500) * env(n, 0.1, 1.6, 2) * 0.6
    save("mine_collapse", mix(crack, roar, rub), peak=0.9)
    # into the water: a splash
    n = int(0.7 * SR)
    sp = band(noise(0.7), 300, 6000) * env(n, 0.005, 0.35, 3)
    plop = tone(np.linspace(260, 90, n), 0.7) * env(n, 0.002, 0.12, 5) * 0.6
    save("mine_splash", mix(sp, plop), peak=0.7)


if __name__ == "__main__":
    build()
