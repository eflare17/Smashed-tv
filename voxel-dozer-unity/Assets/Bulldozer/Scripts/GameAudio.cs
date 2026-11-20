// The sound: it plays what SoundBank makes.
//   Volumes: Master, Engine (the dozer's engine and tracks), Effects (everything else), set in Esc > Settings and
//   kept like the other settings.
//   One-shots: Play / PlayAt, from a small pool of sources.  Loops: a looping source whose volume and pitch follow
//   the game each frame (Loop).
//   This script looks after the worker (footsteps, jackhammer, backpack), the cart (rolling, motor, tipping) and the
//   ambience (wind and birds outside; a low hum, drips and creaking props in the mine).  The dozer has its own
//   (DozerAudio).  The pick, shovel, money and upgrades call Play at the moment it happens.
using UnityEngine;

public class GameAudio : MonoBehaviour
{
    public static GameAudio Instance { get; private set; }
    public static float Master = 0.8f, Engine = 0.8f, Effects = 0.8f;   // 0..1, Esc > Settings
    public static int Played { get; private set; }                    // one-shots started (for tests)

    public static void LoadPrefs()
    {
        Master = Mathf.Clamp01(PlayerPrefs.GetFloat("set.vol.master", 0.8f));
        Engine = Mathf.Clamp01(PlayerPrefs.GetFloat("set.vol.engine", 0.8f));
        Effects = Mathf.Clamp01(PlayerPrefs.GetFloat("set.vol.effects", 0.8f));
    }
    public static void SavePrefs()
    {
        PlayerPrefs.SetFloat("set.vol.master", Master);
        PlayerPrefs.SetFloat("set.vol.engine", Engine);
        PlayerPrefs.SetFloat("set.vol.effects", Effects);
    }

    // ---- one-shots
    const int PoolSize = 16;
    AudioSource[] pool;
    int next;

    /// Plays a sound once at a place in the world (it gets quieter with distance).
    public static void PlayAt(string name, Vector3 at, float volume = 1f, float pitch = 1f, float delay = 0f)
    {
        if (Instance == null) return;
        Instance.Shot(name, at, volume, pitch, delay, 1f);
    }

    /// Plays a sound once, the same loudness wherever you are (money, upgrades, goals).
    public static void Play(string name, float volume = 1f, float pitch = 1f)
    {
        if (Instance == null) return;
        Instance.Shot(name, Vector3.zero, volume, pitch, 0f, 0f);
    }

    void Shot(string name, Vector3 at, float volume, float pitch, float delay, float spatial)
    {
        var s = pool[next]; next = (next + 1) % PoolSize;
        s.Stop();
        s.clip = SoundBank.Get(name);
        s.transform.position = at;
        s.spatialBlend = spatial;
        s.volume = Mathf.Clamp01(volume * Effects);
        s.pitch = pitch;
        if (delay > 0f) s.PlayDelayed(delay); else s.Play();
        Played++;
    }

    /// A looping source on `parent` (or here), started silent.
    public static AudioSource Loop(GameObject parent, string name, float spatial, float minDist = 4f, float maxDist = 70f)
    {
        var s = parent.AddComponent<AudioSource>();
        s.clip = SoundBank.Get(name);
        s.loop = true; s.playOnAwake = false;
        s.spatialBlend = spatial;
        s.rolloffMode = AudioRolloffMode.Linear;
        s.minDistance = minDist; s.maxDistance = maxDist;
        s.dopplerLevel = 0f;
        s.volume = 0f;
        s.time = Random.Range(0f, s.clip.length * 0.9f);                  // (so two loops of one sound don't line up)
        s.Play();
        return s;
    }

    /// Eases a loop's volume and pitch towards what is wanted.
    public static void Steer(AudioSource s, float volume, float pitch, float dt, float rate = 8f)
    {
        if (s == null) return;
        float k = 1f - Mathf.Exp(-rate * dt);
        s.volume = Mathf.Lerp(s.volume, Mathf.Clamp01(volume), k);
        s.pitch = Mathf.Lerp(s.pitch, pitch, k);
    }

    // ---- the loops looked after here
    AudioSource jack, vacuum, gravel, cartRoll, motor, tip, wind, hum;
    GameObject cartGo, workerGo;
    float lastStride, lastAlong, birdTimer = 3f, dripTimer = 2f, creakTimer = 8f, inMine, cashCool;
    int lastPack;
    bool started;

