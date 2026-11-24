// First-time hints: short tips, each shown ONCE, the first time it is useful, in a small box under the goal at the top
// of the screen.  They teach the loop: digging, the cart and the hopper, gold versus coins, the upgrades and the
// mountain road's pegs.  A placeholder set (the owner hasn't written them, 22 Nov 2026): the words are in THE LIST.
//
// Which ones have been shown is kept on this computer (PlayerPrefs "hint.<id>"), not in the save: a tip you have
// read once doesn't come back for a new game.  (Hints.ResetAll() forgets them; there is no menu button for it yet.)
// Hidden in trailer mode, in the prologue, in the ending, and while the menu or the upgrade tree is up.
//
// One at a time: a tip stays up for its time (or until the next one is due and it has had 4 s), then the next.
using System.Collections.Generic;
using UnityEngine;

public class Hints : MonoBehaviour
{
    public static Hints Instance { get; private set; }

    struct Hint { public string id, pc, pad; public float seconds; public System.Func<bool> when; }
    static Hint H(string id, string pc, string pad, System.Func<bool> when, float seconds = 9f) { return new Hint { id = id, pc = pc, pad = pad, when = when, seconds = seconds }; }

    // ------------------------------------------------------------------ THE LIST (checked in this order)
    static readonly Hint[] List =
    {
        H("dozer",   "You're in Dad's old dozer.  Enter gets out: the mine is dug on foot.  Enter near the dozer gets back in.",
                     "You're in Dad's old dozer.  Y gets out: the mine is dug on foot.  Y near the dozer gets back in.",
                     () => Wk != null && Wk.InDozer, 8f),
        H("dig",     "Dig: aim at the rubble in the mine and hold the left mouse button (or Space).  1 is the pick, it breaks ground.  2 is the shovel, it scoops it up.",
                     "Dig: aim at the rubble in the mine and hold the right trigger.  RB / LB change tool: the pick breaks ground, the shovel scoops it up.",
                     () => Wk != null && !Wk.InDozer && !Dingo.Working),
        H("cart",    "Use the shovel again to throw.  Near the cart, it lands in the cart.  Fill it, then E at an end of the cart takes hold, and W pushes it out of the mine.",
                     "Use the shovel again to throw.  Near the cart, it lands in the cart.  Fill it, then A at an end of the cart takes hold, and the left stick pushes it out.",
                     () => World != null && World.ShovelVoxels >= VoxelWorld.ClodVoxels),
        H("hopper",  "At the end of the rails is the hopper.  E tips the cart into it: soil, clay and rock are sold for coins on the spot.",
                     "At the end of the rails is the hopper.  A tips the cart into it: soil, clay and rock are sold for coins on the spot.",
                     () => World != null && Cart != null && (World.CartVoxels >= Cart.capacity / 2 || Cart.AtDump && World.CartVoxels >= VoxelWorld.ClodVoxels)),
        H("upgrade", "You can afford an upgrade.  U opens the upgrade tree: pick one and buy it, and it works straight away.",
                     "You can afford an upgrade.  Start opens the upgrade tree: pick one and buy it with A, and it works straight away.",
                     () => Money.Instance != null && Money.Instance.Coins >= 40 && Upgrades.Instance != null && Upgrades.Instance.CantBuy(Upgrades.Branch.Shovel) == null),
        H("gold",    "Gold!  The hopper keeps gold instead of selling it: it's in your gold store (top left).  Sell it at the gold buyer's shed by the mine door (E at the counter), or keep it: new machines cost gold as well as coins.",
                     "Gold!  The hopper keeps gold instead of selling it: it's in your gold store (top left).  Sell it at the gold buyer's shed by the mine door (A at the counter), or keep it: new machines cost gold as well as coins.",
                     () => Money.Instance != null && Money.Instance.GoldStore > 0, 11f),
        H("part",    "That's one of Dad's dozer parts.  E picks it up; carry it to the dozer and E fits it.  Fit all three and the old dozer is restored.",
                     "That's one of Dad's dozer parts.  A picks it up; carry it to the dozer and A fits it.  Fit all three and the old dozer is restored.",
                     () => AnyFound()),
        H("deeper",  "Deeper pays more.  Rock fetches four times what soil does, and quartz ten times.  The hopper shows what each part of a load fetched.",
                     "Deeper pays more.  Rock fetches four times what soil does, and quartz ten times.  The hopper shows what each part of a load fetched.",
                     () => Goals.Instance != null && Goals.Instance.IsDone("cart_tip")),
        H("road",    "The mountain road: each peg says how far to CUT down or FILL up to reach the road's grade.  Green ground is on grade.  B turns blade auto on; press it again for Grade, which holds the blade at the road's grade for you.",
                     "The mountain road: each peg says how far to CUT down or FILL up to reach the road's grade.  Green ground is on grade.  A turns blade auto on; press it again for Grade, which holds the blade at the road's grade for you.",
                     () => NearRoadInDozer(), 12f),
    };

    // ------------------------------------------------------------------ state
    int showing = -1; float shownFor, checkTimer;
    readonly HashSet<string> seen = new HashSet<string>();
    /// Tests: don't read or write the computer's prefs (so a test never marks the owner's tips as seen).
    public static bool TestNoPrefs;

