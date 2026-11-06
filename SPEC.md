# ReaHarvest — Spécification

> Gestionnaire collaboratif de projets REAPER.
> Nom technique : `reaharvest` (dépôt, paquets Dart préfixés `reaharvest_`, identifiant d'application `reaharvest`).

> Document de référence pour l'implémentation (sessions Claude Code).
> Les identifiants de code, noms de fichiers techniques et commentaires sont en anglais.
> Les points marqués **[À VALIDER]** doivent être vérifiés avant d'implémenter la fonctionnalité concernée.

---

## 1. Contexte et objectifs

Groupe de 3 musiciens (un seul profil technique) travaillant sur des projets REAPER partagés via un dossier Google Drive monté (mode streaming).

Problèmes à résoudre :
1. Divergence des projets et réintégration manuelle des parties.
2. Duplication massive (médias copiés par personne et par version, jusqu'à ×5).
3. Manque de discipline (arborescence non respectée, duplications par peur de supprimer, perte de la « bonne » version).

Objectifs :
- Imposer une organisation sans effort pour les non-techniciens.
- Ne jamais dupliquer les médias.
- Travailler sur une copie locale (performance, hors ligne), le Drive servant de dépôt partagé.
- Partager statuts, tâches, notes et paroles entre membres.
- Gérer aussi des projets purement personnels (locaux, ou locaux avec sauvegarde cloud) dans la même application, via des bibliothèques de modes différents (§3.0).
- Application rapide, moderne, intuitive.

Plateformes : **Windows et macOS prioritaires**, Linux secondaire (doit compiler et fonctionner, sans effort d'optimisation dédié).
Publication publique envisagée à terme : aucune dépendance en dur à Google Drive, à un fournisseur cloud ni à un backend précis.

---

## 2. Glossaire

| Terme | Définition |
|---|---|
| Bibliothèque (library) | Ensemble de projets géré par l'application, avec un mode (local, local + cloud, collaboration), un layout et ses dossiers. Possède un `libraryId`. |
| Mode | Niveau de partage et de fonctionnalités d'une bibliothèque (§3.0). |
| Dépôt (repository) | Dossier racine cloud d'une bibliothèque en mode local + cloud ou collaboration (ex. Drive monté). Source de vérité des fichiers projets. |
| Espace de travail (workspace) | Dossier local d'une bibliothèque, où les titres sont créés, récupérés et modifiés. |
| Groupe | Ensemble de membres partageant une bibliothèque en mode collaboration. Possède un `groupId`. À ne pas confondre avec le niveau « Artiste » d'une arborescence. |
| Modèle d'arborescence (layout) | Suite ordonnée de niveaux qui fige la structure des dossiers d'un dépôt (ex. `artist/album/title`). Cf. §3. |
| Niveau / tag | Élément d'un layout. Chaque niveau correspond à un dossier et à un tag (clé + valeur) utilisé pour la recherche et la navigation. |
| Nœud | Dossier correspondant à un niveau du layout. Possède un `nodeId` stable. |
| Titre (nœud feuille) | Dernier niveau du layout, quel que soit son nom affiché (titre, scène…). Dossier contenant le pool média, les assets et les versions. Son `nodeId` sert de `titleId`. |
| Version | Un fichier `.RPP` dans le dossier d'un titre. Possède un `versionId` stable, un propriétaire, un libellé. |
| Pool média | Dossier `Media/` du titre, partagé par toutes ses versions, en ajout seul. |
| Récupérer (checkout) | Copie dépôt → espace de travail. |
| Publier (publish) | Copie espace de travail → dépôt. |
| Libérer (release) | Suppression de la copie locale d'un titre. |
| Asset | Fichier annexe d'un titre, hors projet REAPER (partition, tablature, image, PDF, texte…). |
| Store collaboratif | Stockage des données partagées (statuts, tâches, notes, paroles, métadonnées d'assets). Deux implémentations : journal et PocketBase. |

---

## 3. Bibliothèques, modes et organisation

### 3.0 Bibliothèques et modes

L'utilisateur configure **une ou plusieurs bibliothèques**. Chacune possède son propre mode, son layout et ses dossiers. Toutes sont présentées dans une **vue unifiée**, filtrable par bibliothèque et par mode (§5.2).

| Mode | Dossiers | Fonctionnalités | Cas d'usage |
|---|---|---|---|
| **`local`** | Espace de travail uniquement | Organisation (layout), navigation, versions (avec propriétaire = membre local), vue détail, création, ouverture REAPER. Aucune synchronisation, aucune collaboration | Projets personnels sur une seule machine |
| **`cloud`** (local + cloud) | Espace de travail + dépôt cloud | `local` + Récupérer / Publier / Libérer, détection de conflits (utile entre plusieurs machines d'un même utilisateur), sauvegarde. Utilisateur unique : pas de contrôle de propriété ni de forçage | Projets personnels sauvegardés et accessibles depuis plusieurs machines |
| **`collab`** (collaboration) | Espace de travail + dépôt cloud partagé | `cloud` + membres, propriété des versions et forçage, store collaboratif (statuts, tâches, notes, paroles, assets partagés, activité, notifications) | Projets de groupe |

Règles :
- Le travail se fait **toujours dans l'espace de travail local** ; le dépôt n'est jamais un lieu de travail.
- **Changement de mode** possible à tout moment, par assistant :
  - `local` → `cloud` : choix du dépôt, publication initiale ;
  - `cloud` → `collab` : création du groupe, invitation des membres, adoption des versions (attribution du propriétaire) ;
  - rétrogradations : `collab` → `cloud` (export du store collaboratif en snapshot conservé dans le dépôt), `cloud` → `local` (le dépôt est laissé intact, simplement détaché).
- Un même dossier ne peut appartenir qu'à une seule bibliothèque (contrôle à la configuration).

**Fournisseurs cloud.** Le MVP s'appuie sur un **dossier monté ou synchronisé par le client du fournisseur** : l'application ne voit qu'un chemin du système de fichiers. Sont donc couverts, sans code spécifique : Google Drive pour ordinateur, Dropbox, OneDrive, iCloud Drive, Nextcloud, Syncthing, partage réseau (NAS/SMB), montage rclone (Linux). Contraintes communes à prendre en charge :
- fichiers « à la demande » (non présents localement) : ne jamais les lire ni les hacher inutilement, s'appuyer sur taille et mtime ;
- copies de conflit propres au fournisseur (ex. `fichier (1).RPP`, `conflicted copy`) : détectées et signalées comme anomalies, jamais adoptées silencieusement **[À VALIDER : motifs de nommage par fournisseur]**.

Les fournisseurs accessibles par API (sans dossier monté) sont **hors MVP**. L'accès au dépôt passe par un port `RepositoryStorage` dont l'implémentation MVP est `MountedFolderStorage`, pour permettre d'autres adaptateurs ultérieurement.

### 3.1 Modèles d'arborescence (layouts)

La structure des dossiers est définie par un **layout** : une suite ordonnée de niveaux. Chaque niveau est un **placeholder ciblant un tag**. La valeur du tag est le nom du dossier ; elle alimente la recherche, les filtres et la navigation dans l'interface.

Modèles fournis :
| Modèle | Niveaux (clés de tag) | Libellés affichés |
|---|---|---|
| **Classique (recommandé)** | `artist / album / title` | Artiste / Album / Titre |
| Orienté projet (sans album) | `artist / title` | Artiste / Titre |
| Orienté film | `project / chapter / scene` | Projet / Chapitre / Scène ou titre |

Règles des layouts :
- Le dernier niveau est toujours le **nœud feuille** (titre) : c'est lui qui contient `Media/` et les versions.
- Un layout comporte de 1 à 4 niveaux. Les modèles personnalisés définissent pour chaque niveau une clé de tag (identifiant technique, en anglais) et un libellé affiché.
- Tous les niveaux sont obligatoires. Chaque niveau intermédiaire dispose d'une valeur réservée (`_Unassigned`, affichée « Non classé » dans l'interface) pour les éléments non rattachés.
- En mode `local` uniquement, un layout peut être remplacé par l'**arborescence libre** (§3.3).
- Le layout est défini **par bibliothèque**, dans `_library.json`. Il est **figé dès la création du premier titre** : en changer ensuite relève d'une migration (hors MVP).
- Chaque layout déclare un **mapping tags → métadonnées de rendu** (ex. classique : `artist` → artiste, `album` → album, `title` → titre). Le mapping est modifiable par l'utilisateur.

### 3.2 Structure physique

Exemple avec le modèle classique :
```
<libraryRoot>/                   # repository root (modes cloud/collab) or workspace root (mode local)
  _library.json                   # libraryId, mode, layout, collab settings (cf. §6.5)
  _collab/                        # collab mode with journal store only (cf. §6.3)
  <artist>/
    .node.json                    # { nodeId, level: "artist" }
    <album>/
      .node.json                  # { nodeId, level: "album" }
      <title>/                    # leaf node
        .node.json                # { nodeId, level: "title" }
        Media/                    # shared, append-only pool
        Renders/                  # default render folder; publication optional (cf. §5.3)
        Assets/                   # attached files: scores, tabs, images, docs (cf. §5.9)
        <any name>.RPP            # versions (flat list)
        _versions/                # snapshots of overwritten versions (history)
        _trash/                   # deleted versions and assets
```

Règles :
- Le **chemin** définit les valeurs des tags. Les fichiers `.node.json` ne portent que des **identifiants stables** et le niveau, pour que déplacer ou renommer un dossier ne casse pas les données collaboratives.
- Tout dossier ou `.RPP` dont la position ne correspond pas au layout apparaît dans la section « À ranger » (§5.2).
- Le nom d'un `.RPP` est libre : l'identité d'une version ne dépend pas de son nom (cf. §4.2).
- Les comparaisons d'extension sont **insensibles à la casse** (`.rpp` et `.RPP` coexistent dans les projets réels).
- Fichiers exclus de toute synchronisation et de l'indexation (relevé sur un dépôt réel) :
  - REAPER : `*.reapeaks`, `*.rpp-bak` (y compris horodatés : `<nom>-AAAA-MM-JJ_HHMM.rpp-bak`), sous-dossier `Backups/` du titre (backups horodatés), `*.rpp-undo`, `*.rpp-prox`, `*.reapindex`. Les backups REAPER restent un filet de sécurité **local** : l'historique partagé est assuré par `_versions/` (§5.4) et par l'historique du fournisseur cloud ;
  - système : `.DS_Store`, `._*` (AppleDouble macOS), `desktop.ini`, `Thumbs.db` ;
  - fournisseur cloud : raccourcis Google Drive (`*.gdoc`, `*.gsheet`…).

### 3.3 Arborescence libre (mode `local` uniquement)

Option pour les utilisateurs qui ne veulent pas réorganiser leurs dossiers : l'application **laisse l'arborescence intacte**. L'interface recommande néanmoins un layout figé, et l'assistant de migration (§5.8) permet d'y passer plus tard.

Principe : la bibliothèque surveille **un ou plusieurs dossiers racines** et se comporte comme une grande bibliothèque indexée. Tout dossier contenant au moins un `.rpp` est un titre ; ses `.rpp` sont ses versions.

Règles :
1. **Tags** : dérivés des noms des dossiers parents, relatifs à la racine ; utilisables en recherche, sans filtre par niveau.
2. **Identité des titres** : un `.node.json` est écrit dans chaque dossier titre (identité stable, facilite la migration ultérieure vers un layout). C'est la seule écriture de l'application dans l'arborescence en dehors des actions explicites.
3. **Métadonnées de version** (`EXTSTATE`) : écrites uniquement à l'adoption explicite d'une version ; `.rpp` en lecture seule sinon.
4. **Pool média** : aucune contrainte `Media/`, pas de normalisation des chemins, pas de section « À ranger ». Seuls les médias absents sont signalés.
5. **Création, suppression, historique** : nouveaux titres créés dans un dossier choisi par l'utilisateur ; `_trash/` et `_versions/` placés dans le dossier du `.rpp` concerné, créés à la première utilisation.
6. **Dossiers imbriqués** contenant chacun des `.rpp` (cas réel : `titre/membre/v2/…`) : chaque dossier est un titre distinct.
7. **Configuration** : les racines surveillées et la configuration de la bibliothèque sont stockées dans la configuration de l'application, pas dans les dossiers. Une racine située sous une racine déjà déclarée (dans n'importe quelle bibliothèque) est refusée, pour éviter les doublons.
8. **Changement de mode** : passage à `cloud` ou `collab` impossible sans migration préalable vers un layout.

L'espace de travail local reproduit la même arborescence pour les titres récupérés. En modes `cloud` et `collab`, `_library.json` du dépôt fait référence ; l'espace de travail en conserve une copie pour fonctionner hors ligne.

---

## 4. Modèle de données côté fichiers

Ces données ne dépendent **pas** du store collaboratif : l'application doit fonctionner (navigation, versions, synchronisation) même sans store disponible.

### 4.1 Nœuds et titre
- `nodeId` : ULID généré à la création ou à l'adoption de chaque nœud, stocké dans son `.node.json`.
- Le `nodeId` du nœud feuille sert de `titleId`.
- Les tags d'un titre (ex. `artist=X`, `album=Y`, `title=Z`) sont dérivés de son chemin et indexés.

### 4.2 Version
Métadonnées stockées **dans le `.RPP`**, via une section `EXTSTATE` dédiée nommée `ReaHarvest` (conservée par REAPER à chaque sauvegarde) :
- `versionId` (ULID)
- `owner` (memberId) — obligatoire dans **tous les modes**, dès le jalon A (en mode `local` et `cloud` : le membre local), afin d'éviter toute évolution ultérieure du modèle
- `label` (texte libre, ex. « refrain B »)

La date est la date de modification du fichier.

Format observé (REAPER 7.84, `test/fixtures/reference-metadata.rpp`) : chunk `<EXTSTATE` en fin de chunk racine `<REAPER_PROJECT`, après `<EXTENSIONS`, un sous-chunk par section, une ligne `CLÉ valeur` par clé, section et clé en majuscules :
```
  <EXTSTATE
    <REAHARVEST
      VERSIONID 01JC...
      OWNER 01JC...
      LABEL "refrain B"
    >
  >
```
Règles validées par test (`SetProjExtState` puis sauvegarde, REAPER 7.84) :
- REAPER met section et clés **en majuscules** et les **trie alphabétiquement** ;
- une valeur vide n'est pas écrite (clé absente = clé supprimée) ;
- valeur simple : brute (`VERSIONID 01JC…`) ; avec espaces : entre `"` (`LABEL "refrain B"`) ; Unicode écrit tel quel en UTF-8 ;
- valeur contenant `"` : entre `'` (`DQUOTE 'say "hi"'`), même règle de délimiteurs que les lignes projet (§5.6) ;
- valeur contenant les trois délimiteurs (`"`, `'`, `` ` ``) ou un retour à la ligne : sous-chunk base64 `<BIN CLÉ` / ligne(s) base64 / `>`.

Le reader gère toutes ces formes. Le writer émet : brut si aucun espace ni délimiteur, `"…"` si la valeur ne contient ni `"` ni retour à la ligne, `<BIN` sinon (forme acceptée par REAPER, plus simple que de reproduire la cascade de délimiteurs). Clés toujours écrites en majuscules, comme REAPER.

Validé par test (fichier écrit à la main, ouvert par REAPER, valeurs relues via `GetProjExtState`) : REAPER lit correctement les valeurs brutes, `"…"`, `<BIN` base64 et l'Unicode ; la lecture des clés est insensible à la casse (une clé écrite `owner` est lue via `OWNER`). Si `<EXTSTATE` est absent, le writer l'insère en fin de chunk racine ; si la section est absente, il l'ajoute au chunk `<EXTSTATE` existant.

Détection automatique lors du scan :
| Cas | Détection | Comportement |
|---|---|---|
| Renommage | Même `versionId`, nouveau nom | Suivi transparent |
| Duplication manuelle (*Save As*) | Deux fichiers avec le même `versionId` | Proposer d'en faire une nouvelle version (nouvel ID, propriétaire = utilisateur courant) |
| Fichier inconnu | `.RPP` sans `versionId` | Section « À adopter » : choix du propriétaire et du libellé, écriture des métadonnées |

Les versions forment une **liste plate** (pas d'arbre, pas de version parente).

### 4.3 Médias
- Tout média référencé par une version doit résider dans `Media/` du titre, en **chemin relatif**.
- Références observées : `<SOURCE WAVE` / `<SOURCE MIDI` … `FILE ".\audio-files\x.wav"` ou `FILE "audio-files\x.wav"`, séparateur `\` sous Windows. Les projets existants utilisent `RECORD_PATH "audio-files"` : la migration (§5.8) réécrit ces chemins vers `Media/` **[À VALIDER : lecture par REAPER macOS d'un chemin relatif avec `\`]**.
- Le pool est en **ajout seul** : un fichier publié n'est jamais modifié ni supprimé, sauf purge explicite (cf. §5.4).
- Collision de nom à la publication (même nom, contenu différent selon le hash) : renommage avec suffixe et réécriture des références dans le `.RPP`.
- Le MIDI intégré au `.RPP` (cas du batteur) ne génère pas de média.

---

## 5. Fonctionnalités

### 5.1 Configuration
- **Bibliothèques** (0..n), chacune avec : nom affiché, mode (§3.0), racine de l'espace de travail, racine du dépôt (modes `cloud` et `collab`), layout, dossier de templates optionnel propre à la bibliothèque.
- Ajout d'une bibliothèque : création d'une nouvelle (choix du mode et du layout) ou rattachement à un dépôt existant (lecture de son `_library.json`, cas d'un membre qui rejoint un groupe).
- Assistant de premier lancement : création de la première bibliothèque, détection de REAPER.
- Identité locale du membre (`memberId`, nom affiché), créée au premier lancement et utilisée dans tous les modes (propriétaire des versions).
- Chemin de l'exécutable REAPER et du dossier de ressources REAPER (valeurs par défaut par OS).
- Dossier des templates de projet (par défaut : `ProjectTemplates` du dossier de ressources REAPER).
- Vérification d'une préférence REAPER recommandée, avec avertissement non bloquant : peaks centralisés hors projet (évite des milliers de `.reapeaks` dans l'espace de travail). Clés validées : `altpeaks` bit `0x1` = « Store all peak caches (.reapeaks) in alternate path » (General > Paths), `altpeakspath` = chemin.
- Aucune vérification des options de backup REAPER : tous les backups (`.rpp-bak`, horodatés, `Backups/`) sont exclus de la synchronisation (§3.2), quelle que soit l'option choisie.

### 5.2 Navigation
Principe : **aucune navigation arborescente imposée**. L'accès aux titres passe d'abord par la recherche et les filtres, pour minimiser le nombre de clics.

- **Barre de recherche principale**, toujours visible et focalisée au démarrage :
  - recherche instantanée, tolérante aux fautes, servie par l'index local ;
  - porte sur les valeurs de tags, les noms de versions, les libellés, les propriétaires et, en mode `collab`, les notes et paroles.
- **Modes d'affichage**, au choix de l'utilisateur et mémorisés :
  - **cartes** (vue par défaut) : titre, tags, statut, état de synchronisation, propriétaires des versions, date de dernière modification ;
  - **liste** : tableau dense, triable par colonne ;
  - **arborescence** : regroupement selon les niveaux du layout (ex. Artiste → Album → Titre), proposé comme vue parmi d'autres.
- **Filtres combinables** (puces ou panneau latéral) :
  - tags, un filtre par niveau du layout (ex. `artist`, `album`). Les bibliothèques ayant des layouts différents exposent leurs propres filtres ; une clé de tag commune (ex. `artist`) est filtrée sur l'ensemble ;
  - bibliothèque et mode (`local`, `cloud`, `collab`) ;
  - source : **dépôt (cloud)**, **local**, ou les deux (modes `cloud` et `collab`) ;
  - état de synchronisation : non récupéré, à jour, modifié localement, mis à jour à distance, en conflit ;
  - statut collaboratif (mode `collab`) ;
  - propriétaire de version ;
  - plugins manquants.
- Filtres et recherche sont combinés et conservés entre les sessions ; des **vues enregistrées** (ex. « Mes titres en cours ») sont possibles.
- Accès aux versions d'un titre depuis n'importe quel mode d'affichage, sans changer de vue (panneau de détail).
- Section « À ranger » : `.RPP` ou dossiers hors convention, avec déplacement guidé.
- Section « À adopter » (cf. §4.2).

### 5.3 Vue détail d'une version
Parsing du `.RPP`, sans REAPER :
- pistes de premier niveau (profondeur 0), avec nom (`NAME`) et couleur (`PEAKCOL`, bit `0x1000000` = couleur personnalisée). Profondeur calculée via `ISBUS <type> <delta>` (validé sur le corpus) : `ISBUS 0 0` piste normale, `ISBUS 1 1` début de dossier, `ISBUS 2 -n` dernière piste d'un dossier, ferme `n` niveaux ;
- plugins utilisés par piste, dédupliqués. Formes observées : `<VST "VST3: Nom (Éditeur)" fichier.vst3 0 "" uid{guid} ""`, `<VST "VSTi: …" fichier.dll …`, `<VST "VST: …" fichier.dll …`, `<JS chemin/relatif ""`. CLAP et AU absents du corpus **[À VALIDER]** ;
- **plugins absents** sur la machine, par comparaison avec les caches plugins REAPER, découverts par motif (`reaper-vstplugins*.ini`, `reaper-clap-*.ini`, `reaper-auplugins*.ini`) plutôt que par nom exact :
  - VST (validé Windows, `reaper-vstplugins64.ini`) : section `[vstcache]`, lignes `fichier=horodatage,uid,Nom (Éditeur)` ; dans la clé, les espaces du nom de fichier sont remplacés par `_` (`"TDR Kotelnikov.vst3"` → `TDR_Kotelnikov.vst3`) ;
  - JS (validé, `reaper-jsfx.ini`) : lignes `NAME chemin/relatif "JS: Nom"` ;
  - CLAP, AU, noms macOS et Linux **[À VALIDER]** ;
- tempo, signature, durée, fréquence d'échantillonnage, version de REAPER ;
- propriétaire, libellé, date de modification ;
- médias référencés, avec présence locale et taille.

**Écoute d'un échantillon et rendus** *(hors MVP — phase 3)*
- Un aperçu fidèle **sans rendu est impossible** : le son final dépend des plugins, des automations et du routage, que seul REAPER sait calculer. Un simple mixage des fichiers médias bruts serait trompeur ; il n'est pas retenu.
- **Rendus existants** : l'application lit le dossier de rendu défini dans le projet (ligne `RENDER_FILE`, résolue en relatif par rapport au dossier du titre), liste les fichiers audio présents (date, durée, format) et les lit dans un lecteur intégré (lecture, position, boucle).
- **Rendu à la demande** (optionnel) : lancement d'un rendu en arrière-plan via la ligne de commande REAPER (`-renderproject`), avec les paramètres de rendu du projet. Contraintes : REAPER installé, plugins présents sur la machine, durée proportionnelle au morceau.
  Validé (Windows, REAPER 7.84, REAPER déjà ouvert) : `reaper.exe -renderproject <fichier>.rpp` lance une instance séparée qui rend puis se ferme (code de sortie 0), sans perturber l'instance ouverte ; `RENDER_FILE` relatif est résolu depuis le dossier du projet. L'instance de rendu réécrit `REAPER.ini` en se fermant, avec un contenu identique. Risque résiduel : une préférence modifiée dans l'instance principale pendant un rendu pourrait être écrasée par cette réécriture (piste : option `-cfgfile` avec une copie de `REAPER.ini`, à évaluer en phase 3).
  Formes de `RENDER_FILE` observées : `""` (dossier du projet), dossier relatif (`.\render`), chemin de fichier relatif (`".\render\Drums 3.mp3"`) ou absolu (`"C:\Users\…\x.mp3"`, souvent d'une autre machine). Combiné avec `RENDER_PATTERN` (ex. `$project-ending`) quand il désigne un dossier.
- Convention par défaut pour les nouveaux projets (dès le MVP) : dossier de rendu `Renders/` dans le dossier du titre (cf. §5.6).
- **Publication des rendus**, deux cibles indépendantes, activables au niveau du dépôt et surchargeables par titre :
  - **dépôt** : `Renders/` publié avec le titre, pour que les membres puissent écouter sans REAPER ni plugins. Option désactivable pour économiser l'espace Drive ;
  - **dossiers d'export** (0..n) : copie des rendus vers un dossier externe configuré (ex. dossier Drive synchronisé vers un serveur de streaming type Navidrome). Chaque cible définit un motif de chemin et de nom basé sur les tags du layout (ex. `{artist}/{album}/{title}.{ext}`), des formats acceptés et une politique de remplacement (écraser, versionner).
  - Les métadonnées embarquées dans les fichiers proviennent du mapping tags → métadonnées de rendu (§3.1) ; l'application ne réécrit pas les tags audio **[À VALIDER : suffisance des métadonnées écrites par REAPER pour l'indexation Navidrome]**.

### 5.4 Gestion des versions
- **Créer** : vierge, depuis un template ou par duplication d'une version existante. Nouvel ID ; le propriétaire est l'utilisateur courant.
- **Renommer** le fichier et/ou modifier le libellé.
- **Supprimer** : déplacement vers `_trash/`.
- **Purger** : suppression définitive depuis `_trash/`, avec confirmation. Ensuite, liste des médias du pool référencés par aucune version, puis purge sur confirmation. La purge des médias non référencés ne porte que sur `Media/` : `Assets/` n'est jamais concerné.
- **Historique** : consultation et restauration des instantanés `_versions/`.

### 5.5 Synchronisation
**Récupérer**
- Par défaut : dossier du titre complet (toutes les versions et les médias référencés).
- Option : exclure des versions. Les médias référencés uniquement par les versions exclues ne sont alors pas copiés.
- Mémorisation locale du hash (cf. §7.1) de chaque fichier récupéré, qui sert de base de comparaison.

**Publier**
1. Normalisation des médias : tout média hors `Media/` (chemin absolu, autre machine) y est copié, puis la référence est réécrite en relatif.
2. Copie des médias absents du pool distant (comparaison par nom + taille + hash).
3. Pour chaque `.RPP` modifié :
   - **conflit** si le hash distant diffère du hash de base : refus, affichage du conflit, choix utilisateur (garder le distant, publier comme nouvelle version, ou forcer) ;
   - **version d'un autre membre** : refus par défaut, avec proposition d'enregistrer comme nouvelle version à son nom ;
   - **forçage** : contourne uniquement le contrôle de propriété ou le conflit après confirmation explicite. La version distante écrasée est d'abord copiée dans `_versions/`, et un événement de notification est émis vers le propriétaire.
4. Mise à jour des hash de base et émission d'un événement d'activité (« X a publié Y »).

**Libérer**
- Refus si des modifications locales ne sont pas publiées, sauf confirmation explicite.

**Versions des autres membres en local** : lisibles, ouvrables, importables (phase ultérieure), mais non publiables sans forçage.

### 5.6 Création de projet
- Saisie d'une valeur pour chaque niveau du layout (avec autocomplétion sur les valeurs existantes ; création des dossiers si nécessaire), choix du template et du libellé de version.
- Copie du template, puis renseignement de :
  - titre et auteur du projet ;
  - métadonnées de rendu, selon le mapping tags → métadonnées du layout (§3.1) ;
  - motif de nom de rendu ;
  - chemin d'enregistrement relatif `Media` ;
  - dossier de rendu relatif `Renders` ;
  - métadonnées de version (§4.2).

  Lignes validées sur le corpus (chunk racine) :
  - `TITLE <valeur>`, `AUTHOR <valeur>` ;
  - `<NOTES 0 2` puis une ligne `|texte` par ligne de note, puis `>` ;
  - `RECORD_PATH "<principal>" "<secondaire>"` ;
  - `RENDER_FILE <chemin>`, `RENDER_PATTERN <motif>` (jokers REAPER : `$project`, `$title`, `$author`…) ;
  - `<RENDER_METADATA` puis une ligne `TAG <SCHÉMA:CHAMP> <valeur>` par champ (ex. `TAG ID3:TIT2 $title`, `TAG ID3:TPE1 $author`, `TAG VORBIS:ARTIST $author`), puis `>`.

  Les valeurs ne sont entre guillemets que si nécessaire. Quotation validée : brut sans espace (`TITLE coffeetime`), `"…"` avec espaces (`TITLE "Dancing on a line"`), `'…'` si la valeur contient `"` (`TITLE 'My "quoted" title'`), puis `` `…` `` si elle contient aussi `'`. Le writer reproduit ces règles ; le reader accepte les trois délimiteurs.
- Ouverture immédiate dans REAPER.

### 5.7 Ouverture dans REAPER
- Ouverture dans l'instance existante (`-nonewinst` sous Windows, validé : `reaper.exe -nonewinst <fichier>.rpp` ouvre le projet dans un nouvel onglet de l'instance déjà ouverte, sans en lancer une seconde ; si REAPER est fermé, il le démarre) **[À VALIDER : équivalent macOS]**.
- Toute modification d'un `.RPP` par l'application (adoption, réécriture de chemins, import de pistes) exige que le projet soit fermé dans REAPER : avertissement et confirmation dans le MVP.
  - `REAPER.ini` (`projecttabs`, `projecttab1..n`) n'est pas fiable : il n'est réécrit que ponctuellement et garde des entrées périmées (constaté : `projecttabs=1` avec `projecttab2..9` encore présents).
  - MVP : si un processus REAPER tourne, avertissement et confirmation. Plus tard : script compagnon REAPER publiant la liste des projets ouverts.
  - Validé : REAPER **ne verrouille pas** le `.rpp` ouvert (ouverture exclusive en écriture et renommage réussis pendant que le projet est ouvert). Aucune détection par verrou n'est possible, et REAPER écrasera la modification à la prochaine sauvegarde du projet : l'avertissement doit le dire clairement.

### 5.8 Adoption de l'existant (migration)
Inclus dans le MVP (jalon C). Assistant de reprise de l'arborescence actuelle (`proaudio/reaper/projects/<groupe>/<titre>[/<membre>]`) :
- choix du layout cible, correspondance des niveaux existants avec ses niveaux (valeur `_Unassigned` proposée pour un niveau absent, par exemple l'album), puis déplacement des titres dans la nouvelle structure ;
- lecture de chaque `.rpp` pour connaître sa configuration de chemins : `RECORD_PATH` (ex. `audio-files`), références `FILE` des sources (relatives, absolues, hors du dossier du titre), `RENDER_FILE` (cf. formes au §5.3). Pour chaque cas, le rapport indique si l'application sait le corriger :
  - correction possible : proposition de déplacer les fichiers dans le bon dossier (`Media/`, `Renders/`) et de mettre à jour le `.rpp` en conséquence (patch ciblé, cf. §7.3) ;
  - correction impossible (ex. média introuvable, chemin absolu d'une autre machine sans fichier correspondant) : signalé dans le rapport, `.rpp` laissé intact ;
- fusion des médias des sous-dossiers par membre dans le pool unique, avec gestion des collisions par hash ;
- adoption de chaque `.RPP` (propriétaire déduit du sous-dossier quand il existe, sinon demandé) ;
- dédoublonnage des médias identiques (même hash) ;
- mode simulation avec rapport avant exécution.

### 5.9 Collaboration (mode `collab`, via le store collaboratif, cf. §6)
- **Statut** par titre et par version : `idea`, `writing`, `recording`, `mixing`, `done` (liste configurable).
- **Tâches** par titre : texte, assigné, échéance optionnelle, état.
- **Notes** par titre ou par version.
- **Paroles** par titre, avec historique des modifications.
- **Assets partagés** par titre (partitions, tablatures, images, PDF, autres fichiers) :
  - les fichiers sont stockés dans `Assets/` du titre et synchronisés avec le titre (§5.5). Ils ne sont **pas versionnés** (pas d'historique `_versions/`) ; un asset supprimé est déplacé dans `_trash/` du titre ;
  - les métadonnées (description, auteur, version associée éventuelle) sont dans le store collaboratif (entité `asset`) ;
  - aperçu intégré pour les images et PDF, ouverture avec l'application système sinon ;
  - en mode `local` et `cloud`, `Assets/` est disponible sans métadonnées collaboratives.
- **Fil d'activité** : publications, forçages, changements de statut, nouvelles tâches.
- **Notifications** : dans l'application et notifications système OS.

---

## 6. Store collaboratif

### 6.1 Principes
- Un **modèle canonique unique**, indépendant de l'implémentation.
- Deux adaptateurs interchangeables derrière un même port : `JournalStore` (sans serveur, MVP) et `PocketBaseStore` (phase 2).
- **Bascule en un clic** entre les deux, sans perte de données.
- Le reste de l'application ne connaît que le port.

### 6.2 Modèle canonique
Toutes les entités partagent ces champs :
```
uid        ULID, generated client-side (canonical identity, never backend-generated)
groupId    ULID
libraryId  ULID
entity     "member" | "titleMeta" | "versionMeta" | "task" | "note" | "lyrics" | "asset" | "activity"
author     memberId
hlc        Hybrid Logical Clock timestamp of the last write
deleted    boolean (tombstone)
```
Champs spécifiques par entité : à définir dans le code (types partagés générés une seule fois).
Résolution des conflits : **last-writer-wins par champ**, ordonné par `hlc`, puis par `author` en cas d'égalité.
`activity` est en ajout seul (jamais modifié).

Port (pseudo-signature) :
```
CollabStore
  upsert(entity, uid, fields)
  delete(entity, uid)
  query(entity, filter)
  subscribe(filter) -> stream of changes
  exportSnapshot() -> CanonicalSnapshot
  importSnapshot(CanonicalSnapshot)      # idempotent upsert by uid, LWW applied
```

### 6.3 Adaptateur journal (`JournalStore`)
```
<repositoryRoot>/_collab/<memberId>/<yyyy-mm>.jsonl     # append-only, one writer per directory
<repositoryRoot>/_collab/_snapshots/<timestamp>.json    # optional baselines
```
- Chaque membre n'écrit **que** dans son propre dossier : aucun conflit de synchronisation Drive possible.
- Une ligne = une opération : `{ v, opId, groupId, author, hlc, entity, uid, op: "upsert"|"delete", fields }`.
- Lecture : fusion de tous les journaux, puis projection locale dans SQLite (rejeu incrémental par offset de fichier).
- Détection des changements distants : surveillance de fichiers, avec **repli sur une scrutation périodique des mtimes** (les événements de fichiers sur un lecteur virtuel Drive ne sont pas fiables) **[À VALIDER]**.
- Limite connue : latence de propagation dépendante du client Drive.

### 6.4 Adaptateur PocketBase (`PocketBaseStore`, phase 2)
- Une collection par entité. Le champ `uid` porte un index unique et sert d'identité canonique ; l'`id` interne PocketBase n'est jamais exposé hors de l'adaptateur.
- Écritures : upsert par `uid`, avec application du LWW par champ côté adaptateur.
- Abonnements : temps réel PocketBase.
- Règles d'accès filtrées par `groupId` (multi-tenant possible).
- Authentification : un compte par membre, rattaché à son `memberId`.

### 6.5 Configuration de bibliothèque et bascule du store
`_library.json` (à la racine de la bibliothèque ; en modes `cloud` et `collab`, dans le dépôt, donc partagé par tous les membres) :
```json
{
  "libraryId": "...",
  "schemaVersion": 1,
  "mode": "local" | "cloud" | "collab",
  "layout": {
    "levels": [
      { "key": "artist", "label": "Artiste" },
      { "key": "album",  "label": "Album" },
      { "key": "title",  "label": "Titre" }
    ],
    "renderMetadata": { "artist": "artist", "album": "album", "title": "title" },
    "frozen": true
  },
  "collab": {                      // present in collab mode only
    "groupId": "...",
    "store": "journal" | "pocketbase",
    "backendUrl": "https://..."
  }
}
```
Procédure de bascule (action unique dans les paramètres) :
1. `exportSnapshot()` depuis l'adaptateur courant.
2. `importSnapshot()` dans l'adaptateur cible, puis vérification par comptage par entité.
3. Écriture de `_library.json` avec le nouveau store.
4. Les applications des autres membres détectent le changement de `_library.json` et basculent automatiquement.
5. Bascule PocketBase → journal : le snapshot est écrit dans `_collab/_snapshots/` comme base de départ.

---

## 7. Architecture technique

### 7.1 Stack
- **Flutter (desktop) + Dart**, compilation AOT native. Cibles : Windows et macOS prioritaires, Linux secondaire ; Android et iOS envisagés ultérieurement (§7.4).
- Un seul langage pour l'ensemble : interface, logique métier, entrées/sorties.
- Interface : Material 3 avec thème personnalisé (design system propre à l'application).
- Gestion d'état : **Riverpod** **[À VALIDER au démarrage du projet]**.
- Paquets indicatifs :
  - `sqlite3` / `drift` : index local ;
  - `watcher` : surveillance de fichiers ;
  - `path` ;
  - `pocketbase` : SDK Dart officiel (phase 2) ;
  - `ulid` : identifiants ;
  - `window_manager`, `file_selector`, `local_notifier` : intégration desktop ;
  - `auto_updater` (Sparkle / WinSparkle) : mise à jour automatique.
- **Hash** : algorithme non imposé. Exigences : robuste (empreinte ≥ 128 bits, collisions négligeables hors contexte adverse ; aucun usage de sécurité), extrêmement performant (débit proche de celui du disque), calcul en flux sur les gros fichiers. Choix par benchmark au démarrage du projet (candidats : XXH3-128, BLAKE3, via `dart:ffi` si nécessaire) **[À VALIDER]**. Le hash n'est calculé que si taille ou mtime ont changé.
- **Concurrence** : toutes les tâches longues (scan, parsing de masse, hash, copies) s'exécutent dans des **isolates**, jamais sur l'isolate de l'interface. Le hash est calculé en tâche de fond, par lot (un titre et ses versions).

### 7.2 Découpage
Monorepo de paquets Dart (workspace) :
```
packages/
  domain/          # pure Dart: entities, rules, sync states, canonical collab model, ports (abstract classes)
  rpp/             # pure Dart: RPP parser/writer (read: tracks, FX, metadata; write: targeted line/chunk patches only)
  collab/          # CollabStore port + adapters
    journal/       # JournalStore adapter (dart:io)
    pocketbase/    # PocketBaseStore adapter (phase 2, no dart:io dependency)
  library/         # libraries, modes, configuration, mode transitions
  repository/      # repository and workspace scanning, layout conventions, adoption (dart:io)
                   # RepositoryStorage port + MountedFolderStorage adapter
  index/           # local SQLite index: files, hashes, checkout bases, collab projection
  sync/            # checkout / publish / release / conflict detection
  reaper/          # launching, resource path, plugin cache parsing, prefs checks
apps/
  desktop/         # Flutter desktop app: UI, state management, wiring of adapters
  mobile/          # (later) Flutter mobile app
```
Les paquets sont créés au jalon qui les utilise (jalon A : `domain`, `rpp`, `library`, `repository`, `index`, `reaper` ; jalon B : `sync` ; jalon C : `collab`). Nom de paquet : `reaharvest_<dossier>`.

Règles de découplage :
- `domain` et `rpp` sont du **Dart pur** (aucune dépendance Flutter ni `dart:io`), donc testables isolément et réutilisables sur mobile.
- Les autres paquets dépendent de `domain` via des **interfaces** (classes abstraites), jamais d'implémentations concrètes.
- Aucun type propre à PocketBase ou au journal ne sort de son adaptateur.
- La couche UI ne connaît ni le mode collaboratif ni le système de fichiers : elle consomme des services exposés par la couche d'état.
- Injection des implémentations au point d'entrée de l'application uniquement.

### 7.3 Écriture des fichiers RPP
- Le writer modifie le **texte d'origine par patchs ciblés**, et ne réémet jamais le fichier complet depuis un modèle, afin de garantir la fidélité.
- Écriture atomique : fichier temporaire, puis renommage.
- Tests de non-régression sur un corpus de `.RPP` réels (écrire puis relire sans perte, ouverture dans REAPER).

### 7.4 Applications mobiles (ultérieur)
Objectif : notifications, notes, tâches, paroles, statuts ; pas de gestion de projets REAPER.
- Réutilisation directe de `domain` et du port `CollabStore`.
- **Contrainte** : le mode journal suppose un dossier Drive monté, indisponible sur mobile. Les applications mobiles nécessiteront le **mode PocketBase** (ou un adaptateur journal via l'API Google Drive, à évaluer le moment venu).
- Notifications push mobiles : service tiers requis (FCM / APNs), hors périmètre actuel.

---

## 8. Exigences non fonctionnelles

- **Performance** :
  - démarrage jusqu'à la vue principale exploitable en moins d'une seconde, servie depuis l'index ;
  - aucune opération bloquante dans l'interface ;
  - tâches longues en arrière-plan avec progression et annulation ;
  - scan incrémental (mtime + taille, hash uniquement si nécessaire) ;
  - cible indicative : 1 000 `.RPP` et 100 Go de médias sans dégradation perceptible.
- **Fiabilité** : aucune perte de données possible sans confirmation explicite ; toutes les opérations destructrices passent par la corbeille ou l'historique.
- **Ergonomie** : utilisable par des non-techniciens ; vocabulaire musical plutôt que technique ; actions principales accessibles en un clic.
- **Distribution** : outillage entièrement gratuit et open source ; build et publication par la CI (GitHub Actions), artefacts publiés en GitHub Releases.
  - **Windows** : installeur (Inno Setup ou MSIX) signé gratuitement via **SignPath Foundation** (programme open source : dépôt public, licence OSI, signature depuis la CI), afin d'éviter l'avertissement SmartScreen (retenu ; candidature à déposer une fois le dépôt public et la licence choisie).
  - **macOS** : DMG **non notarisé** (pas d'adhésion payante Apple). L'avertissement Gatekeeper au premier lancement est accepté ; la procédure d'autorisation est documentée. Pas de machine de test disponible : macOS est construit par la CI, testé sur une base « best effort ».
  - **Mise à jour automatique** (`auto_updater`, WinSparkle / Sparkle, flux d'appcast signé) : vérification au démarrage puis périodique → notification « mise à jour disponible » → un clic → téléchargement, installation → redémarrage si nécessaire.
- **Licence** : GPL-3.0 (`LICENSE`).
- **Identifiant d'application** : `io.github.6wheels.reaharvest` (Windows, macOS) ; `io.github._6wheels.reaharvest` sous Linux (règle freedesktop : un segment ne peut commencer par un chiffre ; format compatible avec la vérification Flathub).
- **Internationalisation** : interface en français, préparée pour l'i18n (publication ultérieure).

---

## 9. Phases

| Phase | Contenu |
|---|---|
| **1 — MVP** | Bibliothèques et modes (`local`, `cloud`, `collab`), changement de mode, configuration, layouts (modèles fournis + personnalisé), conventions de dépôt, scan et index, navigation, vue détail, gestion des versions, Récupérer / Publier / Libérer (conflits, forçage), création depuis template, ouverture REAPER, assistant d'adoption. Mode `collab` complet : membres, propriété et forçage, port `CollabStore` + `JournalStore`, statuts, tâches, notes, paroles, assets partagés, activité, notifications |
| **2 — Backend** | `PocketBaseStore`, bascule en un clic, authentification ; prérequis des applications mobiles |
| **3 — Outils** | Rendus : lecteur intégré, rendu à la demande, publication des rendus (dépôt et dossiers d'export) ; import de pistes entre versions ; scripts Lua compagnons (par exemple rendu audio des pistes dont les plugins manquent) |

Jalons internes du MVP, livrés et testés dans cet ordre, chacun utilisable seul :
1. **Jalon A — mode `local`** : configuration et bibliothèques, layouts et arborescence libre, scan et index, navigation, vue détail, gestion des versions, création depuis template, ouverture REAPER.
2. **Jalon B — mode `cloud`** : port `RepositoryStorage` + `MountedFolderStorage`, Récupérer / Publier / Libérer, détection de conflits, changement de mode `local` ↔ `cloud`.
3. **Jalon C — mode `collab`** : membres, propriété et forçage, `CollabStore` + `JournalStore`, statuts, tâches, notes, paroles, assets partagés, activité, notifications, assistant d'adoption de l'existant.

Prévoir dès le jalon A : `memberId` local et `owner` des versions, `libraryId`, `_library.json` (y compris le bloc `collab`), `groupId`, `uid` ULID, HLC, URL de backend configurable, ports `RepositoryStorage` et `CollabStore`.

---

## 10. Points ouverts et risques

1. ~~Format des lignes de métadonnées projet et rendu, `EXTSTATE`~~ (validé, §4.2, §5.6).
2. Détection d'un projet ouvert : ni `REAPER.ini` ni verrou de fichier ; MVP par détection du processus, script compagnon ensuite (§5.7).
3. Fiabilité de la surveillance de fichiers sur le lecteur Drive en streaming (§6.3).
4. ~~Clés `reaper.ini` des préférences~~ (validé : peaks uniquement, backups sans vérification, §5.1).
5. Caches plugins : VST et JS validés sous Windows ; CLAP, AU, macOS et Linux restants (§5.3).
6. Ouverture dans l'instance existante sous macOS (§5.7).
7. Motifs de nommage des copies de conflit par fournisseur cloud (§3.0).
8. ~~Licence et SignPath~~ (GPL-3.0, SignPath retenu, §8).
9. ~~Forme de `RENDER_FILE`, rendu en ligne de commande avec REAPER ouvert~~ (validé, §5.3).
10. Choix de l'algorithme de hash par benchmark (§7.1).
11. Chemins relatifs avec `\` lus par REAPER macOS (§4.3).

## 11. Hors périmètre

- Synchronisation bidirectionnelle automatique en continu (les synchronisations restent explicites).
- Arbre de versions et fusion automatique de projets.
- Changement de layout d'un dépôt existant (migration de structure).
- Travail direct dans le dossier Drive.
- Mode peer-to-peer.
- Fournisseurs cloud accessibles uniquement par API (sans dossier monté).
- Notarisation macOS.