    void Awake()
    {
        Instance = this;
        LoadPrefs();
        pool = new AudioSource[PoolSize];
        for (int i = 0; i < PoolSize; i++)
        {
            var go = new GameObject("Sound " + i);
            go.transform.SetParent(transform, false);
            var s = go.AddComponent<AudioSource>();
            s.playOnAwake = false; s.rolloffMode = AudioRolloffMode.Linear; s.minDistance = 3f; s.maxDistance = 60f; s.dopplerLevel = 0f;
            pool[i] = s;
        }
        SoundBank.MakeAll();
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Start()
    {
        if (FindFirstObjectByType<AudioListener>() == null && Camera.main != null) Camera.main.gameObject.AddComponent<AudioListener>();
        wind = Loop(gameObject, "wind", 0f);
        hum = Loop(gameObject, "mine_hum", 0f);
    }

    void LateUpdate()
    {
        AudioListener.volume = Master;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        var wk = Worker.Instance;
        var cart = MineCart.Instance;
        if (!started && wk != null)
        {
            started = true;
            workerGo = wk.gameObject;
            jack = Loop(workerGo, "jackhammer", 0.7f, 3f, 40f);
            vacuum = Loop(workerGo, "vacuum", 0.7f, 3f, 40f);
            gravel = Loop(workerGo, "gravel", 0.7f, 3f, 40f);
            var dz = FindFirstObjectByType<DozerController>();
            if (dz != null && dz.GetComponent<DozerAudio>() == null) dz.gameObject.AddComponent<DozerAudio>();
        }
        if (cart != null && cartGo == null)
        {
            cartGo = cart.gameObject;
            cartRoll = Loop(cartGo, "cart_roll", 0.9f, 3f, 50f);
            motor = Loop(cartGo, "motor", 0.9f, 3f, 50f);
            tip = Loop(cartGo, "tip_rumble", 0.9f, 3f, 50f);
            lastAlong = cart.Along;
        }
        float fx = Effects;
        bool quiet = Prologue.Playing;

        // ---- the worker
        if (wk != null && jack != null)
        {
            bool onFoot = !wk.InDozer && !quiet;
            Steer(jack, onFoot && wk.Hammering ? 0.8f * fx : 0f, 1f, dt, 20f);
            bool sucking = onFoot && wk.Sucking;
            Steer(vacuum, sucking ? 0.55f * fx : 0f, sucking ? 1f : 0.7f, dt, 6f);
            var world = VoxelWorld.Instance;
            int pack = world != null ? world.PackVoxels : 0;
            Steer(gravel, sucking && pack > lastPack ? 0.6f * fx : 0f, 1f, dt, 12f);
            lastPack = pack;
            // footsteps: one every 0.7 m walked, echoing in the mine
            if (wk.Stride - lastStride > 0.7f)
            {
                lastStride = wk.Stride;
                if (onFoot) PlayAt(InMine(wk.transform.position) ? "step_mine" : "step", wk.transform.position, 0.45f, 0.9f + 0.2f * Random.value);
            }
        }

        // ---- the cart
        if (cart != null && cartRoll != null)
        {
            float speed = Mathf.Abs(cart.Along - lastAlong) / dt;
            lastAlong = cart.Along;
            if (speed > 20f) speed = 0f;                                   // (it was put somewhere: a load, a test)
            Steer(cartRoll, quiet ? 0f : Mathf.Clamp01(speed / 2.5f) * 0.7f * fx, 0.6f + 0.25f * speed, dt, 6f);
            bool motorOn = cart.spec.motor && wk != null && wk.RidingCart;
            Steer(motor, motorOn && !quiet ? (0.35f + 0.1f * speed) * fx : 0f, 0.8f + 0.15f * speed, dt, 4f);
            Steer(tip, cart.Tipping && !quiet ? 0.7f * fx : 0f, 1f, dt, 6f);
        }
        if (cashCool > 0f) cashCool -= dt;

        // ---- the ambience: outside, wind and birds; in the mine, a hum, drips and creaks
        Vector3 ear = Camera.main != null ? Camera.main.transform.position : Vector3.zero;
        inMine = Mathf.MoveTowards(inMine, InMine(ear) ? 1f : 0f, dt * 0.8f);
        Steer(wind, quiet ? 0f : 0.35f * (1f - 0.85f * inMine) * fx, 1f, dt, 3f);
        Steer(hum, quiet ? 0f : 0.3f * inMine * fx, 1f, dt, 3f);
        if (quiet) return;
        birdTimer -= dt;
        if (birdTimer <= 0f)
        {
            birdTimer = 2.5f + 6f * Random.value;
            if (inMine < 0.5f)
            {
                Vector2 c = Random.insideUnitCircle.normalized * (18f + 25f * Random.value);
                PlayAt("bird" + Random.Range(0, 3), ear + new Vector3(c.x, 8f + 6f * Random.value, c.y), 0.6f, 0.9f + 0.25f * Random.value);
            }
        }
        dripTimer -= dt;
        if (dripTimer <= 0f)
        {
            dripTimer = 1.5f + 4f * Random.value;
            if (inMine > 0.5f) { Vector2 c = Random.insideUnitCircle * 4f; PlayAt("drip", ear + new Vector3(c.x, 1f, c.y), 0.35f, 0.85f + 0.35f * Random.value); }
        }
        creakTimer -= dt;
        if (creakTimer <= 0f)
        {
            creakTimer = 6f + 10f * Random.value;
            if (inMine > 0.5f) { Vector2 c = Random.insideUnitCircle * 6f; PlayAt("creak", ear + new Vector3(c.x, 2f, c.y), 0.4f, 0.8f + 0.3f * Random.value); }
        }
    }

    /// Inside the mine's tunnel.
    public static bool InMine(Vector3 p)
    {
        float along = p.z - VoxelWorld.PortalZ;
        return along > 0.8f && along < VoxelWorld.TunnelLength + 1f && Mathf.Abs(p.x - VoxelWorld.PortalX) < 3.5f && p.y < 4f;
    }

    /// The ka-ching for money coming in (not more than one every second and a half: the hopper pays as it fills).
    public static void Cash()
    {
        if (Instance == null || Instance.cashCool > 0f) return;
        Instance.cashCool = 1.5f;
        Play("kaching", 0.7f);
    }
}
