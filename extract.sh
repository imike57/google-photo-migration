#!/bin/bash

echo "=== Début de la fusion des archives ZIP ==="
echo

cd "$(dirname "$0")"
mkdir -p fusion

for z in *.zip; do
  echo "📦 Extraction de : $z ..."
  tmpdir=$(mktemp -d)

  ditto -x -k "$z" "$tmpdir"

  echo "➡️  Fusion du contenu de $z ..."
  find "$tmpdir" -type f | while IFS= read -r file; do
    relpath="${file#$tmpdir/}"
    dest="fusion/$relpath"
    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ]; then
      base="${dest%.*}"
      ext="${dest##*.}"
      [[ "$base" = "$ext" ]] && ext=""
      i=2
      while [ -e "${base} ($i)${ext:+.$ext}" ]; do
        ((i++))
      done
      newfile="${base} ($i)${ext:+.$ext}"
      echo "   ⚠️  Doublon : $(basename "$relpath") → $(basename "$newfile")"
      if ! cp -p "$file" "$newfile"; then
        echo "   ❌ Erreur de copie : $file" >&2
      fi
    else
      echo "   ✅ Copie : $relpath"
      if ! cp -p "$file" "$dest"; then
        echo "   ❌ Erreur de copie : $file" >&2
      fi
    fi
  done

  rm -rf "$tmpdir"
  echo "✅ Terminé pour $z"
  echo
done

echo "=== Fusion terminée ! ==="
echo "Résultat dans : $(pwd)/fusion"
