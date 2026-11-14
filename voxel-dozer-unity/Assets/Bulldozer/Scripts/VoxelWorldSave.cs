// Saving and loading the ground.
//
// The ground is 528 MB, far too big to write out each time.  But it is always made the same way from the same
// recipe (GenerateJob), so a save only has to hold what has changed since then: every 2 m chunk that anything has
// touched (a "touched" bit, kept in dirty[], set by Mark), plus the per-column surface heights and grass, every
// dirt tally, and the loose clods in flight.  Loading makes the ground afresh and lays the saved chunks over it.
//
// Volume is exact across a save and a load: the same voxels, the same tallies and the same clods come back.
using System.IO;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

public partial class VoxelWorld
{
    const int SaveVersion = 2;                             // 2: parts remember being found
    const int ChunkBytes = CS * CS * CS;

    /// Dirt that is not ground right now, counted afresh: tallies, shovel, cart and clods.
    public long LooseTotal()
    {
        long sum = 0;
        for (int i = 0; i < bladeLoad.Length; i++) sum += bladeLoad[i] + shovelLoad[i] + cartLoad[i];
        int n = cCount[0];
        for (int i = 0; i < n; i++) sum += cCnt[i];
        return sum;
    }

    /// A fingerprint of the surface heights, to check a load really brought the ground back.
    public ulong TopHash()
    {
        ulong h = 1469598103934665603UL;
        for (int i = 0; i < top.Length; i++) { h ^= top[i]; h *= 1099511628211UL; }
        return h;
    }

    public int TouchedChunks()
    {
        int n = 0;
        for (int i = 0; i < dirty.Length; i++) if ((dirty[i] & 2) != 0) n++;
        return n;
    }

    static void WriteBytes(BinaryWriter w, byte[] b) { w.Write(b.Length); w.Write(b); }
    static byte[] ReadBytes(BinaryReader r) { int n = r.ReadInt32(); return r.ReadBytes(n); }

    static void WriteInts(BinaryWriter w, NativeArray<int> a) { w.Write(a.Length); for (int i = 0; i < a.Length; i++) w.Write(a[i]); }
    static void ReadInts(BinaryReader r, NativeArray<int> a) { int n = r.ReadInt32(); for (int i = 0; i < n; i++) { int v = r.ReadInt32(); if (i < a.Length) a[i] = v; } }

    public void WriteSave(BinaryWriter w)
    {
        w.Write(SaveVersion);
        w.Write(NX); w.Write(NY); w.Write(NZ);
        w.Write(SolidCount); w.Write(StartTotal);

        // touched chunks: index, then its 32 x 32 x 32 voxels, a 32-voxel column at a time
        var buf = new byte[ChunkBytes];
        int touched = TouchedChunks();
        w.Write(touched);
        for (int c = 0; c < dirty.Length; c++)
        {
            if ((dirty[c] & 2) == 0) continue;
            int cx = c % CX, cy = (c / CX) % CY, cz = c / (CX * CY), o = 0;
            for (int z = cz * CS; z < cz * CS + CS; z++)
                for (int x = cx * CS; x < cx * CS + CS; x++)
                {
                    NativeArray<byte>.Copy(vox, cy * CS + NY * (x + NX * z), buf, o, CS);
                    o += CS;
                }
            w.Write(c);
            w.Write(buf);
        }

        WriteBytes(w, top.Reinterpret<byte>(sizeof(ushort)).ToArray());
        WriteBytes(w, grass.ToArray());
        WriteInts(w, bladeLoad); WriteInts(w, shovelLoad); WriteInts(w, cartLoad);

        int n = cCount[0];
        w.Write(n);
        for (int i = 0; i < n; i++)
        {
            float3 p = cPos[i], v = cVel[i]; float4 q = cRot[i].value;
            w.Write(p.x); w.Write(p.y); w.Write(p.z);
            w.Write(v.x); w.Write(v.y); w.Write(v.z);
            w.Write(q.x); w.Write(q.y); w.Write(q.z); w.Write(q.w);
            w.Write(cMat[i]); w.Write(cCnt[i]); w.Write(cRest[i]); w.Write(cAge[i]);
        }
    }

    public void ReadSave(BinaryReader r)
    {
        int version = r.ReadInt32();
        if (version != SaveVersion) throw new IOException("This save was made by a different version of the game.");
        if (r.ReadInt32() != NX || r.ReadInt32() != NY || r.ReadInt32() != NZ) throw new IOException("This save is for a different size of site.");
        long solid = r.ReadInt64(), startTotal = r.ReadInt64();

        // Chunks that need redrawing afterwards: everything touched now, and everything the save touched.
        var redraw = new bool[dirty.Length];
        for (int c = 0; c < dirty.Length; c++) redraw[c] = (dirty[c] & 2) != 0;

        // the ground afresh, exactly as it was made at the start
        new GenerateJob { vox = vox, top = top, grass = grass }.Schedule(NX * NZ, 256).Complete();
        for (int c = 0; c < dirty.Length; c++) dirty[c] = 0;

        int touched = r.ReadInt32();
        for (int k = 0; k < touched; k++)
        {
            int c = r.ReadInt32();
            byte[] buf = r.ReadBytes(ChunkBytes);
            int cx = c % CX, cy = (c / CX) % CY, cz = c / (CX * CY), o = 0;
            for (int z = cz * CS; z < cz * CS + CS; z++)
                for (int x = cx * CS; x < cx * CS + CS; x++)
                {
                    NativeArray<byte>.Copy(buf, o, vox, cy * CS + NY * (x + NX * z), CS);
                    o += CS;
                }
            dirty[c] = 2;                                    // still counts as touched, for the next save
            redraw[c] = true;
        }

        byte[] topBytes = ReadBytes(r);
        top.Reinterpret<byte>(sizeof(ushort)).CopyFrom(topBytes);
        grass.CopyFrom(ReadBytes(r));
        ReadInts(r, bladeLoad); ReadInts(r, shovelLoad); ReadInts(r, cartLoad);

        int n = r.ReadInt32();
        if (n > MaxClods) n = MaxClods;
        for (int i = 0; i < n; i++)
        {
            cPos[i] = new float3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
            cVel[i] = new float3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
            cRot[i] = new quaternion(r.ReadSingle(), r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
            cMat[i] = r.ReadByte(); cCnt[i] = r.ReadByte(); cRest[i] = r.ReadSingle(); cAge[i] = r.ReadSingle();
        }
        cCount[0] = n;

        SolidCount = solid;
        StartTotal = startTotal;
        Recount();
        int inFlight = 0;
        for (int i = 0; i < n; i++) inFlight += cCnt[i];
        ClodVoxelsInFlight = inFlight;
        BermVoxels = inFlight;
        LoadVoxels = carriedOnBlade + ClodVoxelsInFlight + ShovelVoxels + CartVoxels;

        // redraw what changed, and the grass
        for (int c = 0; c < dirty.Length; c++) if (redraw[c]) dirty[c] |= 1;
        for (int pass = 0; pass < 400; pass++)
        {
            Remesh(512);
            if (LastRemeshChunks == 0) break;
        }
        grassTex.LoadRawTextureData(grass);
        grassTex.Apply(false);
    }
}
