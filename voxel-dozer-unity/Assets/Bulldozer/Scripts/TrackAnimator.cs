// Makes one track turn.  The track is a ring of separate pads that travel round a loop: along the
// bottom towards the back, up round the drive sprocket, forward along the top, and down round the
// front idler.  The sprocket and idler spin to match.  DozerController sets `speed` for each side.
using UnityEngine;

public class TrackAnimator : MonoBehaviour
{
    public float speed;                                   // metres a second; + when this side is driving forward

    // The loop the pads follow, in this track's own space (x = forward, y = up).  From the voxel model.
    public Vector2 frontCentre = new Vector2(1.71875f, -0.03125f);
    public float frontRadius = 0.6875f;
    public Vector2 rearCentre = new Vector2(-1.71875f, 0.03125f);
    public float rearRadius = 0.75f;
    public float padPitch = 0.25f;

    public float Travel { get; private set; }            // how far the track has run, in metres
    public int PadCount { get { return pads != null ? pads.Length : 0; } }

    Transform sprocket, idler;
    Transform[] pads;
    Vector2 botFront, botRear, topRear, topFront;
    float angBot, angTop, lenBot, lenRear, lenTop, lenFront, loop, spacing;

    void Awake()
    {
        Transform template = null;
        for (int i = 0; i < transform.childCount; i++)
        {
            var c = transform.GetChild(i);
            if (c.name.StartsWith("Sprocket")) sprocket = c;
            else if (c.name.StartsWith("Idler")) idler = c;
            else if (c.name.StartsWith("Pad")) template = c;
        }

        // the two straight runs are the lines that touch both wheels
        Vector2 between = rearCentre - frontCentre;
        float dist = between.magnitude;
        Vector2 u = between / dist;
        float c0 = (frontRadius - rearRadius) / dist, s0 = Mathf.Sqrt(1f - c0 * c0);
        Vector2 perp = new Vector2(-u.y, u.x);            // points down, since u points backwards
        Vector2 nBot = u * c0 + perp * s0, nTop = u * c0 - perp * s0;
        botFront = frontCentre + nBot * frontRadius; botRear = rearCentre + nBot * rearRadius;
        topRear = rearCentre + nTop * rearRadius; topFront = frontCentre + nTop * frontRadius;
        angBot = Mathf.Atan2(nBot.y, nBot.x); angTop = Mathf.Atan2(nTop.y, nTop.x);
        lenBot = (botRear - botFront).magnitude;
        lenRear = rearRadius * (angBot - angTop + 2f * Mathf.PI);
        lenTop = (topFront - topRear).magnitude;
        lenFront = frontRadius * (angTop - angBot);
        loop = lenBot + lenRear + lenTop + lenFront;

        if (template != null)
        {
            int n = Mathf.Max(1, Mathf.RoundToInt(loop / padPitch));
            spacing = loop / n;
            pads = new Transform[n];
            pads[0] = template;
            for (int i = 1; i < n; i++)
            {
                pads[i] = Instantiate(template, transform);
                pads[i].name = template.name;
            }
        }
        Place();
    }

    void Update()
    {
        Travel += speed * Time.deltaTime;
        Place();
    }

    void Place()
    {
        if (pads != null)
        {
            float start = Mathf.Repeat(Travel, loop);
            for (int i = 0; i < pads.Length; i++)
            {
                float s = Mathf.Repeat(start + i * spacing, loop);
                Vector2 p; float ang;
                if (s < lenBot) { p = Vector2.Lerp(botFront, botRear, s / lenBot); ang = angBot; }
                else if ((s -= lenBot) < lenRear) { ang = angBot - s / rearRadius; p = rearCentre + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * rearRadius; }
                else if ((s -= lenRear) < lenTop) { p = Vector2.Lerp(topRear, topFront, s / lenTop); ang = angTop; }
                else { s -= lenTop; ang = angTop - s / frontRadius; p = frontCentre + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * frontRadius; }
                pads[i].localPosition = new Vector3(0f, p.y, p.x);
                pads[i].localRotation = Quaternion.Euler(90f - ang * Mathf.Rad2Deg, 0f, 0f);
            }
        }
        if (sprocket != null) sprocket.localRotation = Quaternion.Euler(Travel / rearRadius * Mathf.Rad2Deg, 0f, 0f);
        if (idler != null) idler.localRotation = Quaternion.Euler(Travel / frontRadius * Mathf.Rad2Deg, 0f, 0f);
    }
}
