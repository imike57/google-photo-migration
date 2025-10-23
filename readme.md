# Scripts de migration pour Google Photos

Développé pour une utilisation sur Mac ; le fonctionnement sur d’autres systèmes n’est pas garanti.

## Étapes

1. Exportez vos photos Google depuis [Google Takeout](https://takeout.google.com/) et placez les fichiers ZIP dans le dossier `zip` à la racine de ce projet.
2. Exécutez `extract.sh ./zip ./fusion` pour extraire tous les fichiers ZIP et fusionner les dossiers.
3. Exécutez `update.sh --source ./fusion` pour mettre à jour les dates à partir des fichiers JSON fournis par Google. [ExifTool](https://exiftool.org/) doit être installé sur votre machine.
4. Utilisez [gpth](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper) pour exporter l’ensemble dans un dossier correctement trié : `./gpth`.
