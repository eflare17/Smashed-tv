// Records the game's own sound (what the listener hears: engine, dirt, everything) to a WAV file while filming a trailer,
// because the PC can't record its speakers.  Start with  -recordaudio <file.wav>  alongside -trailer.
// Beside it, <file.wav>.start holds the UTC time (Unix seconds) of the first sample, to line it up with a screen recording.
// The file is written as it goes (the header kept up to date), so killing the game still leaves a good file.
using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class TrailerAudio : MonoBehaviour
{
    static string path;
    readonly List<float> pending = new List<float>();
    readonly object gate = new object();
    FileStream file;
    int channels = 2, rate = 48000;
    long dataBytes;
    bool gotFirst;
    double firstUtc;

    /// Puts the recorder on the listener, if -recordaudio was given.  Safe to call more than once.
    public static void Attach()
    {
        if (path == null)
        {
            var args = System.Environment.GetCommandLineArgs();
            path = "";
            for (int i = 0; i + 1 < args.Length; i++) if (args[i].ToLowerInvariant() == "-recordaudio") path = args[i + 1];
        }
        if (path == "") return;
        var l = FindFirstObjectByType<AudioListener>();
        if (l == null || l.GetComponent<TrailerAudio>() != null) return;
        l.gameObject.AddComponent<TrailerAudio>();
    }

    void Awake()
    {
        rate = AudioSettings.outputSampleRate;
        file = new FileStream(path, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
        file.Write(new byte[44], 0, 44);
    }

    void OnAudioFilterRead(float[] data, int ch)
    {
        lock (gate)
        {
            if (!gotFirst) { gotFirst = true; firstUtc = (System.DateTime.UtcNow - new System.DateTime(1970, 1, 1)).TotalSeconds; channels = ch; }
            pending.AddRange(data);
        }
    }

    void Update() { Flush(); }
    void OnDestroy() { Flush(); if (file != null) { file.Dispose(); file = null; } }
    void OnApplicationQuit() { Flush(); }

    void Flush()
    {
        if (file == null) return;
        float[] buf;
        bool first;
        lock (gate)
        {
            if (pending.Count == 0) return;
            buf = pending.ToArray(); pending.Clear();
            first = gotFirst && dataBytes == 0;
        }
        if (first) File.WriteAllText(path + ".start", firstUtc.ToString("F4", System.Globalization.CultureInfo.InvariantCulture));
        var bytes = new byte[buf.Length * 2];
        for (int i = 0; i < buf.Length; i++)
        {
            short s = (short)Mathf.Clamp(Mathf.RoundToInt(buf[i] * 32767f), -32768, 32767);
            bytes[i * 2] = (byte)(s & 0xff); bytes[i * 2 + 1] = (byte)((s >> 8) & 0xff);
        }
        file.Seek(0, SeekOrigin.End);
        file.Write(bytes, 0, bytes.Length);
        dataBytes += bytes.Length;
        // the header, with the sizes so far
        var h = new BinaryWriter(new MemoryStream());
        h.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); h.Write((int)(36 + dataBytes)); h.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
        h.Write(16); h.Write((short)1); h.Write((short)channels); h.Write(rate); h.Write(rate * channels * 2); h.Write((short)(channels * 2)); h.Write((short)16);
        h.Write(System.Text.Encoding.ASCII.GetBytes("data")); h.Write((int)dataBytes);
        var hb = ((MemoryStream)h.BaseStream).ToArray();
        file.Seek(0, SeekOrigin.Begin); file.Write(hb, 0, hb.Length);
        file.Flush();
    }
}
