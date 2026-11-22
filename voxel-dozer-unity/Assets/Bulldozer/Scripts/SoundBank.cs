// Every sound in the game.  There are no sound files yet: each one is made in code the first time it is wanted.
//
// To use a recorded sound instead, put the file in Assets/Resources/Sounds/ with the sound's name (for example
// Assets/Resources/Sounds/engine.wav).  Get() always looks for a file first and only makes the sound when there isn't one.
// Several takes of a one-shot can be given as name_0, name_1 ...: Get() picks one at random each time.
// Loops (marked below) should be recorded so they loop cleanly.
// The owner's recordings (art/bulldozer-vox/sounds, made with ElevenLabs) are cut into these by make_sounds.py.
//
//   Dozer        engine (loop)  engine_lug (loop: labouring)  tracks (loop)  dirt (loop: blade pushing)
//                hydraulic (loop)  ripper (loop)  clunk (hard rock)
//   Rifle        rifle (a shot)
//   On foot      pick_rock  pick_dirt  pick_gold  shovel_scrape  shovel_whump  jackhammer (loop)  vacuum (loop)
//                gravel (loop: stones up the hose)  step  step_mine
//   Cart / money cart_roll (loop)  motor (loop)  tip_rumble (loop)  kaching  upgrade  goal  gold (into the gold store)
//   Ambience     wind (loop)  bird0 bird1 bird2  mine_hum (loop)  drip  creak
using System.Collections.Generic;
using UnityEngine;

public static class SoundBank
{
    public const int Rate = 44100;
    static readonly Dictionary<string, AudioClip[]> clips = new Dictionary<string, AudioClip[]>();
    static readonly HashSet<string> recorded = new HashSet<string>();
    static System.Random rng = new System.Random(7);

    /// The sound with this name: a recorded file from Resources/Sounds if there is one (one of its takes, at random,
    /// when there are several), otherwise made here (once).
    public static AudioClip Get(string name)
    {
        AudioClip[] c;
        if (!clips.TryGetValue(name, out c) || c == null || c.Length == 0 || c[0] == null)
        {
            c = Load(name);
            clips[name] = c;
        }
        return c.Length == 1 ? c[0] : c[Random.Range(0, c.Length)];
    }

    /// True if the game plays a recording for this sound (not one made in code).
    public static bool IsRecorded(string name) { Get(name); return recorded.Contains(name); }
    public static int RecordedCount { get { return recorded.Count; } }

    static AudioClip[] Load(string name)
    {
        var one = Resources.Load<AudioClip>("Sounds/" + name);
        if (one != null) { recorded.Add(name); return new[] { one }; }
        var takes = new List<AudioClip>();
        for (int i = 0; i < 32; i++)
        {
            var t = Resources.Load<AudioClip>("Sounds/" + name + "_" + i);
            if (t == null) break;
            takes.Add(t);
        }
        if (takes.Count > 0) { recorded.Add(name); return takes.ToArray(); }
        rng = new System.Random(name.GetHashCode() & 0x7fffffff);
        float[] s = Make(name);
        if (s == null) { Debug.LogWarning("No sound called " + name); s = new float[64]; }
        var c = AudioClip.Create(name, s.Length, 1, Rate, false);
        c.SetData(s, 0);
        return new[] { c };
    }

    /// Makes every sound now (at the start, so none is made in the middle of play).
    public static void MakeAll()
    {
        foreach (var n in Names) Get(n);
    }

    public static readonly string[] Names =
    {
        "engine", "engine_lug", "tracks", "dirt", "hydraulic", "ripper", "clunk",
        "pick_rock", "pick_dirt", "pick_gold", "shovel_scrape", "shovel_whump", "jackhammer", "vacuum", "gravel", "step", "step_mine",
        "cart_roll", "motor", "tip_rumble", "kaching", "upgrade", "goal", "gold", "rifle",
        "wind", "bird0", "bird1", "bird2", "mine_hum", "drip", "creak",
    };

    // ------------------------------------------------------------------ the recipes
    const float Tail = 0.2f;                                  // loops are made this much long, then folded back on themselves

