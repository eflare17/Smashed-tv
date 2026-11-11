using System;
using UnityEngine;

namespace Digger
{
    /// <summary>
    /// Terrain the blade can cut, push and pile up. Heights are cached in an array, edited
    /// in small rectangles around the blade, and written back to the Terrain (and its
    /// collider) every physics step. Loose soil slumps until no slope is steeper than the
    /// angle of repose, so pushed dirt forms natural piles and windrows.
    ///
    /// The saved TerrainData asset is never touched: a runtime copy is made on Awake.
    /// </summary>
    [RequireComponent(typeof(Terrain))]
    public class DeformableGround : MonoBehaviour
    {
        [Tooltip("Loose soil slumps until no slope is steeper than this (degrees).")]
        public float reposeAngle = 37f;
        [Tooltip("Slump passes per physics step around the blade.")]
        public int relaxIterations = 6;
        [Tooltip("Share of the over-steep difference moved per pass (0..0.5).")]
        [Range(0.05f, 0.5f)] public float slumpRate = 0.4f;
        [Tooltip("Terrain layer painted where soil has been cut or dumped.")]
        public int freshSoilLayer = 1;
        [Tooltip("How quickly disturbed ground turns to fresh soil colour.")]
        public float freshPaintRate = 0.35f;
        [Tooltip("Seconds between texture (alphamap) refreshes.")]
        public float paintInterval = 0.2f;

        /// <summary>Raised after heights change (rectangle in heightmap samples). A network layer can replicate these.</summary>
        public event Action<RectInt> HeightsChanged;

        public struct PassResult
        {
            /// <summary>Soil cut from under the blade this step (m³).</summary>
            public float cutVolume;
            /// <summary>Soil heaped against the blade face right now (m³).</summary>
            public float loadVolume;
        }

        Terrain terrain;
        TerrainData data;
        float[,] h, originalH;        // normalized heights [z, x]
        float[,,] alpha, originalAlpha;
        int res, aRes, layers;
        float sizeY, cellX, cellZ;
        Vector3 origin;
        int dx0, dz0, dx1, dz1; bool dirty;
        int ax0, az0, ax1, az1; bool alphaDirty;
        float paintTimer;
        readonly float[] binVol = new float[40];
        readonly float[] binWeight = new float[40];

        public Terrain Terrain { get { return terrain; } }
        public float CellArea { get { return cellX * cellZ; } }

        void Awake()
        {
            terrain = GetComponent<Terrain>();
            var source = terrain.terrainData;
            data = Instantiate(source);
            data.name = source.name + " (runtime)";
            terrain.terrainData = data;
            var col = GetComponent<TerrainCollider>();
            if (col) col.terrainData = data;

            res = data.heightmapResolution;
            sizeY = data.size.y;
            cellX = data.size.x / (res - 1);
            cellZ = data.size.z / (res - 1);
            origin = terrain.transform.position;
            h = data.GetHeights(0, 0, res, res);
            originalH = (float[,])h.Clone();

            aRes = data.alphamapResolution;
            layers = data.alphamapLayers;
            if (layers > freshSoilLayer)
            {
                alpha = data.GetAlphamaps(0, 0, aRes, aRes);
                originalAlpha = (float[,,])alpha.Clone();
            }
        }

        void Update()
        {
            paintTimer += Time.deltaTime;
            if (alphaDirty && paintTimer >= paintInterval)
            {
                paintTimer = 0f;
                FlushAlpha();
            }
        }

        float WorldY(float n) { return origin.y + n * sizeY; }
        float NormY(float y) { return (y - origin.y) / sizeY; }

        /// <summary>Ground height at a world position (bilinear).</summary>
        public float WorldHeight(float x, float z)
        {
            if (h == null) return origin.y;
            float fx = Mathf.Clamp((x - origin.x) / cellX, 0f, res - 1.001f);
            float fz = Mathf.Clamp((z - origin.z) / cellZ, 0f, res - 1.001f);
            int ix = (int)fx, iz = (int)fz;
            float tx = fx - ix, tz = fz - iz;
            float a = Mathf.Lerp(h[iz, ix], h[iz, ix + 1], tx);
            float b = Mathf.Lerp(h[iz + 1, ix], h[iz + 1, ix + 1], tx);
            return WorldY(Mathf.Lerp(a, b, tz));
        }

