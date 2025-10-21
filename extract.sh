#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
SOURCE_DIR="${1:-}"
MERGE_DIR="${2:-}"

if [ -z "$SOURCE_DIR" ] || [ -z "$MERGE_DIR" ]; then
  echo "Usage: $0 <dossier_zip> <dossier_fusion>"
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Erreur : le dossier source n'existe pas : $SOURCE_DIR"
  exit 1
fi

# Forcer l'encodage UTF-8 pour éviter "Illegal byte sequence"
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

DUPLICATE_DIR="$MERGE_DIR/duplicate"

mkdir -p "$MERGE_DIR"
mkdir -p "$DUPLICATE_DIR"

echo "Extraction des ZIPs depuis : $SOURCE_DIR"
shopt -s nullglob

for zipfile in "$SOURCE_DIR"/*.zip; do
  [ -e "$zipfile" ] || continue
  echo "→ Traitement : $(basename "$zipfile")"

  TMP_DIR="$(mktemp -d)"
  # Utiliser ditto (meilleur sur mac pour gérer métadonnées et noms)
  if command -v ditto >/dev/null 2>&1; then
    # -x : extract, -k : zip archive
    if ! ditto -x -k "$zipfile" "$TMP_DIR" 2>/dev/null; then
      # si ditto échoue, fallback sur unzip en forçant UTF-8 si possible
      echo "warning: ditto a échoué, essai avec unzip..."
      LANG=en_US.UTF-8 unzip -qq "$zipfile" -d "$TMP_DIR"
    fi
  else
    # pas de ditto (cas peu probable sur Mac) -> unzip
    LANG=en_US.UTF-8 unzip -qq "$zipfile" -d "$TMP_DIR"
  fi

  # Parcours en mode binaire-safe (print0)
  find "$TMP_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    # chemin relatif à l'intérieur du zip
    rel_path="${file#$TMP_DIR/}"
    dest_file="$MERGE_DIR/$rel_path"
    dest_dir="$(dirname "$dest_file")"

    if [ -e "$dest_file" ]; then
      # doublon : déplacer dans duplicate en gardant l'arborescence relative
      dup_target="$DUPLICATE_DIR/$rel_path"
      mkdir -p "$(dirname "$dup_target")"
      echo "⚠️  Doublon : $rel_path -> $(realpath --relative-to="$PWD" "$dup_target" 2>/dev/null || echo "$dup_target")"
      # mv le fichier extrait vers duplicate
      mv -- "$file" "$dup_target"
    else
      mkdir -p "$dest_dir"
      mv -- "$file" "$dest_file"
    fi
  done

  # Supprimer dossiers vides restants dans tmp
  rm -rf "$TMP_DIR"
done

echo "✅ Extraction terminée."
echo "Fichiers fusionnés dans : $MERGE_DIR"
echo "Doublons déplacés dans : $DUPLICATE_DIR"
