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

    static Color Shade(Color c, float k) { return new Color(c.r * k, c.g * k, c.b * k); }

    /// The same grunt drawn in the ground's own 6.25 cm voxels (VoxelWorld.Voxel): 24 tall (1.5 m), 15 wide, 8 deep.
    /// Smashed's shape and colours kept; the finer blocks add a cap brim, nose, mouth, hands, a belt with a buckle and
    /// shading on the shirt.  Walk frame 0 or 1 as before (legs and arms one forward, swapped).  NOT USED IN THE GAME
    /// YET: only the picture (ArenaBuilder.GruntPicture) draws it, until the owner says yes.
    public static B[] GruntBoxesFine(int frame)
    {
        int a = frame == 0 ? 2 : 0, b = 2 - a;          // walk offsets, 2 voxels (12.5 cm)
        Color shirtDark = Shade(GruntShirt, 0.78f), shirtLight = Shade(GruntShirt, 1.12f), hand = Shade(Skin, 0.9f);
        Color belt = new Color(0.2f, 0.13f, 0.07f), buckle = new Color(0.78f, 0.66f, 0.3f), mouth = new Color(0.45f, 0.12f, 0.1f);
        Color capDark = Shade(GruntCap, 0.8f), pantsDark = Shade(GruntPants, 0.82f);
        var l = new List<B>
        {
            // legs: pants y2-8, boots y0-1 with a toe; hips join them at the top
            new B(3, 2, 1 + a, 6, 8, 4 + a, GruntPants), new B(8, 2, 1 + b, 11, 8, 4 + b, GruntPants),
            new B(3, 2, 1 + a, 6, 2, 4 + a, pantsDark), new B(8, 2, 1 + b, 11, 2, 4 + b, pantsDark),   // turn-ups
            new B(3, 0, 1 + a, 6, 1, 5 + a, Boot), new B(8, 0, 1 + b, 11, 1, 5 + b, Boot),
            new B(3, 7, 1, 11, 8, 6, GruntPants),
            // belt and buckle
            new B(2, 9, 0, 12, 9, 7, belt), new B(6, 9, 7, 8, 9, 7, buckle),
            // shirt y10-16: darker at the bottom and the sides, lighter over the shoulders
            new B(2, 10, 0, 12, 16, 7, GruntShirt),
            new B(2, 10, 0, 12, 10, 7, shirtDark), new B(2, 11, 0, 2, 15, 7, shirtDark), new B(12, 11, 0, 12, 15, 7, shirtDark),
            new B(3, 16, 1, 11, 16, 6, shirtLight),
            // arms reaching forward: green sleeve, skin forearm, a bigger hand
            new B(0, 13, 2, 1, 16, 5, GruntShirt), new B(13, 13, 2, 14, 16, 5, GruntShirt),
            new B(0, 14, 6, 1, 16, 7 + a, Skin), new B(13, 14, 6, 14, 16, 7 + b, Skin),
            new B(0, 13, 8 + a, 1, 16, 9 + a, hand), new B(13, 13, 8 + b, 14, 16, 9 + b, hand),
            // head y17-21
            new B(4, 17, 0, 10, 21, 7, Skin),
            new B(5, 19, 7, 6, 20, 7, Eye), new B(8, 19, 7, 9, 20, 7, Eye),
            new B(7, 18, 8, 7, 19, 8, hand),                                   // nose
            new B(6, 17, 7, 8, 17, 7, mouth),
            // cap y22-23 with a brim out the front
            new B(4, 22, 0, 10, 23, 7, GruntCap), new B(5, 23, 1, 9, 23, 6, Shade(GruntCap, 1.08f)),
            new B(4, 22, 8, 10, 22, 9, capDark),
        };
        return l.ToArray();
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
        bool linear = QualitySettings.activeColorSpace == ColorSpace.Linear;   // vertex colours aren't converted for us
        foreach (var key in new List<Vector3Int>(grid.Keys)) if (linear) grid[key] = grid[key].linear;
        foreach (var kv in grid)
            for (int f = 0; f < 6; f++)
            {
                if (grid.ContainsKey(kv.Key + Dirs[f])) continue;
                int s = verts.Count;
                for (int k = 0; k < 4; k++) { verts.Add(((Vector3)kv.Key + Corners[f][k] - centre) * size); norms.Add(Dirs[f]); cols.Add(kv.Value); }
                // wound so the face looks outward (Unity: Cross(b - a, c - a) points out of a front face)
                Vector3 n = Dirs[f], e1 = Corners[f][1] - Corners[f][0], e2 = Corners[f][2] - Corners[f][0];
                if (Vector3.Dot(Vector3.Cross(e1, e2), n) > 0f) { tris.Add(s); tris.Add(s + 1); tris.Add(s + 2); tris.Add(s); tris.Add(s + 2); tris.Add(s + 3); }
                else { tris.Add(s); tris.Add(s + 2); tris.Add(s + 1); tris.Add(s); tris.Add(s + 3); tris.Add(s + 2); }
            }
        var m = new Mesh();
        m.SetVertices(verts); m.SetNormals(norms); m.SetColors(cols); m.SetTriangles(tris, 0);
        m.RecalculateBounds();
        return m;
    }
}
