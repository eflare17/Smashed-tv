using UnityEngine;

namespace Digger
{
    /// <summary>Simple on-screen readout and controls card (IMGUI, so it needs no UI setup).</summary>
    public class DozerHud : MonoBehaviour
    {
        public DozerController dozer;
        public BladeCutter cutter;
        public DozerCameraRig rig;
        public DozerInput input;
        public bool showHelp = true;

        GUIStyle panel, label, value, small, heading, badge;
        Texture2D panelTex, barBack, barFill, frameTex;

        void Update()
        {
            if (input && input.HelpPressed) showHelp = !showHelp;
        }

        static Texture2D Solid(Color c)
        {
            var t = new Texture2D(1, 1);
            t.SetPixel(0, 0, c);
            t.Apply();
            t.hideFlags = HideFlags.DontSave;
            return t;
        }

        void Styles()
        {
            if (panel != null) return;
            panelTex = Solid(new Color(0.06f, 0.055f, 0.05f, 0.78f));
            barBack = Solid(new Color(1f, 1f, 1f, 0.12f));
            barFill = Solid(new Color(0.94f, 0.66f, 0.18f, 0.95f));
            frameTex = Solid(new Color(0.94f, 0.66f, 0.18f, 1f));
            panel = new GUIStyle { normal = { background = panelTex }, padding = new RectOffset(14, 14, 10, 12) };
            label = new GUIStyle { fontSize = 15, normal = { textColor = new Color(0.8f, 0.77f, 0.72f) } };
            value = new GUIStyle(label) { fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperRight, normal = { textColor = new Color(0.97f, 0.95f, 0.9f) } };
            small = new GUIStyle(label) { fontSize = 13, richText = true };
            heading = new GUIStyle(label) { fontSize = 13, fontStyle = FontStyle.Bold, normal = { textColor = new Color(0.94f, 0.66f, 0.18f) } };
            badge = new GUIStyle(label) { fontSize = 12, fontStyle = FontStyle.Bold, normal = { textColor = Color.black }, padding = new RectOffset(6, 6, 2, 2) };
            badge.normal.background = frameTex;
        }

        void Row(float x, ref float y, float w, string name, string text)
        {
            GUI.Label(new Rect(x, y, w, 22), name, label);
            GUI.Label(new Rect(x, y, w, 22), text, value);
            y += 22;
        }

        void OnGUI()
        {
            if (!dozer) return;
            Styles();
            float scale = Mathf.Max(0.75f, Screen.height / 1080f);
            GUI.matrix = Matrix4x4.Scale(new Vector3(scale, scale, 1f));

            // Readout
            float x = 18, y = 18, w = 260;
            GUI.Box(new Rect(x, y, w + 28, 268), GUIContent.none, panel);
            float cx = x + 14, cy = y + 10;
            GUI.Label(new Rect(cx, cy, w, 20), "STAGE 1 · TEST YARD", heading); cy += 26;
            Row(cx, ref cy, w, "Speed", string.Format("{0:0.0} km/h", Mathf.Abs(dozer.SpeedKmh)));
            Row(cx, ref cy, w, "Gear", (dozer.Reversing ? "R" : "F") + dozer.GearNumber);
            GUI.Label(new Rect(cx, cy, w, 22), "Engine load", label); cy += 22;
            GUI.DrawTexture(new Rect(cx, cy, w, 8), barBack);
            GUI.DrawTexture(new Rect(cx, cy, w * Mathf.Clamp01(dozer.EngineLoad), 8), barFill);
            cy += 16;
            float bladeH = cutter ? dozer.BladeHeightAboveGround(cutter.edgeLeft, cutter.edgeRight) : 0f;
            Row(cx, ref cy, w, "Blade height", string.Format("{0:+0;-0;0} cm", bladeH * 100f));
            Row(cx, ref cy, w, "Blade tilt", TiltText(dozer.TiltDegrees));
            Row(cx, ref cy, w, "Blade angle", AngleText(dozer.AngleDegrees));
            Row(cx, ref cy, w, "Load on blade", cutter ? string.Format("{0:0.0} m³", cutter.LoadVolume) : "-");
            Row(cx, ref cy, w, "Work lights", dozer.LightsOn ? "On" : "Off");
            if (input && input.gyroTilt) Row(cx, ref cy, w, "Gyro tilt", "On");

            // Controls card
            if (showHelp)
            {
                const string keys =
                    "<b>W / S</b>  forward / reverse     <b>A / D</b>  steer (pivot when stopped)\n" +
                    "<b>Q / E</b>  gear down / up        <b>Space</b>  brake\n" +
                    "<b>R / F</b> or <b>↑ / ↓</b>  raise / lower blade\n" +
                    "<b>Z / C</b>  tilt blade             <b>← / →</b>  angle blade\n" +
                    "<b>Right mouse</b>  orbit camera   <b>Wheel</b>  zoom   <b>V</b>  cab view\n" +
                    "<b>B</b>  blade cam   <b>L</b>  work lights   <b>G</b>  gyro tilt\n" +
                    "<b>P</b>  reset dozer   <b>Backspace</b>  reset ground   <b>H</b>  hide this\n" +
                    "Gamepad: left stick drive, right stick blade, LB/RB tilt, triggers throttle";
                var hy = Screen.height / scale - 196;
                GUI.Box(new Rect(18, hy, 560, 178), GUIContent.none, panel);
                GUI.Label(new Rect(32, hy + 10, 540, 20), "CONTROLS", heading);
                GUI.Label(new Rect(32, hy + 34, 540, 150), keys, small);
            }

            // Frame around the blade cam
            if (rig && rig.bladeCamOn && rig.bladeCamera)
            {
                var r = rig.BladeCamGuiRect;
                r = new Rect(r.x / scale, r.y / scale, r.width / scale, r.height / scale);
                const float t = 2f;
                GUI.DrawTexture(new Rect(r.x - t, r.y - t, r.width + 2 * t, t), frameTex);
                GUI.DrawTexture(new Rect(r.x - t, r.yMax, r.width + 2 * t, t), frameTex);
                GUI.DrawTexture(new Rect(r.x - t, r.y, t, r.height), frameTex);
                GUI.DrawTexture(new Rect(r.xMax, r.y, t, r.height), frameTex);
                GUI.Label(new Rect(r.x, r.y - 22, 90, 20), "BLADE CAM", badge);
            }
            GUI.matrix = Matrix4x4.identity;
        }

        static string TiltText(float deg)
        {
            if (Mathf.Abs(deg) < 0.3f) return "level";
            return string.Format("{0} corner down {1:0.0}°", deg > 0f ? "left" : "right", Mathf.Abs(deg));
        }

        static string AngleText(float deg)
        {
            if (Mathf.Abs(deg) < 0.5f) return "straight";
            return string.Format("{0} {1:0}°", deg > 0f ? "right" : "left", Mathf.Abs(deg));
        }
    }
}
