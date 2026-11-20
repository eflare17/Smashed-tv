// The pause menu.  Esc opens it (and Esc closes the upgrades first, if they are open).  On the pad: Start opens the
// upgrades as before, and Back from there opens this menu.  The game stops while it is up.
//
//   Resume      back to the game (Esc, Start or Back do it too)
//   Settings    graphics: quality, shadows, view distance, full screen or windowed, resolution
//               screen: UI size (how big the panels and help are drawn, 75% to 200%; see Ui.cs)
//               controls: mouse speed, invert mouse look
//               sound: master, engine and effects volume (GameAudio.cs); camera shake on or off
//   New game    asks first; starts the site afresh (the old save is kept as a backup)
//   Quit        asks first; the built game saves itself as it closes
//
// The settings are kept in PlayerPrefs, so they stay from one game to the next.
//
// What the graphics settings change (the game uses the built-in render pipeline):
//   Medium quality is the look the game was made with: SceneLook sets the shadows, and this keeps what it set.
//   Low halves the shadow distance and makes shadows coarser, with no smoothing of edges; High pushes them further
//   and smooths more.  View distance is how far the camera draws: the ground itself is small, so this mostly cuts
//   the far hills and trees; the haze is thickened to match, so the edge doesn't show.
//   Ultra is for a big graphics card: High's shadows pushed further still and drawn from an 8192 shadow map (sharp
//   edges up close), 8x MSAA edge smoothing, more lights at once, and stronger soft shading in the corners and cracks
//   between blocks (the ambient occlusion the post-processing already does, turned up).
//
// The fps counter (Show fps, or F11) is a small readout in the top right: frames a second and milliseconds a frame,
// averaged over half a second.
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

public class PauseMenu : MonoBehaviour
{
    public static PauseMenu Instance { get; private set; }
    public bool Open { get; private set; }
    public static bool Paused { get { return Instance != null && Instance.Open; } }
    /// True while the menu is up, and on the frame it opens or closes, so the key that did it does nothing else.
    public static bool Blocking { get { return Instance != null && (Instance.Open || Instance.changedFrame == Time.frameCount); } }

    // ---------------------------------------------------------------- the settings
    public static readonly string[] QualityNames = { "Low", "Medium", "High", "Ultra" };
    public static readonly string[] ViewNames = { "Short", "Middle", "Far" };
    public static readonly float[] ViewMetres = { 250f, 450f, 900f };     // Far is what the game had (SiteProps sets 900)
    public static int Quality = 1, View = 2;
    public static bool Shadows = true, InvertMouse, ShowFps;
    public static bool CameraShake = true;                                // the camera bumps on hard hits (FollowCamera)
    public static float MouseSpeed = 1f;                                  // times the normal speed, 0.25 to 3
    public static float UltraAo = 2.0f;                                   // Ultra's ambient occlusion strength (Medium's is the scene's, 0.6)

    public static void LoadPrefs()
    {
        Quality = Mathf.Clamp(PlayerPrefs.GetInt("set.quality", 1), 0, 3);
        View = Mathf.Clamp(PlayerPrefs.GetInt("set.view", 2), 0, 2);
        Shadows = PlayerPrefs.GetInt("set.shadows", 1) == 1;
        InvertMouse = PlayerPrefs.GetInt("set.invert", 0) == 1;
        ShowFps = PlayerPrefs.GetInt("set.fps", 0) == 1;
        MouseSpeed = Mathf.Clamp(PlayerPrefs.GetFloat("set.mouse", 1f), 0.25f, 3f);
        Ui.Size = Mathf.Clamp(PlayerPrefs.GetFloat("set.uisize", 1f), Ui.MinSize, Ui.MaxSize);
        CameraShake = PlayerPrefs.GetInt("set.shake", 1) == 1;
        GameAudio.LoadPrefs();
    }