    static float[] Make(string name)
    {
        float[] b;
        switch (name)
        {
            // ---- the dozer
            case "engine":                                    // a big diesel at idle: 30 firings a second
                b = Buf(2f + Tail);
                for (int i = 0; i * (1f / 30f) < 2f + Tail; i++)
                {
                    float at = i / 30f, a = 0.8f + 0.2f * U();
                    Tone(b, at, 72f, a, 0.020f); Tone(b, at, 144f, 0.35f * a, 0.010f); Tone(b, at, 290f, 0.12f * a, 0.006f);
                    Noise(b, at, 0.55f * a, 0.009f, 0.25f);
                }
                Rumble(b, 0.12f, 0.02f);
                LowPass(b, 0.3f);
                return Loop(b, 0.8f);
            case "engine_lug":                                // labouring: slower, lumpier, deeper
                b = Buf(2f + Tail);
                for (int i = 0; i * (1f / 22f) < 2f + Tail; i++)
                {
                    float at = i / 22f + 0.004f * R(), a = 0.45f + 0.75f * U();
                    Tone(b, at, 52f, a, 0.035f); Tone(b, at, 104f, 0.45f * a, 0.016f);
                    Noise(b, at, 0.9f * a, 0.014f, 0.15f);
                }
                Rumble(b, 0.3f, 0.012f);
                LowPass(b, 0.22f);
                return Loop(b, 0.85f);
            case "tracks":                                    // steel track plates: 8 clanks a second at pitch 1
                b = Buf(1f + Tail);
                for (int i = 0; i * 0.125f < 1f + Tail; i++)
                {
                    float at = i * 0.125f + 0.006f * R(), a = 0.6f + 0.4f * U();
                    Tone(b, at, 430f + 30f * R(), 0.5f * a, 0.025f); Tone(b, at, 1130f, 0.3f * a, 0.014f); Tone(b, at, 2300f, 0.15f * a, 0.007f);
                    Noise(b, at, 0.45f * a, 0.004f, 0.6f);
                    Tone(b, at + 0.06f, 610f, 0.15f * a, 0.012f);               // the rattle of the next plate
                }
                Rumble(b, 0.08f, 0.03f);
                return Loop(b, 0.7f);
            case "dirt":                                      // a heap rolling in front of the blade
                b = Buf(2f + Tail);
                Rumble(b, 0.8f, 0.02f);
                for (int i = 0; i < 220; i++) Noise(b, U() * (2f + Tail), 0.15f + 0.25f * U(), 0.008f, 0.3f);
                LowPass(b, 0.35f);
                return Loop(b, 0.8f);
            case "hydraulic":                                 // the pump whining while a ram moves
                b = Buf(1f + Tail);
                for (int i = 0; i < b.Length; i++)
                {
                    float t = (float)i / Rate, w = 0.85f + 0.15f * Mathf.Sin(2f * Mathf.PI * 3f * t);
                    b[i] = w * (0.5f * Sin(340f, t) + 0.22f * Sin(680f, t) + 0.1f * Sin(1020f, t) + 0.06f * Sin(1700f, t)) + 0.05f * R();
                }
                LowPass(b, 0.5f);
                return Loop(b, 0.5f);
            case "ripper":                                    // a shank tearing through ground and rock
                b = Buf(1.5f + Tail);
                Rumble(b, 0.5f, 0.05f);
                for (int i = 0; i < 160; i++)
                {
                    float at = U() * (1.5f + Tail);
                    Noise(b, at, 0.4f + 0.6f * U(), 0.006f, 0.7f);
                    if (U() < 0.3f) Tone(b, at, 250f + 400f * U(), 0.2f, 0.02f);
                }
                LowPass(b, 0.4f);
                return Loop(b, 0.8f);
            case "clunk":                                     // the blade hitting hard rock
                b = Buf(0.7f);
                Tone(b, 0f, 55f, 1f, 0.09f); Tone(b, 0f, 140f, 0.5f, 0.05f); Tone(b, 0f, 310f, 0.35f, 0.08f); Tone(b, 0f, 740f, 0.25f, 0.05f);
                Tone(b, 0f, 1630f, 0.12f, 0.03f);
                Noise(b, 0f, 0.8f, 0.02f, 0.4f);
                return Shot(b, 0.95f);

            // ---- on foot
            case "rifle":                                     // a sharp crack with a short low thump under it
                b = Buf(0.35f);
                Noise(b, 0f, 1.0f, 0.012f, 0.95f); Noise(b, 0.002f, 0.6f, 0.05f, 0.25f);
                Tone(b, 0f, 120f, 0.6f, 0.04f); Tone(b, 0f, 70f, 0.4f, 0.07f);
                return Shot(b, 0.9f);
            case "pick_rock":                                 // clink
                b = Buf(0.45f);
                Tone(b, 0f, 2150f, 0.6f, 0.07f); Tone(b, 0f, 3340f, 0.4f, 0.05f); Tone(b, 0f, 5200f, 0.2f, 0.03f); Tone(b, 0f, 1250f, 0.3f, 0.04f);
                Noise(b, 0f, 0.7f, 0.003f, 0.9f);
                return Shot(b, 0.8f);
            case "pick_dirt":                                 // thud
                b = Buf(0.3f);
                Tone(b, 0f, 95f, 0.9f, 0.05f); Tone(b, 0f, 190f, 0.3f, 0.02f);
                Noise(b, 0f, 0.7f, 0.025f, 0.12f);
                for (int i = 0; i < 6; i++) Noise(b, 0.02f + 0.1f * U(), 0.15f, 0.004f, 0.5f);
                return Shot(b, 0.85f);
            case "pick_gold":                                 // ting
                b = Buf(1.1f);
                Tone(b, 0f, 2637f, 0.6f, 0.35f); Tone(b, 0f, 5274f, 0.2f, 0.2f); Tone(b, 0f, 3951f, 0.15f, 0.25f);
                Tone(b, 0f, 2150f, 0.25f, 0.05f);
                Noise(b, 0f, 0.4f, 0.003f, 0.9f);
                return Shot(b, 0.8f);
            case "shovel_scrape":                             // the blade of the shovel going in
                b = Buf(0.4f);
                for (int i = 0; i < b.Length; i++)
                {
                    float t = (float)i / Rate, env = Mathf.Clamp01(t / 0.08f) * Mathf.Exp(-Mathf.Max(0f, t - 0.08f) / 0.08f);
                    b[i] = env * R() * (0.6f + 0.4f * Mathf.Sin(t * 260f));
                }
                Band(b, 0.5f, 0.05f);
                for (int i = 0; i < 10; i++) Noise(b, 0.03f + 0.2f * U(), 0.2f, 0.003f, 0.7f);
                return Shot(b, 0.7f);
            case "shovel_whump":                              // a shovelful landing
                b = Buf(0.45f);
                Tone(b, 0f, 70f, 0.8f, 0.06f);
                Noise(b, 0f, 0.7f, 0.05f, 0.08f);
                for (int i = 0; i < 14; i++) Noise(b, 0.01f + 0.15f * U(), 0.12f + 0.12f * U(), 0.004f, 0.6f);
                return Shot(b, 0.8f);
            case "jackhammer":                                // 25 blows a second
                b = Buf(0.48f + Tail);
                for (int i = 0; i * 0.04f < 0.48f + Tail; i++)
                {
                    float at = i * 0.04f, a = 0.8f + 0.2f * U();
                    Tone(b, at, 950f, 0.5f * a, 0.006f); Tone(b, at, 2400f, 0.3f * a, 0.004f); Tone(b, at, 130f, 0.6f * a, 0.012f);
                    Noise(b, at, 0.7f * a, 0.004f, 0.7f);
                }
                Rumble(b, 0.1f, 0.05f);
                return Loop(b, 0.75f);
            case "vacuum":                                    // the backpack sucking
                b = Buf(2f + Tail);
                for (int i = 0; i < b.Length; i++)
                {
                    float t = (float)i / Rate;
                    b[i] = R() * (0.8f + 0.2f * Mathf.Sin(2f * Mathf.PI * t)) + 0.08f * Sin(233f, t) + 0.04f * Sin(466f, t);
                }
                Band(b, 0.55f, 0.04f);
                return Loop(b, 0.6f);
            case "gravel":                                    // stones rattling up the hose
                b = Buf(1f + Tail);
                for (int i = 0; i < 170; i++)
                {
                    float at = U() * (1f + Tail);
                    Noise(b, at, 0.3f + 0.7f * U(), 0.002f, 0.8f);
                    Tone(b, at, 2500f + 3500f * U(), 0.2f, 0.003f);
                }
                return Loop(b, 0.6f);
            case "step":
                b = Buf(0.25f);
                Footstep(b, 0f, 1f);
                return Shot(b, 0.6f);
            case "step_mine":                                 // the same, echoing off the tunnel
                b = Buf(0.75f);
                Footstep(b, 0f, 1f);
                Footstep(b, 0.09f, 0.42f); Footstep(b, 0.17f, 0.28f); Footstep(b, 0.26f, 0.17f); Footstep(b, 0.37f, 0.1f); Footstep(b, 0.5f, 0.05f);
                LowPass(b, 0.6f);
                return Shot(b, 0.6f);

            // ---- the cart, the money
            case "cart_roll":                                 // wheels rolling, a clack-clack at each rail joint
                b = Buf(2f + Tail);
                Rumble(b, 0.35f, 0.03f);
                for (int i = 0; i < b.Length; i++) b[i] += 0.04f * Sin(180f, (float)i / Rate);
                for (int i = 0; i < 3; i++)
                    foreach (float o in new[] { 0f, 0.13f })
                    {
                        float at = i * 1f + o;
                        Tone(b, at, 800f, 0.5f, 0.02f); Tone(b, at, 1900f, 0.3f, 0.01f); Tone(b, at, 260f, 0.4f, 0.03f);
                        Noise(b, at, 0.6f, 0.004f, 0.7f);
                    }
                return Loop(b, 0.7f);
            case "motor":                                     // the motor cart's little engine putting along: 12 a second
                b = Buf(1f + Tail);
                for (int i = 0; i * (1f / 12f) < 1f + Tail; i++)
                {
                    float at = i / 12f, a = 0.7f + 0.3f * U();
                    Tone(b, at, 95f, 0.8f * a, 0.02f); Tone(b, at, 190f, 0.3f * a, 0.01f);
                    Noise(b, at, 0.6f * a, 0.01f, 0.3f);
                }
                LowPass(b, 0.4f);
                return Loop(b, 0.75f);
            case "tip_rumble":                                // a load pouring out
                b = Buf(2f + Tail);
                Rumble(b, 1f, 0.015f);
                for (int i = 0; i < 300; i++) Noise(b, U() * (2f + Tail), 0.2f + 0.3f * U(), 0.004f, 0.6f);
                return Loop(b, 0.85f);
            case "kaching":                                   // money in
                b = Buf(1.3f);
                Noise(b, 0f, 0.8f, 0.01f, 0.7f); Tone(b, 0f, 1200f, 0.3f, 0.01f);
                Tone(b, 0.07f, 2093f, 0.45f, 0.4f); Tone(b, 0.07f, 2637f, 0.4f, 0.35f); Tone(b, 0.07f, 3136f, 0.3f, 0.3f); Tone(b, 0.07f, 4186f, 0.15f, 0.2f);
                return Shot(b, 0.7f);
            case "upgrade":                                   // a part bolted on
                b = Buf(0.7f);
                Tone(b, 0f, 80f, 0.8f, 0.07f); Tone(b, 0f, 200f, 0.4f, 0.05f); Noise(b, 0f, 0.6f, 0.02f, 0.35f);
                foreach (float at in new[] { 0.16f, 0.21f, 0.26f, 0.31f }) { Tone(b, at, 1500f, 0.3f, 0.006f); Noise(b, at, 0.3f, 0.002f, 0.8f); }
                Tone(b, 0.36f, 520f, 0.4f, 0.12f); Tone(b, 0.36f, 1040f, 0.2f, 0.08f);
                return Shot(b, 0.8f);
            case "gold":                                      // gold into the gold store: a quick rising sparkle over a soft bell
                b = Buf(1.4f);
                Tone(b, 0f, 523f, 0.35f, 0.6f); Tone(b, 0f, 1046f, 0.15f, 0.5f);
                {
                    float[] up = { 1568f, 1976f, 2349f, 3136f, 3951f, 4699f };
                    for (int k = 0; k < up.Length; k++) { Tone(b, 0.05f + k * 0.055f, up[k], 0.32f - k * 0.03f, 0.25f); Noise(b, 0.05f + k * 0.055f, 0.08f, 0.002f, 0.95f); }
                }
                return Shot(b, 0.6f);
            case "goal":                                      // a goal done: two bright notes
                b = Buf(1.1f);
                Tone(b, 0f, 784f, 0.5f, 0.3f); Tone(b, 0f, 1568f, 0.12f, 0.2f);
                Tone(b, 0.13f, 1047f, 0.5f, 0.45f); Tone(b, 0.13f, 2094f, 0.12f, 0.3f);
                return Shot(b, 0.65f);

            // ---- the ambience
            case "wind":
                b = Buf(6f + Tail);
                for (int i = 0; i < b.Length; i++) b[i] = R();
                LowPass(b, 0.02f); LowPass(b, 0.05f);
                for (int i = 0; i < b.Length; i++)
                {
                    float t = (float)i / Rate;
                    b[i] *= 0.6f + 0.3f * Mathf.Sin(2f * Mathf.PI * t / 6f) + 0.15f * Mathf.Sin(2f * Mathf.PI * t / 3f + 1f);
                }
                return Loop(b, 0.8f);
            case "bird0": case "bird1": case "bird2":
                b = Buf(0.7f);
                int notes = 2 + (name[4] - '0');
                float f0 = 2600f + 1400f * U(), at0 = 0f;
                for (int k = 0; k < notes; k++)
                {
                    float len = 0.05f + 0.05f * U(), f1 = f0 * (0.8f + 0.5f * U());
                    Chirp(b, at0, len, f0, f1, 0.6f);
                    at0 += len + 0.03f + 0.06f * U();
                    f0 = f1 * (0.9f + 0.2f * U());
                }
                return Shot(b, 0.5f);
            case "mine_hum":
                b = Buf(4f + Tail);
                Rumble(b, 0.5f, 0.008f);
                for (int i = 0; i < b.Length; i++) { float t = (float)i / Rate; b[i] += 0.12f * Sin(50f, t) + 0.06f * Sin(100f, t) + 0.03f * Sin(150f, t); }
                return Loop(b, 0.6f);
            case "drip":
                b = Buf(0.55f);
                Chirp(b, 0f, 0.035f, 900f, 1900f, 0.7f);
                Chirp(b, 0.12f, 0.035f, 900f, 1900f, 0.22f);
                Chirp(b, 0.25f, 0.035f, 900f, 1900f, 0.08f);
                return Shot(b, 0.6f);
            case "creak":                                     // an old prop groaning: wood sticking and slipping
                b = Buf(1.2f);
                for (float t = 0.05f; t < 0.95f; )
                {
                    float env = Mathf.Sin(Mathf.PI * (t - 0.05f) / 0.9f);
                    Tone(b, t, 300f + 200f * env, 0.5f * env, 0.004f);
                    Noise(b, t, 0.3f * env, 0.002f, 0.5f);
                    t += 0.004f + 0.008f * (1f - env) + 0.002f * U();
                }
                LowPass(b, 0.5f);
                return Shot(b, 0.6f);
        }
        return null;
    }

