// The sound: it plays what SoundBank makes (copied from the Digger Game and cut down).
//   One-shots: Play / PlayAt, from a small pool of sources.  Loops: a looping source whose volume follows the game (Loop).
//   This script looks after the footsteps and the wind; the guns, the grunts and the blasts call PlayAt when it happens.
using UnityEngine;

public class GameAudio : MonoBehaviour
{
    public static GameAudio Instance { get; private set; }
    public static float Master = 0.8f, Effects = 0.8f;
    public static int Played { get; private set; }                    // one-shots started (for tests)

    const int PoolSize = 24;
    AudioSource[] pool;
    int next;

    /// Plays a sound once at a place in the world (it gets quieter with distance).
    public static void PlayAt(string name, Vector3 at, float volume = 1f, float pitch = 1f, float delay = 0f)
    {
        if (Instance == null) return;
        Instance.Shot(name, at, volume, pitch, delay, 0.7f);
    }

    /// Plays a sound once, the same loudness wherever you are.
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
        s.time = Random.Range(0f, s.clip.length * 0.9f);
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

    AudioSource wind;
    float lastStride;

    void Awake()
    {
        Instance = this;
        pool = new AudioSource[PoolSize];
        for (int i = 0; i < PoolSize; i++)
        {
            var go = new GameObject("Sound " + i);
            go.transform.SetParent(transform, false);
            var s = go.AddComponent<AudioSource>();
            s.playOnAwake = false; s.rolloffMode = AudioRolloffMode.Linear; s.minDistance = 4f; s.maxDistance = 70f; s.dopplerLevel = 0f;
            pool[i] = s;
        }
        SoundBank.MakeAll();
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    void Start()
    {
        if (FindFirstObjectByType<AudioListener>() == null && Camera.main != null) Camera.main.gameObject.AddComponent<AudioListener>();
        wind = Loop(gameObject, "wind", 0f);
    }

    void LateUpdate()
    {
        AudioListener.volume = Master;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        Steer(wind, 0.25f * Effects, 1f, dt, 3f);
        var pl = ArenaPlayer.Instance;
        if (pl != null && pl.Stride - lastStride > 0.75f)                 // footsteps: one every 0.75 m run
        {
            lastStride = pl.Stride;
            PlayAt("step", pl.transform.position, 0.35f, 0.9f + 0.2f * Random.value);
        }
    }
}
