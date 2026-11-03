# 4431 IPTV pour Mac

Application IPTV native pour Mac Apple Silicon, sous macOS 13 ou ultérieur. Connexion par compte Xtream ou par URL de playlist Xtream M3U. Les identifiants sont conservés dans le Trousseau du Mac.

**[Télécharger le DMG 0.0.3](https://github.com/heavensal/4431-IPTV-Macbook/releases/download/v0.0.3/4431-IPTV-Macbook-0.0.3.dmg)** · [Notes de version](https://github.com/heavensal/4431-IPTV-Macbook/releases/tag/v0.0.3)

Ouvrir le DMG et glisser 4431 IPTV dans Applications. Cette compilation utilise une signature locale ad hoc.

## Lecture

Choisir une catégorie TV, Films ou Séries, ou valider une recherche globale avec Entrée. La barre du lecteur permet de changer de piste audio, de sélectionner les sous-titres et de passer du plein écran au lecteur quart de fenêtre. La vidéo garde ses proportions. En mode réduit, le catalogue reste accessible pendant la lecture. Les langues et illustrations dépendent des données du fournisseur.

## Construire le DMG

Sur un Mac Apple Silicon équipé de Xcode et des outils Swift 5.9 ou ultérieurs, exécuter `./package-dmg.sh`. Le script télécharge VLCKit 3.7.3 depuis VideoLAN, vérifie son empreinte SHA-256 puis produit `dist/4431 IPTV.dmg`. Pour ouvrir Package.swift directement dans Xcode, exécuter d’abord `./fetch-vlckit.sh`.

Le moteur VLCKit est distribué avec l’application. Sa licence figure dans Vendor/COPYING.txt. Aucune playlist ni aucun compte fournisseur n’est inclus.

## Mises à jour intégrées à partir de 0.0.3

Installez la version 0.0.3 manuellement dans Applications. Ensuite, utilisez le menu 4431 IPTV → Rechercher les mises à jour… → Installer et relancer. L’app vérifie également les nouvelles versions en arrière-plan. Le compte IPTV reste dans le Trousseau.

### Publier une version

Sur le Mac qui possède la clé Sparkle, modifier VERSION (par exemple 0.0.4) et augmenter BUILD (par exemple 4). Modifier RELEASE_NOTES.md. Committer les modifications, puis lancer `./release.sh` depuis le projet. Le script construit et signe le DMG, actualise appcast.xml, pousse le commit puis crée la release GitHub. GitHub CLI doit être connecté au compte autorisé.

La clé privée Sparkle est dans le Trousseau sous le compte 4431-IPTV-Macbook. Elle doit être sauvegardée avant de changer de Mac, avec l’outil generate_keys de Sparkle. Garder cette sauvegarde privée. La clé publique est intégrée à l’app. La signature Sparkle des mises à jour et la notarisation Apple sont deux mécanismes distincts.

Pour compiler depuis un clone, lancer fetch-vlckit.sh et fetch-sparkle.sh avant d’ouvrir Package.swift.