    static Worker Wk { get { return Worker.Instance; } }
    static VoxelWorld World { get { return VoxelWorld.Instance; } }
    static MineCart Cart { get { return MineCart.Instance; } }

    void Awake()
    {
        Instance = this;
        if (!TestNoPrefs) foreach (var h in List) if (PlayerPrefs.GetInt("hint." + h.id, 0) == 1) seen.Add(h.id);
    }
    void OnDestroy() { if (Instance == this) Instance = null; }

    /// The tip on screen now ("" if none), and whether one has been shown (tests).
    public string Showing { get { return showing >= 0 ? Text(List[showing]) : ""; } }
    public string ShowingId { get { return showing >= 0 ? List[showing].id : ""; } }
    public bool Seen(string id) { return seen.Contains(id); }
    public static int Count { get { return List.Length; } }
    /// Tests: what the tip is doing now.
    public string DebugLine { get { return "showing=" + showing + " for=" + shownFor.ToString("F2") + " blocked=" + Blocked + " gui=" + guiCalls; } }
    int guiCalls;

    static string Text(Hint h) { return Pad.InUse ? h.pad : h.pc; }

    static bool Blocked { get { return TrailerMode.On || Prologue.Playing || Ending.Playing || PauseMenu.Blocking || (Upgrades.Instance != null && Upgrades.Instance.Open); } }

    void Update()
    {
        if (showing >= 0)
        {
            if (!Blocked) shownFor += Time.unscaledDeltaTime;
            if (shownFor >= List[showing].seconds) showing = -1;
        }
        if (Blocked || Time.timeSinceLevelLoad < 3f) return;
        checkTimer -= Time.unscaledDeltaTime;
        if (checkTimer > 0f) return;
        checkTimer = 0.5f;
        if (showing >= 0 && shownFor < 4f) return;                 // give the one up now a fair go first
        for (int i = 0; i < List.Length; i++)
        {
            var h = List[i];
            if (seen.Contains(h.id) || i == showing) continue;
            bool due;
            try { due = h.when(); } catch (System.Exception) { due = false; }
            if (!due) continue;
            Show(i);
            return;
        }
    }

    void Show(int i)
    {
        showing = i; shownFor = 0f;
        seen.Add(List[i].id);
        if (!TestNoPrefs) { PlayerPrefs.SetInt("hint." + List[i].id, 1); PlayerPrefs.Save(); }
    }

    /// Forgets which tips have been shown, so they all come again.
    public static void ResetAll()
    {
        foreach (var h in List) PlayerPrefs.DeleteKey("hint." + h.id);
        PlayerPrefs.Save();
        if (Instance != null) { Instance.seen.Clear(); Instance.showing = -1; }
    }

    /// Tests: forget what was shown, without touching the prefs.
    public void TestForget() { seen.Clear(); showing = -1; }

    static bool AnyFound()
    {
        var f = Finds.Instance;
        if (f == null) return false;
        for (int k = 0; k < Finds.Count; k++) if (f.Found[k] && !f.Collected[k]) return true;
        return false;
    }

    static bool NearRoadInDozer()
    {
        if (Wk == null || !Wk.InDozer) return false;
        var d = FindFirstObjectByType<DozerController>();
        if (d == null) return false;
        Vector3 p = d.transform.position;
        float s, off; Vector2 rd;
        MountainRoad.Nearest(p.x, p.z, out s, out off, out rd);
        return Mathf.Abs(off) < 8f && s < MountainRoad.Length;
    }

    // ------------------------------------------------------------------ on screen: under the goal, top middle
    GUIStyle head, body;
    void OnGUI()
    {
        if (showing < 0 || Blocked) return;
        guiCalls++;
        Ui.Begin();
        if (head == null)
        {
            head = new GUIStyle(GUI.skin.label) { fontSize = 13, fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperLeft };
            head.normal.textColor = new Color(0.55f, 0.85f, 1f);
            body = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.UpperLeft, wordWrap = true };
            body.normal.textColor = new Color(0.95f, 0.95f, 0.95f);
        }
        string text = Text(List[showing]);
        float w = 560f, x = (Ui.W - w) / 2f, y = 92f;
        if (Hud.HelpOn && x < Hud.HelpRight + 12f) { x = Hud.HelpRight + 12f; w = Mathf.Max(320f, Mathf.Min(w, Ui.W - x - Hud.Margin)); }   // clear of the help box
        float h = body.CalcHeight(new GUIContent(text), w - 24f) + 30f;
        float fade = Mathf.Clamp01(Mathf.Min(shownFor * 3f, (List[showing].seconds - shownFor) * 2f));
        var old = GUI.color;
        GUI.color = new Color(1f, 1f, 1f, fade);
        GUI.Box(new Rect(x, y, w, h), GUIContent.none);
        GUI.Label(new Rect(x + 12f, y + 5f, w - 24f, 18f), "TIP", head);
        GUI.Label(new Rect(x + 12f, y + 22f, w - 24f, h - 26f), text, body);
        GUI.color = old;
    }
}
