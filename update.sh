#!/usr/bin/env bash
# ==========================================================
# update.sh
# Version: 1.0
# Usage:
#   ./update.sh -s /chemin/source [-e /chemin/export] [-t images|videos|both] [--touch]
#
# -s | --source   : dossier source (Google Takeout) (obligatoire)
# -e | --export   : dossier export (optionnel). Si présent, les fichiers sont copiés dans ce dossier
#                   (même arborescence relative) puis modifiés. Sinon modification in-place.
# -t | --targets  : images / videos / both (défaut: both)
# --touch         : met à jour le mtime du fichier pour correspondre à la date extraite
#
# Le script lit la clé "title" dans chaque JSON et utilise jq + exiftool.
# Compatible macOS / Linux. Relance automatiquement avec bash si nécessaire.
# ==========================================================

# relance avec bash si on est sous /bin/sh
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail
IFS=$'\n\t'

# ---------- Paramètres par défaut ----------
SOURCE_DIR=""
EXPORT_DIR=""
TARGETS="both"
DO_TOUCH=false

# ---------- Parse args (long + short) -----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            SOURCE_DIR="$2"; shift 2;;
        -e|--export)
            EXPORT_DIR="$2"; shift 2;;
        -t|--targets)
            TARGETS="$2"; shift 2;;
        --touch)
            DO_TOUCH=true; shift 1;;
        -h|--help)
            cat <<'EOF'
Usage: ./update.sh -s /source [-e /export] [-t images|videos|both] [--touch]

-s | --source   : dossier source (Google Takeout) (obligatoire)
-e | --export   : dossier export (optionnel)
-t | --targets  : images / videos / both   (défaut: both)
--touch         : met à jour le mtime du fichier (touch) pour correspondre à la date dans le JSON
-h | --help     : affiche cette aide
EOF
            exit 0;;
        *)
            echo "Argument inconnu: $1"; exit 1;;
    esac
done

# ---------- Vérifs ----------
if [ -z "$SOURCE_DIR" ]; then
    echo "❌ Le paramètre --source est requis."
    exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Le dossier source n'existe pas: $SOURCE_DIR"
    exit 1
fi
if [ -n "$EXPORT_DIR" ] && [ ! -d "$EXPORT_DIR" ]; then
    echo "🔧 Le dossier export n'existe pas, création: $EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
fi

# dépendances
for cmd in jq exiftool; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Erreur : '$cmd' requis. Installe via brew/apt."
        exit 1
    fi
done

# Normalisation targets
TARGETS="$(echo "$TARGETS" | tr '[:upper:]' '[:lower:]')"
if [[ "$TARGETS" != "images" && "$TARGETS" != "videos" && "$TARGETS" != "both" ]]; then
    echo "❌ --targets doit être 'images', 'videos' ou 'both'."
    exit 1
fi

echo "🔍 Source : $SOURCE_DIR"
if [ -n "$EXPORT_DIR" ]; then
    echo "📁 Export : $EXPORT_DIR"
else
    echo "⚠️  Pas d'export : modification in-place"
fi
echo "🎯 Cibles : $TARGETS"
[ "$DO_TOUCH" = true ] && echo "🕒 mtime sera mis à jour (touch)."

# ---------- Extensions ----------
image_exts=("jpg" "jpeg" "png" "heic" "gif" "tiff" "bmp")
video_exts=("mp4" "mov" "m4v" "3gp" "avi" "mts" "mpg" "mpeg" "wmv" "mkv" "webm")

lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

is_in_list() {
    local needle="$1"; shift
    local v
    for v in "$@"; do
        if [ "$needle" = "$v" ]; then return 0; fi
    done
    return 1
}

# ---------- Date formatting (macOS vs GNU) ----------
format_exif_date() {
    ts="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date -r expects seconds since epoch
        date -u -r "$ts" +"%Y:%m:%d %H:%M:%S"
    else
        date -u -d @"$ts" +"%Y:%m:%d %H:%M:%S"
    fi
}

# ---------- Collecte des JSONs (sécurisé) ----------
tmpfile="$(mktemp)"
find "$SOURCE_DIR" -type f -name "*.json" -print0 > "$tmpfile"

count_total=0
count_updated=0
count_skipped=0
count_notfound=0

