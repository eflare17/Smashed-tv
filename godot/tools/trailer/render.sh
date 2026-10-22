#!/bin/bash
# The trailer, start to finish: the music made (make_music.py), the shot list played and recorded frame by frame by
# Godot's movie maker (trailer.gd, Forward+, 30 fps: as slow as it needs, every frame the same), the game's own sound
# mixed under the music, the loading cut off, an H.264 MP4 out (encode.py, first_frames.py). Usage: render.sh out.mp4 [workdir].
# Under a display (xvfb-run on a server; VK_ICD_FILENAMES for a software Vulkan if there's no GPU).
# Owned by the voxel session.
set -e
OUT=${1:-trailer.mp4}
WORK=${2:-$(mktemp -d)}
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT_DIR="$(cd "$HERE/../.." && pwd)"
mkdir -p "$WORK"
python3 -I "$HERE/make_music.py" "$WORK/music.wav"
RUN=(godot --path "$GODOT_DIR" --rendering-method forward_plus --resolution 1280x720 --write-movie "$WORK/game.avi"
	--fixed-fps 30 -s res://tools/trailer/trailer.gd -- --nosave --godmode --quality=ultra)
if [ -z "$DISPLAY" ]; then
	xvfb-run -a -s "-screen 0 1280x720x24" "${RUN[@]}"
else
	"${RUN[@]}"
fi
# every shot's first frame found (small frames: where the picture changes most at each cut) and replaced by its second
# (a cut's new bodies aren't posed till the frame after), the loading (2 s) off the front, the game's sound under the music
mkdir -p "$WORK/fr"
ffmpeg -hide_banner -loglevel error -y -i "$WORK/game.avi" -vf scale=320:180 -start_number 0 "$WORK/fr/f%d.png"
python3 -I "$HERE/encode.py" "$WORK/game.avi" "$WORK/music.wav" "$OUT" "$(python3 -I "$HERE/first_frames.py" "$WORK/fr")"
echo "trailer: $OUT"
