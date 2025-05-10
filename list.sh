#!/bin/bash

# === Variabili base ===
timestamp=$(date '+%Y-%m-%d %H:%M')
skipped_count=0
rai_count=0

# === File ===
OUTPUT_FILE="world.m3u"
BACKUP_FILE="bak_list.m3u"
JSON_FILE="country.json"
RAI_FILE="rai.m3u"
README_FILE="README.md"
ARCHIVE_FILE="README.archive.md"
STATUS_FILE="status.json"

# === Canali gestiti manualmente e da escludere ===
FORCED_CHANNELS=("La7")
EXCLUDED_CHANNELS=(
  "Rai 1 Ⓖ" "Rai 2 Ⓖ" "Rai 3 Ⓖ" "Rai 4 Ⓖ"
  "Rai 5 Ⓖ" "Rai Movie Ⓖ" "Rai Premium Ⓖ"
  "Rai Gulp Ⓖ" "Rai YoYo Ⓖ" "Rai News 24 Ⓖ"
  "Rai Scuola Ⓖ" "Rai Storia Ⓖ" "Rai Sport Ⓖ"
  "Rai Radio 2 Visual Radio Ⓖ"
)

CHECK_STREAMS=true

# === Backup lista precedente ===
if [ -f "$OUTPUT_FILE" ]; then
  echo "🔄 Backup lista precedente..."
  cp "$OUTPUT_FILE" "$BACKUP_FILE"
fi

# === Inizializza file temporaneo ===
> "$OUTPUT_FILE"

# === Funzione normalizzazione nome canale ===
normalize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/\[.*?\]|\(.*?\)//g' |
    sed -E 's/\b(hd|fhd|sd|1080|720|h264|h265|plus|extra|direct|premium)\b//g' |
    sed -E 's/rete[[:space:]]*4|retequattro/rete4/g' |
    sed -E 's/canale[[:space:]]*5/canale5/g' |
    sed -E 's/italia[[:space:]]*1/italia1/g' |
    sed -E 's/tv[[:space:]]*8/tv8/g' |
    sed -E 's/[^a-z0-9]+//g' |
    tr -d '\n'
}

# === Parsing dei canali dal JSON ===
jq -r 'keys[]' "$JSON_FILE" | while IFS= read -r country; do
  echo "📦 Elaborazione $country..."
  temp_file="/tmp/temp_${country// /_}.m3u"
  > "$temp_file"

  urls=$(jq -r --arg key "$country" '.[$key] // [] | .[]' "$JSON_FILE")
  for url in $urls; do
    [[ -z "$url" ]] && continue
    curl -s "$url" >> "$temp_file"
  done

  while IFS= read -r line; do
    if [[ $line == \#EXTINF* ]]; then
      name=$(echo "$line" | cut -d',' -f2)

      for excluded in "${EXCLUDED_CHANNELS[@]}"; do
        if [[ "$name" == "$excluded" ]]; then
          echo "⛔ Escluso: $name"
          read -r _  # salta URL
          skipped_count=$((skipped_count + 1))
          continue 2
        fi
      done

      logo=$(echo "$line" | grep -o 'tvg-logo="[^"]*"' | cut -d'"' -f2)
      [[ -z "$logo" ]] && logo="https://raw.githubusercontent.com/JonathanSanfilippo/vision/refs/heads/main/frontend/img/logo.png"
      read -r url
      [[ -z "$name" || -z "$url" || "$name" =~ \[COLOR|\[B|\] ]] && continue
      tvgid=$(normalize_name "$name")

      if $CHECK_STREAMS; then
        status=$(curl -s -L -A "Mozilla/5.0" --max-time 5 --head "$url" | grep -i "^HTTP" | head -n1 | awk '{print $2}')
        force_channel=false
        for forced in "${FORCED_CHANNELS[@]}"; do
          [[ "$name" == "$forced" ]] && force_channel=true && echo "⚠️  Forzato: $name" && break
        done
        if [[ "$force_channel" == false && "$status" =~ ^(404|410|500|502|503|000)$ ]]; then
          echo "❌ $name non valido (HTTP $status)"
          skipped_count=$((skipped_count + 1))
          continue
        fi
      fi

      printf "#EXTINF:-1 tvg-name=\"%s\" tvg-logo=\"%s\" tvg-id=\"%s\" group-title=\"%s\",%s\n%s\n\n" \
        "$name" "$logo" "$tvgid" "$country" "$name" "$url" >> "$OUTPUT_FILE"
    fi
  done < "$temp_file"

  rm -f "$temp_file"
done

# === Inserisci i canali RAI in cima alla lista ===
if [[ -f "$RAI_FILE" ]]; then
  echo "📺 Inserimento canali RAI in cima a list.m3u..."
  temp_final="/tmp/final.m3u"

  echo "#EXTM3U" > "$temp_final"
  tail -n +2 "$RAI_FILE" >> "$temp_final"
  grep -v '^#EXTM3U' "$OUTPUT_FILE" >> "$temp_final"

  mv "$temp_final" "$OUTPUT_FILE"

  rai_count=$(grep -c '^#EXTINF' "$RAI_FILE")
else
  sed -i '1i#EXTM3U' "$OUTPUT_FILE"
fi

# === Conta i canali finali reali ===
valid_count=$(grep -c '^#EXTINF' "$OUTPUT_FILE")

# === Crea status.json ===
cat <<EOF > "$STATUS_FILE"
{
  "last_update": "$(date '+%H:%M')",
  "channels": $valid_count
}
EOF

echo "📄 Salvato status.json con $valid_count canali"

# === Log archivio ===
{
  echo "## 🔁 Esecuzione del $timestamp"
  echo
  echo "- Canali validi: $valid_count"
  echo "- Scartati: $skipped_count"
  [[ $rai_count -gt 0 ]] && echo "- Canali RAI aggiunti: $rai_count"
  echo
  echo "### Log"
  echo '```bash'
  journalctl --user -u list.service --since "10 minutes ago" --no-pager
  echo '```'
  echo
} >> "$ARCHIVE_FILE"

# === Rigenera README.md ===
{
  echo "## 🌐 Ultima esecuzione"
  echo
  echo "- Data: $timestamp"
  echo "- Canali validi: $valid_count"
  echo "- Scartati: $skipped_count"
  [[ $rai_count -gt 0 ]] && echo "- Canali RAI aggiunti: $rai_count"
  echo
  echo "## 🧾 Log dettagliato ultima esecuzione"
  echo
  echo '```bash'
  journalctl --user -u list.service --since "10 minutes ago" --no-pager
  echo '```'
  echo

} > "$README_FILE"

# === Commit & Push se necessario ===
if git diff --quiet && git diff --cached --quiet; then
  echo "🟢 Nessuna modifica da pushare."
else
  echo "📤 Commit & push in corso..."
  git add .
  git commit -m "🌐 server: $timestamp"
  git push origin main
fi

echo "✅ Completato. Totale canali validi: $valid_count, scartati: $skipped_count (RAI: $rai_count)"