    // ------------------------------------------------------------------ the building blocks
    static float U() { return (float)rng.NextDouble(); }
    static float R() { return (float)rng.NextDouble() * 2f - 1f; }
    static float Sin(float f, float t) { return Mathf.Sin(2f * Mathf.PI * f * t); }
    static float[] Buf(float seconds) { return new float[Mathf.CeilToInt(seconds * Rate)]; }

    /// A note that starts at `at` (seconds) and dies away (decay: seconds to fall to about a third).
    static void Tone(float[] b, float at, float freq, float amp, float decay)
    {
        int s = (int)(at * Rate), n = Mathf.Min(b.Length - s, (int)(decay * 8f * Rate));
        if (s < 0) return;
        for (int i = 0; i < n; i++) { float t = (float)i / Rate; b[s + i] += amp * Mathf.Exp(-t / decay) * Mathf.Sin(2f * Mathf.PI * freq * t); }
    }

    /// A burst of noise that dies away; lp (0..1) is how bright it is (1 = all of it, small = dull).
    static void Noise(float[] b, float at, float amp, float decay, float lp)
    {
        int s = (int)(at * Rate), n = Mathf.Min(b.Length - s, (int)(decay * 8f * Rate));
        if (s < 0) return;
        float y = 0f;
        for (int i = 0; i < n; i++) { float t = (float)i / Rate; y += lp * (R() - y); b[s + i] += amp * Mathf.Exp(-t / decay) * y * (1f + (1f - lp) * 2f); }
    }