        /// <summary>
        /// One physics step of a blade. <paramref name="left"/> and <paramref name="right"/> are the
        /// ends of the cutting edge (world), <paramref name="face"/> the way the blade faces,
        /// <paramref name="velocity"/> the blade's velocity. Soil above the cutting edge is cut and
        /// heaped just ahead of the blade (or behind it when back-dragging); when the blade is angled
        /// to the direction of travel the soil slides toward the trailing end and spills off as a windrow.
        /// </summary>
        public PassResult BladePass(Vector3 left, Vector3 right, Vector3 face, Vector3 velocity, float bladeHeight)
        {
            var r = new PassResult();
            if (h == null) return r;

            var L = new Vector2(left.x, left.z);
            var R = new Vector2(right.x, right.z);
            Vector2 along = R - L;
            float width = along.magnitude;
            if (width < 0.2f) return r;
            along /= width;
            var fwd = new Vector2(face.x, face.z);
            fwd -= along * Vector2.Dot(fwd, along);
            if (fwd.sqrMagnitude < 1e-4f) return r;
            fwd.Normalize();

            var travel = new Vector2(velocity.x, velocity.z);
            int dir = Vector2.Dot(travel, fwd) < -0.05f ? -1 : 1;
            float slide = 0f;
            if (travel.sqrMagnitude > 0.0025f) slide = -Vector2.Dot(along, travel.normalized) * 0.45f * dir;

            const float band = 0.35f;     // depth of ground under the blade that gets cut
            const float gap = 0.12f;      // soil lands this far from the cutting edge
            const float depth = 0.8f;     // ...spread over this depth
            const float reach = 1.6f;     // how far ahead soil still counts as blade load
            int bins = Mathf.Clamp(Mathf.CeilToInt(width / 0.25f), 4, binVol.Length);
            for (int i = 0; i < bins; i++) { binVol[i] = 0f; binWeight[i] = 0f; }

            float pad = band + gap + depth + reach + 0.6f + width * Mathf.Abs(slide);
            int x0 = Mathf.Clamp(Mathf.FloorToInt((Mathf.Min(left.x, right.x) - pad - origin.x) / cellX), 1, res - 2);
            int x1 = Mathf.Clamp(Mathf.CeilToInt((Mathf.Max(left.x, right.x) + pad - origin.x) / cellX), 1, res - 2);
            int z0 = Mathf.Clamp(Mathf.FloorToInt((Mathf.Min(left.z, right.z) - pad - origin.z) / cellZ), 1, res - 2);
            int z1 = Mathf.Clamp(Mathf.CeilToInt((Mathf.Max(left.z, right.z) + pad - origin.z) / cellZ), 1, res - 2);
            if (x1 <= x0 || z1 <= z0) return r;
            float area = cellX * cellZ;

            // Pass 1: cut everything above the cutting edge under the blade; measure the heap ahead.
            for (int z = z0; z <= z1; z++)
            {
                for (int x = x0; x <= x1; x++)
                {
                    var p = new Vector2(origin.x + x * cellX, origin.z + z * cellZ) - L;
                    float u = Vector2.Dot(p, along) / width;
                    if (u < 0f || u > 1f) continue;
                    float w = Vector2.Dot(p, fwd) * dir;
                    float edgeY = Mathf.Lerp(left.y, right.y, u);
                    float hy = WorldY(h[z, x]);
                    if (w >= -band && w <= 0.05f)
                    {
                        if (hy > edgeY)
                        {
                            float ex = hy - edgeY;
                            h[z, x] = NormY(edgeY);
                            int b = Mathf.Min(bins - 1, (int)(u * bins));
                            binVol[b] += ex * area;
                            r.cutVolume += ex * area;
                            Touch(x, z, true);
                        }
                    }
                    else if (w > 0.05f && w < reach && hy > edgeY)
                    {
                        r.loadVolume += Mathf.Min(hy - edgeY, bladeHeight) * area;
                    }
                }
            }

            if (r.cutVolume > 0f)
            {
                // Pass 2: weights of the landing zone for each strip of blade.
                for (int pass = 0; pass < 2; pass++)
                {
                    for (int z = z0; z <= z1; z++)
                    {
                        for (int x = x0; x <= x1; x++)
                        {
                            var p = new Vector2(origin.x + x * cellX, origin.z + z * cellZ) - L;
                            float w = Vector2.Dot(p, fwd) * dir - gap;
                            if (w < 0f || w > depth) continue;
                            float u = Vector2.Dot(p, along) / width - slide;
                            int b = Mathf.FloorToInt(u * bins);
                            if (b < 0 || b >= bins) continue;
                            float weight = 1f - w / depth;
                            if (pass == 0) { binWeight[b] += weight; continue; }
                            if (binWeight[b] <= 0f) continue;
                            float add = binVol[b] * weight / binWeight[b] / area;
                            h[z, x] = Mathf.Min(1f, h[z, x] + add / sizeY);
                            Touch(x, z, true);
                        }
                    }
                }
            }

            if (dirty) Relax(x0 - 2, z0 - 2, x1 + 2, z1 + 2);
            Flush();
            return r;
        }