    public static void SavePrefs()
    {
        PlayerPrefs.SetInt("set.quality", Quality);
        PlayerPrefs.SetInt("set.view", View);
        PlayerPrefs.SetInt("set.shadows", Shadows ? 1 : 0);
        PlayerPrefs.SetInt("set.invert", InvertMouse ? 1 : 0);
        PlayerPrefs.SetInt("set.fps", ShowFps ? 1 : 0);
        PlayerPrefs.SetFloat("set.mouse", MouseSpeed);
        PlayerPrefs.SetFloat("set.uisize", Ui.Size);
        PlayerPrefs.SetInt("set.shake", CameraShake ? 1 : 0);
        GameAudio.SavePrefs();
        PlayerPrefs.Save();
    }

    // what SceneLook set up: the Medium look
    bool haveBase;
    float baseShadowDist, baseLod;
    int baseAA, baseCascades, baseLights;
    ShadowQuality baseShadows;
    ShadowResolution baseShadowRes;
    Light sun; int baseSunRes;
    public static float AoNow = -1f;                     // for tests: the ambient occlusion strength Ultra set (-1 not touched yet)
    AmbientOcclusion ao; float baseAo;                  // the scene's own ambient occlusion (the post-processing look)

    /// Puts the quality and shadow settings into Unity.
    public void ApplyGraphics()
    {
        if (!haveBase)
        {
            haveBase = true;
            baseShadowDist = QualitySettings.shadowDistance; baseLod = QualitySettings.lodBias;
            baseAA = QualitySettings.antiAliasing; baseCascades = QualitySettings.shadowCascades;
            baseLights = QualitySettings.pixelLightCount; baseShadows = QualitySettings.shadows;
            baseShadowRes = QualitySettings.shadowResolution;
            sun = RenderSettings.sun;
            if (sun != null) baseSunRes = sun.shadowCustomResolution;
        }
        bool ultra = Quality == 3;
        if (sun != null) sun.shadowCustomResolution = ultra ? 8192 : baseSunRes;
        // the ambient occlusion: only touched once Ultra is picked (volume.profile makes the volume its own copy)
        if (ao == null && ultra)
        {
            var vol = FindFirstObjectByType<PostProcessVolume>();
            if (vol != null && vol.profile != null && vol.profile.TryGetSettings(out ao)) baseAo = ao.intensity.value;
            else ao = null;
        }
        if (ao != null) ao.intensity.value = ultra ? UltraAo : baseAo;
        AoNow = ao != null ? ao.intensity.value : -1f;
        if (Quality == 0)
        {
            QualitySettings.shadowDistance = baseShadowDist * 0.5f;
            QualitySettings.shadowResolution = ShadowResolution.Medium;
            QualitySettings.shadowCascades = 2;
            QualitySettings.antiAliasing = 0;
            QualitySettings.pixelLightCount = Mathf.Min(baseLights, 2);
            QualitySettings.lodBias = baseLod * 0.5f;
            QualitySettings.anisotropicFiltering = AnisotropicFiltering.Disable;
        }
        else if (Quality == 1)
        {
            QualitySettings.shadowDistance = baseShadowDist;
            QualitySettings.shadowResolution = baseShadowRes;
            QualitySettings.shadowCascades = baseCascades;
            QualitySettings.antiAliasing = baseAA;
            QualitySettings.pixelLightCount = baseLights;
            QualitySettings.lodBias = baseLod;
            QualitySettings.anisotropicFiltering = AnisotropicFiltering.Enable;
        }
        else
        {
            QualitySettings.shadowDistance = baseShadowDist * (ultra ? 2.2f : 1.6f);
            QualitySettings.shadowResolution = ShadowResolution.VeryHigh;
            QualitySettings.shadowCascades = 4;
            QualitySettings.antiAliasing = ultra ? 8 : Mathf.Max(baseAA, 4);
            QualitySettings.pixelLightCount = ultra ? Mathf.Max(baseLights, 16) : baseLights;
            QualitySettings.lodBias = baseLod * (ultra ? 2.5f : 1.5f);
            QualitySettings.anisotropicFiltering = AnisotropicFiltering.ForceEnable;
        }
        QualitySettings.shadows = Shadows ? (baseShadows == ShadowQuality.Disable ? ShadowQuality.All : baseShadows) : ShadowQuality.Disable;
    }

