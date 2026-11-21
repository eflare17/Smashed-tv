// Characters built from boxes of voxels in code, the way Smashed builds them (godot/arcade/smash/smash_vox.gd):
// boxes are [x0, y0, z0, x1, y1, z1] inclusive voxel coordinates with a colour; only the faces with no neighbour
// are kept.  Front of a character is +Z, its right hand is -X, feet at y = 0.
// The colours are Smashed's, exactly.  Smashed's voxels are 0.1 m; the arena draws them at 0.15 m (Grunts.Scale),
// so a grunt stands about 1.65 m next to the 1.8 m player.
using System.Collections.Generic;
using UnityEngine;

public static class VoxModel
{
    public struct B { public int x0, y0, z0, x1, y1, z1; public Color c; public B(int a, int b, int cc, int d, int e, int f, Color col) { x0 = a; y0 = b; z0 = cc; x1 = d; y1 = e; z1 = f; c = col; } }

    // Smashed's colours (smash_vox.gd)
    public static readonly Color Skin = new Color(0.95f, 0.72f, 0.52f);
    public static readonly Color GruntShirt = new Color(0.36f, 0.62f, 0.22f);
    public static readonly Color GruntPants = new Color(0.42f, 0.3f, 0.18f);
    public static readonly Color GruntCap = new Color(0.85f, 0.15f, 0.12f);
    public static readonly Color Boot = new Color(0.12f, 0.1f, 0.1f);
    public static readonly Color Eye = new Color(0.1f, 0.05f, 0.05f);
    public static readonly Color Blood = new Color(0.6f, 0.03f, 0.03f);

    /// Smashed's grunt gib colours (chunks pick from these).
    public static readonly Color[] GruntGibs = { GruntShirt, GruntShirt, Skin, GruntPants, Blood, Blood, GruntCap };

    /// Smashed's grunt (_grunt_boxes), walk frame 0 or 1: legs one forward one back, swapped between the frames,
    /// arms reaching for the player.
    public static B[] GruntBoxes(int frame)
    {
        int a = frame == 0 ? 1 : 0, b = 1 - a;
        return new[]
        {
            new B(1, 0, 1 + a, 2, 3, 2 + a, GruntPants), new B(4, 0, 1 + b, 5, 3, 2 + b, GruntPants),
            new B(1, 0, 1 + a, 2, 0, 2 + a, Boot), new B(4, 0, 1 + b, 5, 0, 2 + b, Boot),
            new B(1, 4, 0, 5, 7, 3, GruntShirt),
            new B(0, 6, 1, 0, 7, 3 + a, Skin), new B(6, 6, 1, 6, 7, 3 + b, Skin),
            new B(0, 5, 1, 0, 5, 2, GruntShirt), new B(6, 5, 1, 6, 5, 2, GruntShirt),
            new B(2, 8, 0, 4, 10, 3, Skin),
            new B(2, 10, 0, 4, 10, 3, GruntCap), new B(2, 9, 0, 4, 9, 0, GruntCap),
            new B(2, 9, 3, 2, 9, 3, Eye), new B(4, 9, 3, 4, 9, 3, Eye),
        };
    }

    /// Smashed's rocket (rocket_mesh), pointing +Z, centred on the origin.
    public static B[] RocketBoxes()
    {
        return new[]
        {
            new B(0, 0, 0, 1, 1, 3, new Color(0.9f, 0.2f, 0.15f)), new B(0, 0, 4, 1, 1, 4, new Color(0.8f, 0.8f, 0.8f)),
            new B(0, 0, -1, 1, 1, -1, new Color(1.0f, 0.8f, 0.2f)),
        };
    }

    static readonly Vector3Int[] Dirs = { new Vector3Int(1, 0, 0), new Vector3Int(-1, 0, 0), new Vector3Int(0, 1, 0), new Vector3Int(0, -1, 0), new Vector3Int(0, 0, 1), new Vector3Int(0, 0, -1) };
    static readonly Vector3[][] Corners =
    {
        new[] { new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1) },
        new[] { new Vector3(0, 0, 0), new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0) },
        new[] { new Vector3(0, 1, 0), new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 1, 0) },
        new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(1, 0, 1), new Vector3(0, 0, 1) },
        new[] { new Vector3(0, 0, 1), new Vector3(1, 0, 1), new Vector3(1, 1, 1), new Vector3(0, 1, 1) },
        new[] { new Vector3(0, 0, 0), new Vector3(0, 1, 0), new Vector3(1, 1, 0), new Vector3(1, 0, 0) },
    };

    /// Voxel boxes -> one mesh of the outside faces.  `centre` (in voxels) lands on the origin; `size` is one voxel in metres.
    public static Mesh FromBoxes(B[] boxes, Vector3 centre, float size)
    {
        var grid = new Dictionary<Vector3Int, Color>();
        foreach (var bx in boxes)
            for (int x = bx.x0; x <= bx.x1; x++)
                for (int y = bx.y0; y <= bx.y1; y++)
                    for (int z = bx.z0; z <= bx.z1; z++)
                        grid[new Vector3Int(x, y, z)] = bx.c;
        var verts = new List<Vector3>(); var norms = new List<Vector3>(); var cols = new List<Color>(); var tris = new List<int>();
        foreach (var kv in grid)
            for (int f = 0; f < 6; f++)
            {
                if (grid.ContainsKey(kv.Key + Dirs[f])) continue;
                int s = verts.Count;
                for (int k = 0; k < 4; k++) { verts.Add(((Vector3)kv.Key + Corners[f][k] - centre) * size); norms.Add(Dirs[f]); cols.Add(kv.Value); }
                // wound so the face looks outward
                Vector3 n = Dirs[f], e1 = Corners[f][1] - Corners[f][0], e2 = Corners[f][2] - Corners[f][0];
                if (Vector3.Dot(Vector3.Cross(e1, e2), n) > 0f) { tris.Add(s); tris.Add(s + 2); tris.Add(s + 1); tris.Add(s); tris.Add(s + 3); tris.Add(s + 2); }
                else { tris.Add(s); tris.Add(s + 1); tris.Add(s + 2); tris.Add(s); tris.Add(s + 2); tris.Add(s + 3); }
            }
        var m = new Mesh();
        m.SetVertices(verts); m.SetNormals(norms); m.SetColors(cols); m.SetTriangles(tris, 0);
        m.RecalculateBounds();
        return m;
    }
}
