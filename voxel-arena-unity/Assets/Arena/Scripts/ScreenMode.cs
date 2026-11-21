// Full screen or a window.  The arena starts full screen (borderless, at the desktop's own resolution).
// F11 or Alt+Enter switches to a window and back, and the choice is remembered for next time (PlayerPrefs
// "arena_fullscreen").  Our own key wins over Unity's remembered screen mode, so an old windowed start can't stick.
// Made by itself on start, so no scene object is needed.
using UnityEngine;

public class ScreenMode : MonoBehaviour
{
    const string Key = "arena_fullscreen";
    bool full;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Make()
    {
        if (Application.isEditor) return;
        var go = new GameObject("Screen mode");
        DontDestroyOnLoad(go);
        go.AddComponent<ScreenMode>();
    }

    void Start()
    {
        full = PlayerPrefs.GetInt(Key, 1) == 1;
        Apply();
    }

    void Apply()
    {
        var d = Screen.mainWindowDisplayInfo;
        int dw = d.width > 0 ? d.width : Display.main.systemWidth, dh = d.height > 0 ? d.height : Display.main.systemHeight;
        if (full) Screen.SetResolution(dw, dh, FullScreenMode.FullScreenWindow);
        else Screen.SetResolution(Mathf.RoundToInt(dw * 0.75f), Mathf.RoundToInt(dh * 0.75f), FullScreenMode.Windowed);
    }

    void Update()
    {
        bool alt = Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt);
        if (Input.GetKeyDown(KeyCode.F11) || (alt && (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter))))
        {
            full = !full;
            PlayerPrefs.SetInt(Key, full ? 1 : 0);
            PlayerPrefs.Save();
            Apply();
        }
    }
}