    // ---- view distance: kept on the camera every frame, since other scripts (SiteProps, the dozer camera) set it too
    float camSetTo = -1f, camBase = 900f, fogSetTo = -1f, fogBase;
    Camera msaaCam; bool baseMsaa;

    void LateUpdate()
    {
        var cam = Camera.main;
        if (cam == null) return;
        // MSAA is off on the game's camera (the post-processing smooths edges instead); Ultra turns it on as well
        if (cam != msaaCam) { msaaCam = cam; baseMsaa = cam.allowMSAA; }
        cam.allowMSAA = Quality == 3 ? true : baseMsaa;
        if (!Mathf.Approximately(cam.farClipPlane, camSetTo)) camBase = cam.farClipPlane;          // someone else set it
        float far = Mathf.Min(camBase, ViewMetres[View]);
        cam.farClipPlane = camSetTo = far;
        if (!Mathf.Approximately(RenderSettings.fogDensity, fogSetTo)) fogBase = RenderSettings.fogDensity;
        // thick enough haze that the ground has faded out by the edge (exp2 fog: 2.4 / distance leaves about 0.3%)
        RenderSettings.fogDensity = fogSetTo = RenderSettings.fog ? Mathf.Max(fogBase, 2.4f / far) : fogBase;
    }

    // ---- full screen and resolution: Unity remembers these itself between games
    struct Res { public int w, h; }
    Res[] resolutions;
    int resIndex;
    bool fullScreen;

    void ReadScreen()
    {
        var list = new System.Collections.Generic.List<Res>();
        foreach (var r in Screen.resolutions)
            if (!list.Exists(x => x.w == r.width && x.h == r.height)) list.Add(new Res { w = r.width, h = r.height });
        if (list.Count == 0) list.Add(new Res { w = Screen.width, h = Screen.height });
        resolutions = list.ToArray();
        resIndex = resolutions.Length - 1;
        for (int i = 0; i < resolutions.Length; i++) if (resolutions[i].w == Screen.width && resolutions[i].h == Screen.height) resIndex = i;
        fullScreen = Screen.fullScreenMode != FullScreenMode.Windowed;
    }

    void ApplyScreen()
    {
        if (Application.isEditor) return;                                 // the editor's game view can't be resized this way
        var r = resolutions[resIndex];
        Screen.SetResolution(r.w, r.h, fullScreen ? FullScreenMode.FullScreenWindow : FullScreenMode.Windowed);
    }

    // ---------------------------------------------------------------- opening and closing
    enum Page { Main, Settings, Quit, NewGame }
    Page page;
    int sel;                                     // the row the keys and pad have picked
    int changedFrame = -1;
    float timeScaleBefore = 1f;

    void Awake() { Instance = this; LoadPrefs(); }
    void OnDestroy() { if (Instance == this) { Instance = null; if (Open) { Time.timeScale = timeScaleBefore; AudioListener.pause = false; } } }
    void Start() { ApplyGraphics(); ReadScreen(); }

    public void SetOpen(bool open)
    {
        if (open == Open) return;
        Open = open;
        changedFrame = Time.frameCount;
        if (open)
        {
            timeScaleBefore = Time.timeScale > 0f ? Time.timeScale : 1f;
            Time.timeScale = 0f;
            AudioListener.pause = true;
            Cursor.lockState = CursorLockMode.None;      // (a click back in the game takes the mouse again, as before)
            page = Page.Main; sel = 0;
            ReadScreen();
        }
        else
        {
            Time.timeScale = timeScaleBefore;
            AudioListener.pause = false;
            SavePrefs();
        }
    }

    // ---- the fps counter
    float fpsTime; int fpsFrames;
    public static float FpsAvg, MsAvg;                   // over the last half second
    public static string FpsText = "";