# ---------- Boucle principale ----------
while IFS= read -r -d '' json; do
    count_total=$((count_total + 1))

    # ignore empty json
    if [ ! -s "$json" ]; then
        echo "⚠️ JSON vide: $(basename "$json")"
        count_skipped=$((count_skipped+1))
        continue
    fi

    # read title
    title=$(jq -r '.title // empty' "$json") || { echo "⚠️ jq error on $json"; continue; }
    if [ -z "$title" ]; then
        echo "⚠️ Aucun 'title' dans: $(basename "$json")"
        count_skipped=$((count_skipped+1))
        continue
    fi

    # read timestamp (photoTakenTime preferred)
    ts=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$json")
    if [ -z "$ts" ]; then
        echo "⚠️ Aucun timestamp pour: $title (json: $(basename "$json"))"
        count_skipped=$((count_skipped+1))
        continue
    fi

    formatted=$(format_exif_date "$ts")

    src_dir="$(dirname "$json")"
    src_img="$src_dir/$title"

    if [ ! -f "$src_img" ]; then
        echo "⚠️ Fichier source introuvable pour: $title (depuis $(basename "$json"))"
        count_notfound=$((count_notfound+1))
        continue
    fi

    # determine target path (export or in-place)
    if [ -n "$EXPORT_DIR" ]; then
        # chemin relatif depuis SOURCE_DIR
        rel_dir="${src_dir#$SOURCE_DIR/}"
        # si src_dir == SOURCE_DIR, rel_dir sera src_dir sans slash initial -> handle:
        if [ "$rel_dir" = "$src_dir" ]; then
            rel_dir="."
        fi
        target_dir="$EXPORT_DIR/$rel_dir"
        mkdir -p "$target_dir"
        target_img="$target_dir/$title"
        # copie source -> target (écrase si existe)
        cp -p "$src_img" "$target_img"
    else
        target_img="$src_img"
    fi

    # detect extension type
    ext="${title##*.}"
    ext_lc="$(lc "$ext")"

    is_image=false
    is_video=false
    if is_in_list "$ext_lc" "${image_exts[@]}"; then is_image=true; fi
    if is_in_list "$ext_lc" "${video_exts[@]}"; then is_video=true; fi

    # decide if process according to TARGETS
    if [ "$TARGETS" = "images" ] && [ "$is_image" = false ]; then
        # skip non-images
        count_skipped=$((count_skipped+1))
        continue
    fi
    if [ "$TARGETS" = "videos" ] && [ "$is_video" = false ]; then
        # skip non-videos
        count_skipped=$((count_skipped+1))
        continue
    fi

    # write metadata with exiftool (images vs videos)
    if [ "$is_video" = true ]; then
        echo "🛠️ (video) $(basename "$target_img") → $formatted"
        exiftool -overwrite_original \
            "-CreateDate=$formatted" \
            "-ModifyDate=$formatted" \
            "-TrackCreateDate=$formatted" \
            "-MediaCreateDate=$formatted" \
            "-QuickTime:CreateDate=$formatted" \
            "-XMP:CreateDate=$formatted" \
            "-UserComment=Updated from Google JSON" \
            "$target_img" >/dev/null 2>&1 || echo "⚠️ exiftool failed for $(basename "$target_img")"
    elif [ "$is_image" = true ]; then
        echo "🛠️ (image) $(basename "$target_img") → $formatted"
        exiftool -overwrite_original \
            "-DateTimeOriginal=$formatted" \
            "-CreateDate=$formatted" \
            "-ModifyDate=$formatted" \
            "-UserComment=Updated from Google JSON" \
            "$target_img" >/dev/null 2>&1 || echo "⚠️ exiftool failed for $(basename "$target_img")"
    else
        # extension inconnue -> traiter comme image par défaut si targets both
        echo "⚠️ Extension non reconnue pour $(basename "$target_img"), skipped"
        count_skipped=$((count_skipped+1))
        continue
    fi

# ----- mise à jour des timestamps fichiers (mtime/atime), et creation sur macOS si possible -----
if [ "$DO_TOUCH" = true ]; then
    # format touch: [[CC]YY]MMDDhhmm[.SS]
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch_ts=$(date -u -r "$ts" +"%Y%m%d%H%M.%S")
        # pour SetFile (creation date) on veut "MM/DD/YYYY HH:MM:SS"
        setfile_date=$(date -u -r "$ts" +"%m/%d/%Y %H:%M:%S")
    else
        touch_ts=$(date -u -d @"$ts" +"%Y%m%d%H%M.%S")
        # SetFile n'existe pas sur Linux normalement
        setfile_date=""
    fi

    # applique mtime/atime
    if touch -t "$touch_ts" "$target_img"; then
        : # ok
    else
        echo "⚠️ touch a échoué pour $(basename "$target_img")"
    fi

    # si on est sur macOS et SetFile est dispo, modifie la creation date (birth time)
    if command -v SetFile >/dev/null 2>&1 && [[ "$OSTYPE" == "darwin"* ]]; then
        if SetFile -d "$setfile_date" "$target_img" 2>/dev/null; then
            echo "🗂️ birthtime (creation) mis à $setfile_date pour $(basename "$target_img")"
        else
            echo "⚠️ SetFile a échoué pour $(basename "$target_img")"
        fi
    else
        # Note: sur Linux la creation/birth time n'est généralement pas modifiable.
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "ℹ️ SetFile non trouvé : installe Xcode Command Line Tools (qui fournit SetFile) si tu veux modifier la date de création."
        fi
    fi

    # NOTE: ctime (inode change time) est géré par le système et ne peut pas être modifié manuellement.
fi


    count_updated=$((count_updated+1))

done < "$tmpfile"

# cleanup
rm -f "$tmpfile"

echo "----------------------------------------"
echo "Total JSON trouvés : $count_total"
echo "Fichiers mis à jour : $count_updated"
echo "Fichiers non trouvés : $count_notfound"
echo "Fichiers ignorés/skippés : $count_skipped"
echo "----------------------------------------"
echo "✅ Terminé."