        void Relax(int x0, int z0, int x1, int z1)
        {
            x0 = Mathf.Clamp(x0, 0, res - 2); z0 = Mathf.Clamp(z0, 0, res - 2);
            x1 = Mathf.Clamp(x1, 0, res - 2); z1 = Mathf.Clamp(z1, 0, res - 2);
            float tan = Mathf.Tan(reposeAngle * Mathf.Deg2Rad);
            float maxX = tan * cellX / sizeY, maxZ = tan * cellZ / sizeY;
            for (int it = 0; it < relaxIterations; it++)
            {
                for (int z = z0; z <= z1; z++)
                {
                    for (int x = x0; x <= x1; x++)
                    {
                        Settle(x, z, x + 1, z, maxX);
                        Settle(x, z, x, z + 1, maxZ);
                    }
                }
            }
        }

        void Settle(int xa, int za, int xb, int zb, float max)
        {
            float d = h[za, xa] - h[zb, xb];
            if (d > max)
            {
                float m = (d - max) * slumpRate;
                h[za, xa] -= m; h[zb, xb] += m;
                Touch(xa, za, false); Touch(xb, zb, false);
            }
            else if (-d > max)
            {
                float m = (-d - max) * slumpRate;
                h[zb, xb] -= m; h[za, xa] += m;
                Touch(xa, za, false); Touch(xb, zb, false);
            }
        }

        void Touch(int x, int z, bool paint)
        {
            if (!dirty) { dx0 = dx1 = x; dz0 = dz1 = z; dirty = true; }
            else
            {
                if (x < dx0) dx0 = x; if (x > dx1) dx1 = x;
                if (z < dz0) dz0 = z; if (z > dz1) dz1 = z;
            }
            if (!paint || alpha == null) return;
            int ax = Mathf.Clamp(Mathf.RoundToInt(x * (aRes - 1f) / (res - 1f)), 0, aRes - 1);
            int az = Mathf.Clamp(Mathf.RoundToInt(z * (aRes - 1f) / (res - 1f)), 0, aRes - 1);
            float cur = alpha[az, ax, freshSoilLayer];
            if (cur >= 0.999f) return;
            float target = Mathf.Min(1f, cur + freshPaintRate);
            float rest = 1f - cur;
            float scale = rest > 1e-4f ? (1f - target) / rest : 0f;
            for (int l = 0; l < layers; l++)
                alpha[az, ax, l] = l == freshSoilLayer ? target : alpha[az, ax, l] * scale;
            if (!alphaDirty) { ax0 = ax1 = ax; az0 = az1 = az; alphaDirty = true; }
            else
            {
                if (ax < ax0) ax0 = ax; if (ax > ax1) ax1 = ax;
                if (az < az0) az0 = az; if (az > az1) az1 = az;
            }
        }

        void Flush()
        {
            if (!dirty) return;
            dirty = false;
            int w = dx1 - dx0 + 1, d = dz1 - dz0 + 1;
            var block = new float[d, w];
            for (int j = 0; j < d; j++)
                for (int i = 0; i < w; i++)
                    block[j, i] = h[dz0 + j, dx0 + i];
            // SetHeights updates the rendered terrain and the collider straight away.
            data.SetHeights(dx0, dz0, block);
            var handler = HeightsChanged;
            if (handler != null) handler(new RectInt(dx0, dz0, w, d));
        }

        void FlushAlpha()
        {
            if (!alphaDirty || alpha == null) return;
            alphaDirty = false;
            int w = ax1 - ax0 + 1, d = az1 - az0 + 1;
            var block = new float[d, w, layers];
            for (int j = 0; j < d; j++)
                for (int i = 0; i < w; i++)
                    for (int l = 0; l < layers; l++)
                        block[j, i, l] = alpha[az0 + j, ax0 + i, l];
            data.SetAlphamaps(ax0, az0, block);
        }

        /// <summary>Puts the yard back the way it was built.</summary>
        public void ResetGround()
        {
            if (originalH == null) return;
            h = (float[,])originalH.Clone();
            data.SetHeights(0, 0, h);
            if (originalAlpha != null)
            {
                alpha = (float[,,])originalAlpha.Clone();
                data.SetAlphamaps(0, 0, alpha);
            }
            dirty = alphaDirty = false;
            var handler = HeightsChanged;
            if (handler != null) handler(new RectInt(0, 0, res, res));
        }
    }
}