    public void ToggleFps() { ShowFps = !ShowFps; SavePrefs(); }

    void CountFrames()
    {
        fpsTime += Time.unscaledDeltaTime; fpsFrames++;
        if (fpsTime >= 0.5f)
        {
            MsAvg = fpsTime * 1000f / fpsFrames; FpsAvg = fpsFrames / fpsTime;
            FpsText = FpsAvg.ToString("F0") + " fps   " + MsAvg.ToString("F1") + " ms";
            fpsTime = 0f; fpsFrames = 0;
        }
    }

    void Update()
    {
        CountFrames();
        if (Input.GetKeyDown(KeyCode.F11)) ToggleFps();
        var up = Upgrades.Instance;
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            if (Open) Back();
            else if (up != null && up.Open) up.SetOpen(false);
            else SetOpen(true);
            return;
        }
        if (!Open)
        {
            // the pad: Back while the upgrades are up comes here (Start is the upgrades, Back on its own is the view)
            if (up != null && up.Open && Pad.Down(Pad.B.Back)) { up.SetOpen(false); SetOpen(true); }
            return;
        }
        if (changedFrame == Time.frameCount) return;
        if (Pad.Down(Pad.B.Start) || Pad.Down(Pad.B.Back)) { SetOpen(false); return; }
        int rows = page == Page.Main ? 4 : (page == Page.Quit || page == Page.NewGame) ? 2 : SettingRows;
        if (Pad.DUpDown || Input.GetKeyDown(KeyCode.UpArrow)) sel = (sel + rows - 1) % rows;
        if (Pad.DDownDown || Input.GetKeyDown(KeyCode.DownArrow)) sel = (sel + 1) % rows;
        if (page == Page.Settings)
        {
            if (Pad.DLeftDown || Input.GetKeyDown(KeyCode.LeftArrow)) Change(sel, -1);
            if (Pad.DRightDown || Input.GetKeyDown(KeyCode.RightArrow)) Change(sel, +1);
        }
        if (Pad.Down(Pad.B.A) || Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter)) Press(page, sel);
    }

    void Back()
    {
        if (page == Page.Main) SetOpen(false);
        else { sel = page == Page.Quit ? 3 : page == Page.NewGame ? 2 : 1; page = Page.Main; SavePrefs(); }
    }

    void Press(Page p, int row)
    {
        if (p == Page.Main)
        {
            if (row == 0) SetOpen(false);
            else if (row == 1) { page = Page.Settings; sel = 0; }
            else if (row == 2) { page = Page.NewGame; sel = 1; }         // "No" picked to start with
            else { page = Page.Quit; sel = 1; }
        }
        else if (p == Page.Quit)
        {
            if (row == 0) { SavePrefs(); if (SaveGame.Instance != null && SaveGame.AutoOn) SaveGame.Instance.Save(); Application.Quit(); }
            else Back();
        }
        else if (p == Page.NewGame)
        {
            if (row == 0) { SavePrefs(); SetOpen(false); if (SaveGame.Instance != null) SaveGame.Instance.NewGame(); }
            else Back();
        }
        else if (row == SettingRows - 1) Back();
        else Change(row, +1);                                            // A or Enter on a setting steps it along
    }

    // ---- the settings page: one row each
    public const int SettingRows = 14, UiSizeRow = 5, SoundRow = 9, ShakeRow = 12;
    static readonly string[] SettingNames = { "Quality", "Shadows", "View distance", "Display", "Resolution", "UI size", "Show fps  (F11)", "Mouse speed", "Invert mouse look",
                                              "Master volume", "Engine volume", "Effects volume", "Camera shake", "Back" };

    string SettingValue(int row)
    {
        switch (row)
        {
            case 0: return QualityNames[Quality];
            case 1: return Shadows ? "On" : "Off";
            case 2: return ViewNames[View] + "  (" + ViewMetres[View].ToString("F0") + " m)";
            case 3: return fullScreen ? "Full screen" : "Windowed";
            case 4: return resolutions[resIndex].w + " x " + resolutions[resIndex].h;
            case 5: return Mathf.RoundToInt(Ui.Size * 100f) + "%";
            case 6: return ShowFps ? "On" : "Off";
            case 7: return MouseSpeed.ToString("0.00") + "x";
            case 8: return InvertMouse ? "On" : "Off";
            case 9: return Mathf.RoundToInt(GameAudio.Master * 100f) + "%";
            case 10: return Mathf.RoundToInt(GameAudio.Engine * 100f) + "%";
            case 11: return Mathf.RoundToInt(GameAudio.Effects * 100f) + "%";
            case 12: return CameraShake ? "On" : "Off";
        }
        return "";
    }

    /// Steps a setting one along (dir -1 or +1) and puts it into the game.
    public void Change(int row, int dir)
    {
        switch (row)
        {
            case 0: Quality = Mathf.Clamp(Quality + dir, 0, 3); ApplyGraphics(); break;
            case 1: Shadows = !Shadows; ApplyGraphics(); break;
            case 2: View = Mathf.Clamp(View + dir, 0, 2); break;
            case 3: fullScreen = !fullScreen; ApplyScreen(); break;
            case 4: resIndex = Mathf.Clamp(resIndex + dir, 0, resolutions.Length - 1); ApplyScreen(); break;
            case 5: Ui.Size = Mathf.Clamp(Mathf.Round((Ui.Size + dir * 0.25f) * 4f) / 4f, Ui.MinSize, Ui.MaxSize); break;
            case 6: ShowFps = !ShowFps; break;
            case 7: MouseSpeed = Mathf.Clamp(Mathf.Round((MouseSpeed + dir * 0.25f) * 4f) / 4f, 0.25f, 3f); break;
            case 8: InvertMouse = !InvertMouse; break;
            case 9: GameAudio.Master = Step10(GameAudio.Master, dir); break;
            case 10: GameAudio.Engine = Step10(GameAudio.Engine, dir); break;
            case 11: GameAudio.Effects = Step10(GameAudio.Effects, dir); break;
            case 12: CameraShake = !CameraShake; break;
        }
    }

    static float Step10(float v, int dir) { return Mathf.Clamp01(Mathf.Round(v * 10f + dir) / 10f); }

    /// For tests: shows the settings page.
    public void ShowSettings() { page = Page.Settings; sel = 0; }

    // ---------------------------------------------------------------- the screen (styled like the upgrades panel)
    void OnGUI()
    {
        if (ShowFps && FpsText.Length > 0)
        {
            Ui.Begin();
            GUI.depth = -20;
            // top right, in the corner (the coins are top left, the blade view bottom right)
            var fs = new GUIStyle(GUI.skin.box) { fontSize = 15, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            fs.normal.textColor = new Color(1f, 1f, 0.85f);
            GUI.Box(new Rect(Ui.W - 170f - Hud.Margin, 10f, 170f, 26f), FpsText, fs);
        }
        if (!Open) return;
        GUI.depth = -10;                                                  // over the upgrades and the help
        float W = 560f;
        float H = page == Page.Settings ? 742f : (page == Page.Quit || page == Page.NewGame) ? 220f : 334f;
        Ui.Begin(W + 40f, page == Page.Settings ? H + 30f : 600f);                                         // (a big UI size is held down so Settings still fits)
        var area = new Rect((Ui.W - W) / 2f, (Ui.H - H) / 2f, W, H);
        GUI.Box(area, GUIContent.none);
        var title = new GUIStyle(GUI.skin.label) { fontSize = 24, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleLeft };
        GUI.Label(new Rect(area.x + 16, area.y + 8, 300, 34), page == Page.Settings ? "Settings" : page == Page.Quit ? "Quit?" : page == Page.NewGame ? "New game?" : "Paused", title);
        var info = new GUIStyle(GUI.skin.label) { fontSize = 14, alignment = TextAnchor.MiddleRight };
        string help = Pad.InUse ? (page == Page.Settings ? "D-pad pick and change   A select   Start closes" : "D-pad pick   A select   Start closes")
                                : (page == Page.Main ? "Esc closes" : "Esc goes back");
        GUI.Label(new Rect(area.xMax - 336, area.y + 8, 320, 34), help, info);

        var button = new GUIStyle(GUI.skin.button) { fontSize = 18 };
        var picked = new GUIStyle(button) { fontStyle = FontStyle.Bold };
        picked.normal.textColor = picked.hover.textColor = new Color(1f, 0.85f, 0.3f);
        float y = area.y + 56f, x = area.x + 24f, w = area.width - 48f;

        if (page == Page.Main)
        {
            string[] names = { "Resume", "Settings", "New game", "Quit" };
            for (int i = 0; i < 4; i++)
            {
                if (GUI.Button(new Rect(x + 60f, y, w - 120f, 44f), names[i], i == sel ? picked : button)) Press(Page.Main, i);
                y += 54f;
            }
            return;
        }
        if (page == Page.Quit || page == Page.NewGame)
        {
            bool quit = page == Page.Quit;
            var text = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.MiddleCenter, wordWrap = true };
            GUI.Label(new Rect(x, y, w, 50f), quit ? (SaveGame.AutoOn ? "The game saves itself as it closes." : "Anything since your last save (F5) will be lost.")
                                                   : "Start the site again from scratch?  Your current game is kept as a backup.", text);
            y += 64f;
            string[] names = quit ? new[] { "Quit the game", "No, go back" } : new[] { "Start a new game", "No, go back" };
            for (int i = 0; i < 2; i++)
                if (GUI.Button(new Rect(x + i * (w / 2f + 6f), y, w / 2f - 6f, 44f), names[i], i == sel ? picked : button)) Press(page, i);
            return;
        }

        var label = new GUIStyle(GUI.skin.label) { fontSize = 16, alignment = TextAnchor.MiddleLeft };
        var labelPicked = new GUIStyle(label) { fontStyle = FontStyle.Bold };
        labelPicked.normal.textColor = new Color(1f, 0.85f, 0.3f);
        var value = new GUIStyle(GUI.skin.box) { fontSize = 16, alignment = TextAnchor.MiddleCenter };
        var head = new GUIStyle(GUI.skin.label) { fontSize = 13, fontStyle = FontStyle.Bold };
        head.normal.textColor = new Color(0.7f, 0.7f, 0.7f);
        for (int i = 0; i < SettingRows; i++)
        {
            if (i == 0) { GUI.Label(new Rect(x, y - 4f, w, 20f), "GRAPHICS", head); y += 16f; }
            if (i == UiSizeRow) { y += 6f; GUI.Label(new Rect(x, y - 4f, w, 20f), "SCREEN", head); y += 16f; }
            if (i == 7) { y += 6f; GUI.Label(new Rect(x, y - 4f, w, 20f), "CONTROLS", head); y += 16f; }
            if (i == SoundRow) { y += 6f; GUI.Label(new Rect(x, y - 4f, w, 20f), "SOUND", head); y += 16f; }
            if (i == SettingRows - 1)
            {
                y += 8f;
                if (GUI.Button(new Rect(x + 120f, y, w - 240f, 38f), "Back", i == sel ? picked : button)) Back();
                break;
            }
            GUI.Label(new Rect(x, y, 200f, 34f), (i == sel ? "> " : "  ") + SettingNames[i], i == sel ? labelPicked : label);
            float vx = x + 200f, vw = w - 200f;
            if (GUI.Button(new Rect(vx, y + 2f, 40f, 30f), "<", button)) { sel = i; Change(i, -1); }
            GUI.Box(new Rect(vx + 46f, y + 2f, vw - 92f, 30f), SettingValue(i), value);
            if (GUI.Button(new Rect(vx + vw - 40f, y + 2f, 40f, 30f), ">", button)) { sel = i; Change(i, +1); }
            y += 40f;
        }
    }
}