    /// Low rumbling noise all the way through (brown-ish: lp small = deeper).
    static void Rumble(float[] b, float amp, float lp)
    {
        float y = 0f, y2 = 0f;
        for (int i = 0; i < b.Length; i++) { y += lp * (R() - y); y2 += lp * (y - y2); b[i] += amp * y2 * (3f / Mathf.Sqrt(lp + 0.001f)) * 0.15f; }
    }

    /// A whistle sliding from f0 to f1, shaped like a little hump.
    static void Chirp(float[] b, float at, float len, float f0, float f1, float amp)
    {
        int s = (int)(at * Rate), n = Mathf.Min(b.Length - s, (int)(len * Rate));
        float ph = 0f;
        for (int i = 0; i < n; i++)
        {
            float k = (float)i / n;
            ph += 2f * Mathf.PI * Mathf.Lerp(f0, f1, k) / Rate;
            b[s + i] += amp * Mathf.Sin(Mathf.PI * k) * Mathf.Sin(ph);
        }
    }

    static void Footstep(float[] b, float at, float a)
    {
        Noise(b, at, 0.8f * a, 0.02f, 0.15f);
        Tone(b, at, 80f, 0.4f * a, 0.03f);
        for (int i = 0; i < 3; i++) Noise(b, at + 0.005f + 0.03f * U(), 0.15f * a, 0.003f, 0.6f);
    }

