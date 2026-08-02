#!/bin/zsh
# Renders the aqua App Store screenshot set (5 iPhone + 5 iPad) from raw
# simulator captures via headless Chrome. Run from this directory.
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd "$(dirname "$0")"
mkdir -p ../final ../final-ipad

# name|headline (HTML, ~ becomes <br>)|iphone capture|ipad capture|tilt
shots=(
  '01-sink-the-fleet|Sink the~<span class="accent">pirate fleet!</span>|sim_battle1|ipad_battle1|-3'
  '02-arm-special-cannons|Arm your~<span class="accent">special cannons</span>|sim_armory|ipad_armory|3'
  '03-duel-captains|Duel four~<span class="accent">salty captains</span>|sim_captains|ipad_captains|-3'
  '04-collect-fleets|Collect~<span class="accent">legendary fleets</span>|sim_shipyard|ipad_shipyard|3'
  '05-battle-online|Battle~<span class="accent">friends online</span>|sim_battle2|ipad_battle2|-3'
)

for s in "${shots[@]}"; do
  IFS='|' read -r name headline iphone ipad tilt <<< "$s"
  headline="${headline//\~/<br>}"

  sed -e "s|HEADLINE_HTML|$headline|" -e "s|SCREEN_SRC|../sim/$iphone.png|" \
      -e "s|TILT|$tilt|" shot.html > "_$name-iphone.html"
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
      --screenshot="_$name-iphone.png" --window-size=1320,2868 \
      "file://$PWD/_$name-iphone.html" 2>/dev/null
  sips -s format jpeg -s formatOptions 92 "_$name-iphone.png" \
      --out "../final/$name.jpg" >/dev/null

  sed -e "s|HEADLINE_HTML|$headline|" -e "s|SCREEN_SRC|../sim-ipad/$ipad.png|" \
      -e "s|TILT|$tilt|" shot-ipad.html > "_$name-ipad.html"
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
      --screenshot="_$name-ipad.png" --window-size=2064,2752 \
      "file://$PWD/_$name-ipad.html" 2>/dev/null
  sips -s format jpeg -s formatOptions 92 "_$name-ipad.png" \
      --out "../final-ipad/$name.jpg" >/dev/null

  echo "built $name"
done
