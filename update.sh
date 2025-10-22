#!/usr/bin/env bash
# ==========================================================
# update_exif_from_json.sh
# Met à jour les métadonnées EXIF (date) des photos Google Photos
# en lisant le champ "title" dans chaque fichier JSON Takeout.
# Évite les process-substitutions -> pas d'erreur '<'
# Compatible macOS / Linux
# ==========================================================

# Si on n'est pas sous bash, relance le script avec bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

# --- Paramètres / vérifications --------------------------
if [ $# -lt 1 ]; then
    echo "❌ Utilisation : $0 <dossier_export_GooglePhotos>"
    exit 1
fi

ROOT_DIR="$1"

if [ ! -d "$ROOT_DIR" ]; then
    echo "❌ Le dossier spécifié n'existe pas : $ROOT_DIR"
    exit 1
fi

for cmd in jq exiftool; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Erreur : la commande '$cmd' est requise. Installe-la (brew/apt)"
        exit 1
    fi
done

echo "🔍 Parcours de : $ROOT_DIR"
echo "---------------------------------------------------"

# Fonction de formatage de date compatible macOS / Linux
format_exif_date() {
    ts="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -u -r "$ts" +"%Y:%m:%d %H:%M:%S"
    else
        date -u -d @"$ts" +"%Y:%m:%d %H:%M:%S"
    fi
}

count_total=0
count_updated=0

# --- Récupère la liste des JSON dans un fichier temporaire (null-separated) ---
tmpfile="$(mktemp)"
# find ... -print0 écrit des chemins séparés par NUL
find "$ROOT_DIR" -type f -name "*.json" -print0 > "$tmpfile"

# Lecture sécurisée (supporte espaces/newlines dans les noms)
while IFS= read -r -d '' json; do
    count_total=$((count_total + 1))

    # fichier JSON vide ?
    if [ ! -s "$json" ]; then
        echo "⚠️  JSON vide : $(basename "$json")"
        continue
    fi

    # Récupère le titre (nom du fichier image) depuis la clé "title"
    title=$(jq -r '.title // empty' "$json")
    if [ -z "$title" ]; then
        echo "⚠️  Aucun champ 'title' dans : $(basename "$json")"
        continue
    fi

    # Récupère le timestamp (photoTakenTime ou creationTime)
    ts=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$json")
    if [ -z "$ts" ]; then
        echo "⚠️  Aucun timestamp dans : $(basename "$json") -> $title"
        continue
    fi

    formatted=$(format_exif_date "$ts")

    # Cherche l'image dans le même dossier que le JSON
    dir=$(dirname "$json")
    img="$dir/$title"

    if [ -f "$img" ]; then
        echo "🛠️  $(basename "$img") → $formatted"
        exiftool -overwrite_original \
            "-DateTimeOriginal=$formatted" \
            "-CreateDate=$formatted" \
            "-ModifyDate=$formatted" \
            "-UserComment=Updated from Google JSON" \
            "$img" >/dev/null 2>&1 || echo "⚠️ exiftool a échoué pour $(basename "$img")"
        count_updated=$((count_updated + 1))
    else
        echo "⚠️  Image introuvable pour : $title (depuis $(basename "$json"))"
    fi

done < "$tmpfile"

# nettoyage
rm -f "$tmpfile"

echo "---------------------------------------------------"
echo "✅ Terminé : $count_updated / $count_total fichiers JSON traités."