    static void LowPass(float[] b, float k)
    {
        float y = b[0];
        for (int i = 0; i < b.Length; i++) { y += k * (b[i] - y); b[i] = y; }
    }

    /// Keeps the middle of the sound: brighter than lo, duller than hi.
    static void Band(float[] b, float hi, float lo)
    {
        float y = 0f, z = 0f;
        for (int i = 0; i < b.Length; i++) { y += hi * (b[i] - y); z += lo * (y - z); b[i] = y - z; }
    }

    static void Normalize(float[] b, float peak)
    {
        float m = 1e-6f;
        for (int i = 0; i < b.Length; i++) m = Mathf.Max(m, Mathf.Abs(b[i]));
        float k = peak / m;
        for (int i = 0; i < b.Length; i++) b[i] *= k;
    }

    /// A one-shot: as loud as asked, with no click at either end.
    static float[] Shot(float[] b, float peak)
    {
        Normalize(b, peak);
        int f = Mathf.Min(b.Length / 4, Rate / 50);
        for (int i = 0; i < f; i++) b[b.Length - 1 - i] *= (float)i / f;
        return b;
    }

    /// A loop: the extra Tail at the end is faded into the start, so it goes round with no join to hear.
    static float[] Loop(float[] b, float peak)
    {
        int f = (int)(Tail * Rate), n = b.Length - f;
        var o = new float[n];
        System.Array.Copy(b, o, n);
        for (int i = 0; i < f; i++) { float k = (float)i / f; o[i] = b[i] * k + b[n + i] * (1f - k); }
        Normalize(o, peak);
        return o;
    }
}
