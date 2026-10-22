#!/usr/bin/env python3
# The trailer's MP4 (render.sh): encode.py game.avi music.wav out.mp4 "first frames". Owned by the voxel session.
# the final MP4: every shot's first frame replaced by its second (the frame a cut's new bodies aren't posed yet),
# the loading cut off, the game's sound under the music
import subprocess, sys
avi, music, out, firsts = sys.argv[1], sys.argv[2], sys.argv[3], [int(x) for x in sys.argv[4].split()]
n = len(firsts)
g = [f"[0:v]split={n + 1}" + "".join(f"[s{i}]" for i in range(n + 1))]
cur = "s0"
for i, k in enumerate(firsts):
    g.append(f"[{cur}][s{i + 1}]freezeframes=first={k}:last={k}:replace={k + 1}[v{i}]")
    cur = f"v{i}"
g.append(f"[{cur}]trim=start_frame=60,setpts=PTS-STARTPTS[v]")
g.append("[0:a]atrim=start=2.0,asetpts=PTS-STARTPTS,volume=0.6[ga]")
g.append("[1:a]volume=0.95[m]")
g.append("[ga][m]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.95[a]")
cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", avi, "-i", music, "-filter_complex", ";".join(g),
       "-map", "[v]", "-map", "[a]", "-t", "57.5", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
       "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
subprocess.run(cmd, check=True)
print("wrote", out)
