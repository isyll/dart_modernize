# dart_modernize 0.12.0 : plan de version

Document de travail rédigé le 2026-10-07 à partir de `main` (version 0.11.1,
commit `773c26c`). **Rien n'est implémenté.** Le document rassemble ce qu'il
faut savoir avant d'écrire la moindre ligne : les nouveautés de Dart 3.13, les
bugs trouvés en faisant tourner l'outil sur de vrais projets et leur origine dans
le code, les dépendances à merger, et le contenu proposé pour la prochaine
version.

Toutes les syntaxes Dart citées ont été vérifiées avec le SDK Dart 3.13.5
(Flutter 3.47.6). Tous les bugs cités ont été reproduits, soit sur un projet
réel, soit sur un projet minimal donné dans la fiche du bug.

## Sommaire

1. [Résumé](#1-résumé)
2. [Point de départ](#2-point-de-départ)
3. [Nouveautés de Dart 3.13, avec exemples](#3-nouveautés-de-dart-313-avec-exemples)
4. [Campagne de tests sur des projets réels](#4-campagne-de-tests-sur-des-projets-réels)
5. [Bugs détectés et leur origine](#5-bugs-détectés-et-leur-origine)
6. [Nouvelles passes proposées](#6-nouvelles-passes-proposées)
7. [Améliorations de l'outil hors passes](#7-améliorations-de-loutil-hors-passes)
8. [Dépendances et merges](#8-dépendances-et-merges)
9. [Prochaine version : 0.12.0](#9-prochaine-version--0120)
10. [Annexes](#10-annexes)

## 1. Résumé

- **Version proposée : 0.12.0**, pas 1.0.0 (raisons et critères pour 1.0.0 en
  9.1). Nouvelles passes et corrections, sans changement du plancher SDK (3.13
  reste le minimum).
- **Le bug le plus visible :** `primary-constructors` supprime les valeurs par
  défaut des paramètres (`this.port = 8080` devient `final int port`). Il est à
  l'origine de la majorité des fichiers annulés par `--verify`, sur 9 des 11
  projets que l'outil a pu traiter jusqu'au bout, et il peut aussi changer le
  comportement sans erreur de compilation (un
  `Duration? timeout = const Duration(seconds: 5)` devient `null`).
- **Le bug le plus dangereux :** `--verify` ne regarde que les fichiers modifiés.
  Une erreur qui apparaît dans un fichier non modifié (un appelant) n'est ni
  détectée ni annulée. Sur un projet minimal, l'outil termine même avec un succès
  (code 0) ; sur `devtools`, il laisse 3 erreurs de compilation sur le disque.
- **Ce que voit l'utilisateur** sur ses projets : « Error: Reverted N files that
  would no longer compile » et un code de sortie 1, alors que des dizaines
  d'autres fichiers ont bien été modernisés et restent modifiés sur le disque.
  Rien ne le lui dit. C'est l'explication probable des « erreurs » constatées.
- **25 bugs** au total (section 5) : 16 dans des passes précises (dont un déclenché
  par un bug du lint `prefer_const_constructors_in_immutables` du SDK), 1 commun à
  presque toutes les passes (B14), 8 dans le pipeline et l'exécution, dont des
  crashes de la VM sur les gros projets (B19) et un reformatage complet du projet
  (B21). Pour chacun, l'origine est localisée dans le code de l'outil (fichier et
  lignes), sauf B17 et B19, qui viennent du SDK Dart et dont l'outil doit se
  protéger.
- **7 nouvelles passes** proposées (section 6), dont celles demandées pour Dart
  3.13 : constructeurs `new` / `factory` sans nom de classe, corps vides `;`, et
  une version 2 de `primary-constructors`.
- **Dependabot :** une PR ouverte (#45, `analyzer` 14.3.0 vers 14.4.0, CI verte).
  `analyzer` 14.5.0 est déjà publié : merger #45 puis faire `dart pub upgrade`.

## 2. Point de départ

| Élément | Valeur |
|:--|:--|
| Version publiée | 0.11.1 (tag `v0.11.1`) |
| Plancher SDK de l'outil | `>=3.13.0 <4.0.0` (le validateur refuse un projet qui autorise plus ancien) |
| `analyzer` | contrainte `^14.0.0`, verrouillé en 14.3.0 |
| Passes | 22 (20 actives par défaut, `sort-members` et `collection-elements` en opt-in) |
| Milestones GitHub | 0.8.0, 0.9.0, 0.10.0, toutes fermées. Aucune pour 0.11.x ni 0.12.0 |
| Issues ouvertes | aucune |
| PR ouvertes | #45 (Dependabot) |

Ce que l'outil couvre déjà des versions récentes de Dart : patterns (3.0),
éléments null-aware (3.8), dot shorthands (3.10), paramètres nommés privés
(3.12), constructeurs primaires simples (3.13).

## 3. Nouveautés de Dart 3.13, avec exemples

Dart 3.13 est sorti le 2026-08-12. Sa nouveauté principale est le passage en
stable des **constructeurs primaires**, accompagnés de plusieurs raccourcis de
syntaxe. Sources en annexe 10.3.

### 3.1 Constructeurs `new` et `factory` sans le nom de la classe

C'est la nouveauté évoquée dans la demande. Dans le corps d'une classe, un
constructeur peut s'écrire avec le mot-clé `new` à la place du nom de la classe,
et un constructeur `factory` peut omettre le nom de la classe.

Avant (et toujours valide) :

```dart
class Point {
  final int x;
  final int y;

  const Point(this.x, this.y);
  const Point.origin() : x = 0, y = 0;
  Point._internal(this.x) : y = 0;

  factory Point.fromJson(Map<String, Object?> json) =>
      Point(json['x'] as int, json['y'] as int);
}

abstract class Shape {
  const factory Shape.circle(double r) = Circle;
}
```

Avec Dart 3.13 :

```dart
class Point {
  final int x;
  final int y;

  const new(this.x, this.y);
  const new origin() : x = 0, y = 0;
  new _internal(this.x) : y = 0;

  factory fromJson(Map<String, Object?> json) =>
      Point(json['x'] as int, json['y'] as int);
}

abstract class Shape {
  const factory circle(double r) = Circle;
}
```

Les règles :

| Ancienne forme | Nouvelle forme |
|:--|:--|
| `C(...)` | `new(...)` |
| `C.nom(...)` | `new nom(...)` |
| `C.new(...)` | `new(...)` |
| `const C(...)` | `const new(...)` |
| `external C(...)` | `external new(...)` |
| `C.a() : this(...)` (redirection) | `new a() : this(...)` |
| `factory C(...)` | `factory(...)` |
| `factory C.nom(...)` | `factory nom(...)` |
| `const factory C.nom() = D;` | `const factory nom() = D;` |

Les appels ne changent pas : on écrit toujours `Point.origin()` et
`Point.fromJson(...)`. Seule la déclaration est raccourcie. Le lint 3.13
`unnecessary_type_name_in_constructor` signale l'ancienne forme et propose le
correctif.

Fonctionne dans les classes, les `mixin class`, les enums et les extension types.

### 3.2 Constructeurs primaires (déjà en partie gérés par l'outil)

Le constructeur est déclaré dans l'en-tête de la classe. Un paramètre marqué
`final` ou `var` est **déclarant** : il crée aussi le champ.

```dart
// Avant
class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}

// Dart 3.13
class const Point(final int x, final int y);
```

Variantes vérifiées avec le SDK 3.13.5 :

```dart
// Valeurs par défaut, paramètres optionnels positionnels et nommés.
class Pair(final int a, [final int b = 2]);
class Settings({final Duration? timeout = const Duration(seconds: 5)});

// Constructeur primaire nommé ou privé.
class Vec._(final int x, final int y) {
  factory zero() => Vec._(0, 0);
}

// Paramètres super.
class A(final int a);
class B(super.a, final int b) extends A;

// Corps et liste d'initialisation du constructeur primaire : la déclaration `this`.
class Range(final int min, final int max) {
  this : assert(min <= max);
}

// Un paramètre non déclarant (sans final ni var) est visible dans les
// initialiseurs de champs.
class Scaled(int raw) {
  final int _value = raw * 2;
}

// Enums.
enum Planet(final double mass) {
  mercury(3.3),
  venus(4.8)
}
```

La passe `primary-constructors` actuelle ne produit que la forme la plus simple :
une classe non abstraite, avec un seul constructeur génératif sans nom, sans
corps ni liste d'initialisation, dont tous les paramètres sont des `this.champ`.
Elle ignore les paramètres `super.`, les `assert`, les constructeurs nommés ou
privés, les enums et les champs déclarés à plusieurs (`final int x, y;`). Et elle
a deux bugs graves (B1 et B2, section 5).

### 3.3 Corps vides remplacés par `;`

Une classe, une `mixin class`, un mixin, un extension type ou une extension dont
le corps est vide peut finir par `;` au lieu de `{}`. Très fréquent dans les
hiérarchies scellées (états bloc, événements) et les exceptions.

```dart
// Avant
sealed class AuthState {}
final class AuthInitial extends AuthState {}
final class AuthLoading extends AuthState {}
class NetworkException implements Exception {}
mixin Loggable {}

// Dart 3.13
sealed class AuthState;
final class AuthInitial extends AuthState;
final class AuthLoading extends AuthState;
class NetworkException implements Exception;
mixin Loggable;
```

Lint correspondant : `empty_container_bodies`. Ne s'applique pas aux classes
d'application de mixin (`class B = A with M;`), qui n'ont déjà pas de corps.

### 3.4 Enums : `const` implicite

Les constructeurs génératifs d'un enum sont implicitement `const`. Le mot-clé
devient superflu.

```dart
// Avant
enum Level {
  low(1),
  high(2);

  const Level(this.value);
  final int value;
}

// Dart 3.13, forme courte dans le corps
enum Level {
  low(1),
  high(2);

  new(this.value);
  final int value;
}

// Dart 3.13, constructeur primaire
enum Level(final int value) {
  low(1),
  high(2)
}
```

Lint correspondant : `unnecessary_const_in_enum_constructor`.

### 3.5 Changement cassant : `final` et `var` interdits sur les paramètres ordinaires

Pour que `final int x` signifie sans ambiguïté « paramètre déclarant », un
paramètre ordinaire ne peut plus porter `final` ni `var` :

```dart
void f(final int x) {}     // error: extraneous_modifier
void g(var x) {}           // error: extraneous_modifier
class Bad {
  const Bad(final int x);  // error: extraneous_modifier
}
```

`dart fix --apply --code=extraneous_modifier` retire ces mots-clés (vérifié). Les
lints `avoid_final_parameters` et `prefer_final_parameters` sont dépréciés depuis
3.12.

Conséquence pour l'outil : un projet qui active `prefer_final_parameters` et
passe son SDK à 3.13 pour pouvoir lancer l'outil se retrouve avec des erreurs de
compilation. La passe `fix-all` les corrige, mais seulement en fin de pipeline,
après que les passes structurelles ont travaillé sur du code en erreur. Voir
l'amélioration I2.

### 3.6 Bibliothèques

| API | Ce qu'elle apporte | Intérêt pour une passe |
|:--|:--|:--|
| `Future.pause([Duration d = Duration.zero])` | Attendre une durée, renvoie `Future<void>` | `Future.delayed(d)` sans callback devient `Future.pause(d)` (P4) |
| `List.unmodifiableOf(Iterable<E>)` / `Map.unmodifiableOf` | Typage correct (l'ancien prend un `Iterable` non typé) | Le SDK porte déjà un `@Deprecated("Use List.unmodifiableOf instead")` commenté sur `List.unmodifiable` : dépréciation à venir (P7, plus tard) |
| `int.oneBitCount`, `int.trailingZeroBitCount` | Comptage de bits | Aucun |
| `Isolate.runSync` et l'API synchrone des isolates | Exécution synchrone | Aucun |

### 3.7 Nouveaux lints 3.13 et lien avec l'outil

| Lint | Effet | Couvert par |
|:--|:--|:--|
| `unnecessary_type_name_in_constructor` | `C()` devient `new()`, `factory C.x` devient `factory x` | P1 (nouvelle) |
| `unnecessary_const_in_enum_constructor` | retire `const` d'un constructeur d'enum | P1 (nouvelle) |
| `empty_container_bodies` | `{}` devient `;` | P2 (nouvelle) |
| `use_declaring_parameters` | utiliser un paramètre déclarant partout où c'est possible | P3 (`primary-constructors` v2) |
| `initialize_in_field_declaration` | déplacer `this : _x = x` vers `final int _x = x;` | P3 |
| `unnecessary_primary_constructor_body` | supprimer un `this;` vide | P3 ne doit jamais en produire |
| `use_primary_constructors` (expérimental) | proposer la promotion | `primary-constructors` |
| `async_return_with_no_await` | déjà utilisé dans `analysis_options.yaml` de l'outil | rien à faire |

Côté analyseur, `no_raw_types` et `no_dynamic_casts` remplacent les options
`strict-raw-types` et `strict-casts`. L'`analysis_options.yaml` de l'outil
utilise encore les options (`strict-casts`, `strict-raw-types`) : à migrer quand
les options seront dépréciées.

`fix-all` applique ces correctifs **seulement si le projet cible active les
lints** dans son `analysis_options.yaml`. Aucun n'est dans `recommended` ni dans
`flutter_lints`. D'où l'intérêt de passes dédiées : elles s'appliquent partout,
s'affichent dans `--dry-run`, se pilotent avec `--only` et `--no-<passe>`.

### 3.8 Formateur 3.13

Le formateur sépare maintenant les groupes d'imports par une ligne vide (`dart:`,
`package:`, relatifs), selon la version de langage du projet. `organize-imports`
groupe déjà de la même façon : pas de conflit attendu, à confirmer par le test de
convergence. Le formateur change aussi le `;` final d'un enum sans membres en `,`
(constaté sur `bedrock`) : c'est son comportement normal.

## 4. Campagne de tests sur des projets réels

### 4.1 Méthode

L'outil 0.11.1 (compilé depuis `main`) a tourné sur **des copies** : aucun projet
d'origine n'a été touché. Pour chaque projet :

1. copie du dossier (projets locaux) ou `git clone --depth 1` (GitHub) dans
   `C:\dmc\work` (chemin court, voir 10.2) ;
2. si la contrainte SDK autorise moins que 3.13, passage à `^3.13.0` (ce que
   l'outil exige) ;
3. `flutter pub get`, et `build_runner` si le code généré n'est pas commité ;
4. commit Git de référence ;
5. `dart analyze` avant ; tests avant (projets locaux) ;
6. `dart_modernize --verbose .` (run 1) ; `dart analyze` après ; tests après ;
7. commit, puis second run pour vérifier l'idempotence (projets de taille
   raisonnable) ;
8. pour chaque fichier annulé ou chaque erreur nouvelle, recherche de la passe
   en cause (dry-run, `--only`, lecture du diff) puis de la ligne de code de
   l'outil qui la produit ; reproduction sur un projet minimal quand c'était
   possible ;
9. projets qui ont planté : relancés seuls sur la machine, et avec une version
   AOT de l'outil (B19).

Le script est en annexe 10.1.

### 4.2 Résultats

Projets personnels (`~/my_projects`, `~/soft_valley_projects`) :

| Projet | Fichiers `lib/` | SDK d'origine | Run 1 | Durée | Fichiers modifiés | Fichiers annulés | Causes | Tests avant / après | Run 2 |
|:--|--:|:--|:--|--:|--:|--:|:--|:--|:--|
| `bedrock` | 113 | `^3.13.0` | succès | 523 s | 1 (formateur) | 0 | aucune | 221 ok, 5 KO / identique | rien à changer |
| `sonap_board_app` | 256 (dont 88 générés) | `^3.13.0` | code 1 | 623 s | 84 | 1 | B1 | 185 ok / 185 ok | 719 s, même fichier annulé |
| `1618-mobile-app` | 102 | `^3.7.0`, passé à `^3.13.0` | code 1 | 577 s | 88 | 14 | B1 (13), B3 (1) | ne se lancent pas (asset manquant) / idem | 389 s, mêmes 14 annulés |
| `anda` (`platform/app`) | 153 | `^3.13.0` | crash mémoire en parallèle (B8) ; seul : code 1 | 271 s seul | 24 | 19 | B1 (18), B6 (1) | 113 ok / 113 ok | non mesuré |

Projets GitHub (clone superficiel du 2026-10-06) :

| Projet | Fichiers `lib/` | SDK d'origine | Run 1 | Durée | Fichiers modifiés | Fichiers annulés | Causes | Nouveaux diagnostics |
|:--|--:|:--|:--|--:|--:|--:|:--|:--|
| `felangel/bloc`, `examples/flutter_todos` | 39 | `^3.12.0`, passé à `^3.13.0` | code 1 | 118 s | 32 | 17 | B1 | aucun ; run 2 : 109 s, rien de nouveau |
| `saber-notes/saber` | 165 | `^3.13.0` | code 1 | 1260 s | 153 | 3 | B1, B4, B5 | aucun |
| `openfoodfacts/smooth-app`, `packages/smooth_app` | 692 | `^3.12.2`, passé à `^3.13.0` | code 1 | 1251 s | 637 | 43 | B1, B14, B15, B16, B17 | 26 infos (B18) |
| `thunder-app/thunder` | 666 | `^3.13.2` | code 1 | 313 s | 630 | 31 | B1, B6, B16, B20 | 58 infos (B21) |
| `rydmike/flex_color_scheme` (paquet) | 74 (118 000 lignes avec `example/`) | `>=3.13.0` | crash de la VM (B19) ; 2e essai : code 1 ; 3e, seul : code 1 | 46 s ; 774 s ; 446 s seul | 322 | 11 | B1, B4, B15 | 11 infos `unnecessary_ignore` (B18) |
| `lichess-org/mobile` | 550 (+ code généré) | `^3.13.0` | crash de la VM (B19) après 4 s ; seul : code 1 | 861 s seul | 616 | 18 | B22 (16 fichiers), B5, B6 | 1 info `async_return_with_no_await` |
| `flutter/devtools`, `packages/devtools_app` (workspace pub) | 487 | `^3.11.0`, passé à `^3.13.0` | crash de la VM (B19) après 265 s ; seul : code 1 | 757 s seul | 642 | 41 | B1, B2, B6, B15, B16, B17, B20, B23, B24, B25 | **3 erreurs restées sur le disque** (B23, B7) et 2 infos (B18) |
| `immich-app/immich`, `mobile` | 614 | `>=3.12.0` | non testé : dépend d'un paquet `openapi` généré par l'outillage du projet, absent du dépôt | | | | | |

Les durées ont été mesurées avec deux ou trois projets traités en même temps
sur la machine (8 cœurs, 16 Go), sauf mention « seul » : elles surestiment le temps
réel, mais restent comparables entre elles.

### 4.3 Ce que la campagne montre

- **Aucun projet réel ne passe sans erreur**, à part `bedrock`, déjà modernisé.
  Chaque run se termine par « Reverted N files » et le code 1.
- **B1 est partout** : il touche 9 des 11 projets traités jusqu'au bout (tous sauf
  `bedrock` et `lichess`, dont les modèles passent par `freezed`), et représente
  la majorité des fichiers annulés. Le corriger change à lui seul l'expérience de
  l'outil.
- **Les gros projets révèlent des bugs que les petits ne montrent pas** : B22 à
  B25 n'apparaissent que sur `lichess` et `devtools`.
- **Le filet `--verify` fonctionne pour ce qu'il voit**, sauf sur `devtools` où 3
  erreurs de compilation restent après le run (B23, B7). Sur les autres projets,
  le code compile à la fin, et les tests des projets personnels donnent les mêmes
  résultats avant et après. Mais le filet ne voit ni les erreurs dans les fichiers
  non modifiés (B7), ni les changements de comportement qui compilent (B1
  nullable, B2, B4), ni les infos et avertissements (B18, B21).
- **Les gros projets font planter l'outil** (B19) quand la machine est chargée :
  3 des 7 projets GitHub testables ont planté au moins une fois.
- **La durée est un frein** : de 2 à 21 minutes, et un second run sur un projet
  déjà modernisé prend autant de temps que le premier (719 s sur `sonap_board_app`
  pour ne rien changer).
- **Le formatage** pèse plus lourd que la modernisation dans les diffs des projets
  qui ne sont pas formatés à 80 colonnes (B21).

## 5. Bugs détectés et leur origine

Gravité : **critique** = code cassé ou comportement changé sans que l'outil le
dise ; **haute** = fichier annulé par `--verify` (l'utilisateur voit une erreur) ;
**moyenne** = robustesse ou expérience utilisateur ; **basse** = cas marginal.

| ID | Gravité | Où | Résumé |
|:--|:--|:--|:--|
| B1 | critique | `primary-constructors` | valeurs par défaut et `[...]` optionnels supprimés |
| B2 | critique | `primary-constructors` | doc, annotations et commentaires du constructeur supprimés |
| B3 | haute | `prefer-inferred-types` | produit `<T>const [...]`, syntaxe invalide |
| B4 | haute | `prefer-inferred-types` | `double x = -1` devient `var x = -1`, donc un `int` |
| B5 | haute | `final-locals` | ne voit pas `(a, b) = ...` ni `for (x in ...)` |
| B6 | haute | `destructure-for-in`, `destructure-locals` | écrit un nom de type non importé |
| B7 | critique | pipeline, `--verify` | ne vérifie que les fichiers modifiés |
| B8 | moyenne | pipeline | un crash en cours de run laisse des fichiers à moitié modifiés |
| B9 | moyenne | pipeline, rapport | un succès partiel est affiché comme un échec |
| B10 | haute | pipeline | lenteur : 2 à 21 minutes par projet |
| B11 | basse (prérequis de B19) | `ProjectAnalyzer`, pipeline | un exécutable compilé ne trouve pas le SDK et se relance lui-même |
| B12 | moyenne | `--dry-run`, `--check` | ignorent `dart fix`, les imports et le formatage |
| B13 | haute (paquets) | `abstract-final-classes` | scelle des classes publiques d'un paquet publié |
| B14 | haute | toutes les passes sauf une | ignorent `// @dart = 2.x` en tête de fichier |
| B15 | haute | `super-parameters` | paramètre nommé replié sur un argument positionnel, appel `super.nom(...)` supprimé |
| B16 | haute | `dot-shorthands` | champ de record dans le `return` d'une fonction `async` |
| B17 | haute | `primary-constructors` et `fix-all` | `dart fix` ajoute un `const` invalide après la promotion (bug du SDK) |
| B18 | moyenne | `abstract-final-classes`, `sort-constructors-first` | font apparaître des lints du projet, ignorent un `// ignore:` volontaire |
| B19 | critique | exécution JIT | crash de la VM sur les gros projets (`flex_color_scheme`, `lichess`, `devtools`) |
| B20 | haute | `destructure-locals`, `destructure-for-in` | motif objet sur une valeur nullable, `?.` pris pour `.` |
| B21 | haute | finalisation, `dart format` | reformate tout le projet à 80 colonnes, sans option pour l'éviter |
| B22 | haute | `dot-shorthands` | éléments d'une collection passée à un constructeur générique (`ISetConst({...})`) |
| B23 | critique | `prefer-inferred-types` | retire le type d'un champ qui redéfinit un membre hérité, le type change |
| B24 | haute | `null-aware-conditionals` | insère `?` loin du `.` dans une chaîne sur plusieurs lignes, syntaxe cassée |
| B25 | haute | `inline-return` | l'expression change de contexte d'inférence en passant dans le `return` |

### B1. `primary-constructors` supprime les valeurs par défaut et les crochets optionnels

**Gravité : critique.** C'est la cause de la majorité des fichiers annulés, sur 9
des 11 projets que l'outil a pu traiter jusqu'au bout.

Constaté sur : `1618-mobile-app` (13 des 14 fichiers annulés : 22
`MISSING_DEFAULT_VALUE_FOR_PARAMETER`, 4 `CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH`),
`anda` (18 des 19 fichiers annulés : 64 et 8 erreurs), `flutter_todos` de bloc
(les 17 fichiers annulés), `sonap_board_app` (le seul fichier annulé),
`smooth-app` (48 et 7 erreurs), `thunder` (50 et 13), `flex_color_scheme` (24
et 53), `devtools` (37 et 48), `saber` (`lib/data/tools/eraser.dart`, un
constructeur déjà écrit `new({this.size = 10})`).

Reproduction :

```dart
class Config {
  final String host;
  final int port;
  final Duration? timeout;

  Config({required this.host, this.port = 8080, this.timeout = const Duration(seconds: 5)});
}

class Pair {
  final int a;
  final int b;

  Pair(this.a, [this.b = 2]);
}
```

Sortie actuelle :

```dart
class Config({required final String host, final int port, final Duration? timeout});

class Pair(final int a, final int b);
```

Trois effets :

1. `port` (non nullable, nommé, sans valeur par défaut) : erreur
   `MISSING_DEFAULT_VALUE_FOR_PARAMETER`. Le fichier est annulé.
2. `timeout` (nullable) : **compile**, mais `Config(host: 'x').timeout` vaut
   maintenant `null` au lieu de 5 secondes. Changement de comportement silencieux.
3. `b` devient positionnel obligatoire : la classe compile, mais chaque appel
   `Pair(1)` dans un **autre** fichier casse (`not_enough_positional_arguments`),
   et `--verify` ne le voit pas (B7).

Les appels `const CartState()` d'une classe `const` dont un champ avait
`= const []` donnent `CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH` dans les fichiers
appelants (`cart_provider.dart`, `home_cubit.dart`, tests de bloc).

**Origine :** `lib/src/pipeline/transformations/primary_constructors.dart`.

- Lignes 182 à 206 : le texte du paramètre d'en-tête est construit comme
  `'$requiredPrefix$modifier $typeText $fieldName'`. La valeur par défaut est
  ignorée. Depuis analyzer 14, elle est portée par `FormalParameter.defaultClause`
  (il n'y a plus d'enveloppe `DefaultFormalParameter`), donc un `this.port = 8080`
  passe le test `p is FieldFormalParameter` de la ligne 159 et perd son `= 8080`.
- Lignes 224 à 226 : `paramsText` ne connaît que « tout nommé, entre `{}` » ou
  « tout positionnel, liste nue ». Les optionnels positionnels perdent leurs `[]`.
- Lignes 173 à 177 : seul le mélange positionnel et nommé est refusé, pas le
  mélange obligatoire et optionnel positionnel.

**Correction proposée :** recopier ` = <texte de la valeur>` depuis
`param.defaultClause` ; émettre `(obligatoires, [optionnels])` ou
`(obligatoires, {nommés})` en respectant l'ordre d'origine ; garder `required`.

**Tests à ajouter :** golden pour nommé avec défaut, nommé nullable avec défaut
non nul, optionnel positionnel avec et sans défaut, mélange obligatoire et
optionnel, classe `const` avec `= const []`. Test sémantique avec un appelant dans
un autre fichier (`Pair(1)`, `const CartState()`).

### B2. `primary-constructors` supprime la doc, les annotations et les commentaires du constructeur

**Gravité : critique** (silencieux : le résultat compile, `--verify` ne peut rien
voir).

```dart
class Token {
  final String value;

  /// Creates a token. Never pass an empty [value].
  @Deprecated('Use Token.parse')
  const Token(
    // raw text, already trimmed
    this.value,
  );
}
```

Sortie actuelle : `class const Token(final String value);`. La doc, le
`@Deprecated` (les utilisateurs de la classe ne sont plus avertis) et le
commentaire du paramètre disparaissent.

Vu aussi sur un vrai projet, `devtools`, `lib/src/shared/memory/heap_graph_loader.dart` :

```dart
// Avant
class HeapGraphLoaderRuntime extends HeapGraphLoader {
  /// If [timeline] is provided the loader will add a snapshot event to it.
  const HeapGraphLoaderRuntime(this.timeline);

  final MemoryTimeline? timeline;
// Sortie : la doc a disparu
class const HeapGraphLoaderRuntime(final MemoryTimeline? timeline) extends HeapGraphLoader {
```

**Origine :** `primary_constructors.dart`, lignes 151 à 155. `_tryRewrite` vérifie
le nom, le corps, les initialiseurs et `external`, mais ni
`ctor.documentationComment`, ni `ctor.metadata`, ni les commentaires dans la liste
de paramètres, ni `param.metadata`. La protection équivalente existe pour les
champs (`_carriesAttachedText`, ligne 124), pas pour le constructeur.

**Correction proposée :** ne pas promouvoir quand le constructeur porte une doc,
une annotation, ou un commentaire entre ses jetons, ou quand un paramètre porte
une annotation. Déplacer la doc sur la classe est possible mais change son sens :
mieux vaut s'abstenir.

### B3. `prefer-inferred-types` produit `<T>const [...]`

**Gravité : haute.** Erreur de syntaxe ; l'analyseur en tire une cascade d'erreurs
trompeuses (`CONSTRUCTOR_WITH_RETURN_TYPE`, `INVALID_CONSTRUCTOR_NAME`,
`EXPECTED_CLASS_MEMBER`...). Constaté sur `1618-mobile-app`,
`lib/screens/search/widgets/filter_bottom_sheet.dart` :

```dart
// Avant
final List<BusinessCategory> _availableCats = const [BusinessCategory.massage];
// Sortie actuelle (invalide)
final _availableCats = <BusinessCategory>const [BusinessCategory.massage];
// Attendu
final _availableCats = const <BusinessCategory>[BusinessCategory.massage];
```

**Origine :** `prefer_inferred_types.dart`, lignes 345 à 347 (`_tryRelocate`). Les
arguments de type sont insérés à `literal.offset`. Pour un littéral `const`, le
nœud commence au mot-clé `const` (`TypedLiteral.constKeyword` fait partie du
nœud).

**Correction proposée :** insérer à `literal.leftBracket.offset` (`ListLiteral` et
`SetOrMapLiteral` exposent tous deux `leftBracket`). Tests : liste, set et map
`const`, en local et en champ, et cible de cascade.

### B4. `prefer-inferred-types` change `double x = -1` en `int`

**Gravité : haute.** Constaté sur `saber`, `test/canvas_backgrounds_test.dart` :
`double lastPosition = -1;` devient `var lastPosition = -1;`, puis
`lastPosition = position` (un `double`) ne compile plus (`INVALID_ASSIGNMENT`).
Si la variable n'est jamais réaffectée, le type change en silence (`-1` au lieu de
`-1.0` à l'affichage ou en JSON).

Même cause sur `flex_color_scheme`, avec des constantes :
`static const double panelButtonPhoneWidthReduce = -20;` devient
`static const panelButtonPhoneWidthReduce = -20;`, donc un `int`. Le fichier de la
constante compile, mais chez les appelants `width + panelButtonPhoneWidthReduce`
devient un `num` : 7 `INVALID_ASSIGNMENT: A value of type 'num' can't be assigned
to a variable of type 'double'` dans d'autres fichiers. L'erreur apparaît loin de
sa cause, ce qui illustre aussi B7.

**Origine :** `prefer_inferred_types.dart`. La garde de la ligne 239
(`_isUnsafeInitializer`) ne traite qu'un `IntegerLiteral` nu. `-1` est une
`PrefixExpression` autour du littéral, que `_hasObviousType` accepte (ligne 192).
Dans un contexte `double`, l'analyseur type le littéral `-1` en `double` (règle
int vers double des littéraux), donc la comparaison `_sameType` de la ligne 144
passe.

**Correction proposée :** déballer `PrefixExpression` et
`ParenthesizedExpression` dans la garde ; plus robuste : pour un littéral
numérique, comparer le type déclaré au type du littéral **sans** contexte (`int`
pour un `IntegerLiteral`). Tests : `double x = -1;`, `double x = (1);`,
`final double d = -0;`.

### B5. `final-locals` ne voit pas certaines réaffectations

**Gravité : haute.** Constaté sur `saber`, `lib/components/canvas/_stroke.dart` :

```dart
var firstPoint = PointVector.fromOffset(...);
var lastPoint = PointVector.fromOffset(...);
(firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);
```

Les deux `var` deviennent `final` : `ASSIGNMENT_TO_FINAL_LOCAL`. Même cas sur
`lichess` (`lib/src/model/puzzle/puzzle_controller.dart` :
`(currentPosition, san) = currentPosition.makeSan(moveObj);`). Reproduit aussi
avec une boucle sur une variable existante :

```dart
var last = 0;
for (last in xs) {}   // `var last` devient `final last` : erreur
```

**Origine :** `final_locals.dart`, lignes 129 à 155. `_ReassignmentFinder` ne
regarde que `AssignmentExpression` et `++` / `--`. Il manque l'affectation par
motif (`PatternAssignment`, dont les cibles sont des `AssignedVariablePattern`)
et la boucle `for (x in ...)` sur un identifiant existant
(`ForEachPartsWithIdentifier`).

**Correction proposée :** ajouter `visitAssignedVariablePattern` et
`visitForEachPartsWithIdentifier` (cible `node.identifier`). Tests : motif record,
liste et objet, et `for (x in ...)`.

### B6. `destructure-for-in` et `destructure-locals` écrivent un type non importé

**Gravité : haute.** Constaté sur `anda`, sur `thunder` (`PostDetail` dans
`draft_utils.dart` et `drafts_settings_page.dart`, `CommunityDetail` dans
`input_dialogs.dart`), sur `lichess` (`LearnStage` dans
`test/model/learn/learn_levels_test.dart`) et sur `devtools` (`Variable` dans
`display_provider.dart`, et le cas du préfixe ci-dessous). Sur `anda`, `lib/features/drive/drive_views.dart` :

```dart
// Avant : TripStop n'est pas importé dans ce fichier, seulement inféré.
for (final stop in driven.trip.stops) LegStop(stop.town, l10n.timeLabel(stop.at)),

// Sortie actuelle : UNDEFINED_CLASS 'TripStop'
for (final TripStop(:town, :at) in driven.trip.stops) LegStop(town, l10n.timeLabel(at)),
```

Le cas du préfixe est constaté sur `devtools`,
`lib/src/screens/debugger/debugger_controller.dart`, qui importe
`package:dap/dap.dart as dap` :

```dart
// Sortie
final StackFrame(id: frameId) = await _fetchDapFrame(frame);
for (final Scope(:variablesReference) in scopes) ...
```

Sans préfixe, `StackFrame` désigne la classe de `package:flutter/foundation.dart`,
qui n'a pas de getter `id` (`UNDEFINED_GETTER`), et `Scope` n'existe pas
(`UNDEFINED_CLASS`). Il fallait `dap.StackFrame` et `dap.Scope`. La valeur
déstructurée est en plus nullable (B20).

**Origine :** `destructure_for_in.dart`, lignes 73 et 98, et
`destructure_locals.dart`, ligne 118. Le nom vient de `type.element.name`, sans
vérifier qu'il désigne le même élément dans la portée du fichier : type non
importé, importé avec un préfixe (`as dap`, il faut écrire `dap.StackFrame`),
masqué par `hide`, homonyme d'une autre classe visible, ou privé à une autre
bibliothèque (`_Foo`).

**Correction proposée :** chercher le nom dans la portée de la bibliothèque (la
bibliothèque elle-même, puis les imports et leur préfixe) ; émettre
`préfixe.Nom` si besoin ; ne rien faire si le type n'est pas atteignable. Tests :
type non importé, import préfixé, `hide`, type privé d'une autre bibliothèque.

### B7. `--verify` ne vérifie que les fichiers modifiés

**Gravité : critique.** L'outil affiche un succès et laisse du code qui ne
compile pas.

Reproduction (projet minimal, deux fichiers) : `lib/pair.dart` contient la classe
`Pair` de B1, `lib/use.dart` (non modifié par l'outil) appelle `Pair(1)`.

```
$ dart_modernize --only primary-constructors .
  ✓ Modernized 1 of 2 file(s).          (code de sortie 0)
$ dart analyze
  error - lib\use.dart:3:22 - 2 positional arguments expected by 'Pair.new', but 1 found.
```

**Constaté aussi sur un vrai projet** : `devtools` (voir B23). Un champ change de
type dans `classes.dart`, fichier qui compile. Les erreurs apparaissent dans deux
autres fichiers, que `--verify` annule, mais la cause reste en place : **3 erreurs
de compilation sur le disque à la fin du run**, alors que l'outil a cru avoir
tout réparé.

**Origine :** `pipeline.dart`, lignes 623 à 651 (`_verify`). La boucle ne parcourt
que `{...result.changedFiles, ...finalize.changedPaths}`. Une nouvelle erreur
dans un fichier non modifié est ignorée. Deux défauts voisins :

- après une annulation, rien ne revérifie : un fichier modifié qui dépendait d'un
  changement annulé peut casser à son tour ;
- seules les erreurs sont comparées. C'est voulu, mais un changement qui compile
  tout en changeant le comportement (B1 `timeout`, B2) échappe forcément au
  filet. D'où l'importance de corriger les passes elles-mêmes.

**Correction proposée :** comparer les erreurs de tout le projet, après chaque
annulation aussi ; pour une nouvelle erreur dans un fichier non modifié, ou qui
reste après l'annulation de son fichier, annuler les fichiers modifiés dont il
dépend (ou procéder par dichotomie) ; recommencer jusqu'à ne plus avoir de
nouvelle erreur, avec un nombre maximal d'itérations. I4 (vérification à chaque
étape) règle le problème plus tôt et à moindre coût.

### B8. Un crash en cours de run laisse des fichiers à moitié modifiés

**Gravité : moyenne** (atténuée par l'exigence d'un arbre Git propre).

Constaté sur `anda`, avec trois runs en parallèle sur la machine : le processus
s'est arrêté sur `../../runtime/vm/zone.cc: 95: error: Out of memory.` (code
`0xC0000409`) pendant `organize-imports`. Les éditions structurelles étaient déjà
écrites : 42 fichiers modifiés, ni formatés ni vérifiés. Lancé seul, le même
projet passe (271 s, environ 1,3 Go). Une session interrompue a laissé de même 85
fichiers modifiés sur la copie de `sonap_board_app`.

**Origine :** `pipeline.dart`, lignes 103 à 119. Les fichiers sont écrits avant
`_finalize` et `_verify`, sans sauvegarde ni `try`/`finally`. Une
`ModernizeException` levée par `_runProcess` (échec de `dart fix` ou de
`dart format`) a le même effet.

**Correction proposée :** en cas d'exception, réécrire `originalContent` (déjà en
mémoire) ; contre un crash dur (mémoire, kill), écrire une sauvegarde dans
`.dart_tool/dart_modernize/backup/` avant la première écriture et ajouter
`--restore`. À défaut, un message qui indique `git checkout -- .`.

### B9. Un succès partiel est affiché comme un échec

**Gravité : moyenne.** C'est probablement « les erreurs » que l'utilisateur voit
sur ses projets.

| Projet | Message affiché | Réalité sur le disque |
|:--|:--|:--|
| `saber` | `Error: Reverted 3 files that would no longer compile.` code 1 | 153 fichiers modernisés |
| `sonap_board_app` | `Reverted 1 file` code 1 | 84 fichiers modifiés |
| `1618-mobile-app` | `Reverted 14 files` code 1 | 88 fichiers modifiés |
| `flutter_todos` | `Reverted 17 files` code 1 | 32 fichiers modifiés |
| `smooth-app` | `Reverted 43 files` code 1 | 637 fichiers modifiés |

Et comme les mêmes fichiers échouent à chaque fois, chaque nouveau run affiche la
même erreur (`sonap_board_app` : 719 s pour ne rien changer et finir en code 1).

**Origine :** `pipeline.dart`, lignes 128 à 135. Quand `reverted` n'est pas vide,
l'outil lève une `ModernizeException` **avant** `_reportCompletion` : aucun
résumé de ce qui a été appliqué. Le message conseille « Re-run with --no-verify
to keep the changes anyway », c'est-à-dire de garder du code qui ne compile pas.

**Correction proposée :** afficher le résumé normal, puis la liste des fichiers
annulés avec la ou les passes en cause (`passesByFile` les connaît), un code de
sortie distinct pour « partiel » (par exemple 2), et proposer `--no-<passe>` à la
place de `--no-verify`.

### B10. Lenteur

**Gravité : haute pour l'adoption.**

| Projet | Fichiers `lib/` | Durée du run 1 |
|:--|--:|--:|
| `flutter_todos` | 39 | 118 s |
| `anda` (seul sur la machine) | 153 | 271 s |
| `thunder` | 666 | 313 s |
| `bedrock` (1 ligne changée) | 113 | 523 s |
| `1618-mobile-app` | 102 | 577 s |
| `sonap_board_app` (run 2 : rien à changer) | 256 | 623 s (run 2 : 719 s) |
| `flex_color_scheme` | 74 (et `example/`) | 774 s (seul : 446 s) |
| `devtools` (seul) | 487 | 757 s |
| `lichess` (seul) | 550 | 861 s |
| `smooth-app` | 692 | 1251 s |
| `saber` | 165 | 1260 s |

Les durées non marquées « seul » ont été mesurées avec deux ou trois projets en
parallèle : elles surestiment, mais les écarts restent parlants. Même seul, un
projet de 500 fichiers prend de 12 à 15 minutes. Le `--dry-run` seul
(étapes structurelles) prend 196 s sur `1618-mobile-app`.

**Origine :** pour un run complet, `pipeline.dart` fait :

- 8 résolutions complètes du projet, une par étape (lignes 565 à 599) ;
- une de plus dans `abstract-final-classes`, qui résout tous les fichiers pour
  savoir quelles classes sont utilisées (`_analyzeProject`) ;
- une autre avec un `ProjectAnalyzer` neuf pour `organize-imports` (ligne 305) ;
- 3 analyses complètes dans des sous-processus : `dart analyze` de référence
  (ligne 100), `dart fix --apply` (ligne 282), `dart analyze` de vérification
  (ligne 632) ;
- `dart format` par lots de 200 fichiers.

L'analyse de référence attend la fin des étapes alors qu'elle n'en dépend pas
(elle lit le disque avant toute écriture).

**Pistes**, de la plus rentable à la plus coûteuse :

1. lancer le `dart analyze` de référence en parallèle des étapes ;
2. réutiliser l'analyseur des étapes pour `organize-imports` au lieu d'en
   démarrer un à froid ;
3. préfiltrer syntaxiquement les fichiers par passe pour ne pas résoudre ceux
   qui n'ont aucun candidat ;
4. enchaîner les étapes fichier par fichier quand les passes ne dépendent pas du
   reste du projet (toutes sauf `abstract-final-classes`) ;
5. afficher la durée de chaque étape en `--verbose`.

Mesurer avant et après sur le corpus de la campagne.

### B11. Un exécutable compilé ne trouve pas le SDK

**Gravité : basse aujourd'hui, mais prérequis de la correction de B19.**
`dart compile exe bin/dart_modernize.dart` puis lancement :
`PathNotFoundException(...\lib\_internal\sdk_library_metadata\lib\libraries.dart)`
puis `...\version`.

**Origine :** deux hypothèses « je tourne sous la VM Dart » dans le code.

- `lib/src/analysis/project_analyzer.dart`, ligne 37 : `AnalysisContextCollection`
  est créé sans `sdkPath`, et l'analyseur déduit le SDK de l'emplacement de
  l'exécutable.
- `pipeline.dart`, lignes 148, 243, 282 et 389 : `dart analyze`, `dart pub get`,
  `dart fix` et `dart format` sont lancés avec `Platform.resolvedExecutable`.
  Dans un exécutable compilé, c'est l'outil lui-même : il se relancerait avec
  `analyze` comme argument.

Aucun impact avec `dart pub global activate`, qui tourne sous la VM Dart.

**Correction proposée :** passer `sdkPath` résolu depuis `DART_SDK`,
`FLUTTER_ROOT` ou le `dart` du `PATH`, et lancer les sous-processus avec ce `dart`
plutôt qu'avec `Platform.resolvedExecutable`.

### B12. `--dry-run` et `--check` ignorent la finalisation

**Gravité : moyenne** (faux négatifs en CI).

```
$ cat lib/a.dart
import 'dart:math';
int   add(int a,int b){return a+b;}
$ dart_modernize --check --no-expression-bodies .
  ✓ Already modern -- 1 file(s) scanned, nothing to change.   (code 0)
$ dart_modernize --no-expression-bodies .
  ✓ Modernized 1 of 1 file(s).   fix-all 1 file, dart format 1 file
```

**Origine :** `pipeline.dart`, lignes 70 à 83 : le mode aperçu s'arrête avant
`_finalize`. Le README présente `--check` comme « exit non-zero if any file would
change », ce qui est faux pour `dart fix`, les imports et le formatage.

**Correction proposée :** au minimum, le documenter dans le README et l'aide. Mieux :
en mode `--check`, lancer aussi `dart format --output=none --set-exit-if-changed`
et `dart fix --dry-run` (peu coûteux). Le diff complet demanderait de rejouer la
finalisation sur une copie temporaire.

### B13. `abstract-final-classes` scelle des classes publiques d'un paquet

**Gravité : haute pour un paquet publié**, sans effet pour une application.

La passe ajoute `abstract final` à une classe qui n'a que des membres statiques et
que personne n'instancie, n'étend ni n'implémente **dans le projet analysé**. Pour
un paquet publié sur pub.dev, ses utilisateurs sont hors du projet : s'ils
étendent ou instancient la classe, leur code casse à la mise à jour du paquet.
C'est un changement d'API cassant fait en silence.

**Origine :** `abstract_final_classes.dart`, la doc de la classe le dit
elle-même : « This is an app-oriented transform: a public class in a published
library could be subclassed by downstream consumers not visible to the analyzer.
The guard checks only the project under analysis. » Pourtant la passe est active
par défaut, quel que soit le type de projet.

**Correction proposée :** si le `pubspec.yaml` n'a pas `publish_to: none`, ne
traiter que les classes privées ou celles de `lib/src/` qui ne sont pas
exportées. Constat fait à la lecture du code. Sur le seul paquet testé,
`flex_color_scheme`, la seule classe scellée dans `lib/` (`TextThemeColor`) est
interne (`lib/src/`, non exportée) : pas de casse ici, par chance.

### B14. Les passes ignorent la version de langage d'un fichier (`// @dart = 2.x`)

**Gravité : haute.** Constaté sur `smooth-app`,
`lib/generic_lib/dialogs/smooth_category_picker.dart`, qui commence par
`// @dart = 2.12`. L'outil y a écrit des paramètres `super.`, des
`.new(...)` et d'autres syntaxes récentes : 23 erreurs, dont
`EXPERIMENT_NOT_ENABLED: This requires the 'super-parameters' language feature`,
`... 'constructor-tearoffs' ...`, et des noms incohérents nés de la reprise sur
erreur de l'analyseur (`Undefined name 'PageControllerPageController'`,
`'SizeSizeSizeconst'`).

**Origine :** le validateur ne regarde que la contrainte SDK du `pubspec.yaml`.
Une seule passe, `primary-constructors`, vérifie la version de langage de la
bibliothèque (`featureSet.isEnabled(.primary_constructors)`, ligne 44). Toutes
les autres émettent leur syntaxe sans condition.

**Correction proposée :** dans `pipeline.dart`, ignorer toute bibliothèque dont
`unit.libraryElement.languageVersion.effective` est inférieure au plancher de
l'outil (3.13), et le signaler en `--verbose`. Plus fin : que chaque passe teste
la fonctionnalité qu'elle émet, comme `primary-constructors` le fait déjà.
L'analyseur expose les drapeaux nécessaires (`Feature.super_parameters`,
`.patterns`, `.null_aware_elements`, `.dot_shorthands`,
`.private_named_parameters`, `.primary_constructors`, `.wildcard_variables`).
Test : un fixture avec `// @dart = 2.12` doit ressortir inchangé.

### B15. `super-parameters` replie à tort vers un argument positionnel ou un constructeur nommé

**Gravité : haute.** Plusieurs défauts dans deux fonctions, constatés sur
`smooth-app` et `flex_color_scheme`.

```dart
// lib/widgets/will_pop_scope.dart
class WillPopScope2Controller extends ValueNotifier<bool> {
  WillPopScope2Controller({required bool canPop}) : super(canPop);
}
// Sortie : {required super.canPop}
// SUPER_FORMAL_PARAMETER_WITHOUT_ASSOCIATED_NAMED et
// IMPLICIT_SUPER_INITIALIZER_MISSING_ARGUMENTS

// lib/resources/app_icons.dart
const AddToList._count({required IconData iconData, super.color, super.key})
    : super._(iconData);
// Sortie : `iconData` devient `super.iconData` ET tout `: super._(iconData)` disparaît.
// L'appel implicite devient `super()`, or AppIcon n'a que `AppIcon._(...)` :
// UNDEFINED_CONSTRUCTOR_IN_INITIALIZER.
```

**Origine :** `super_parameters.dart`.

- `_tryFold`, lignes 197 à 238 : la correspondance de nom n'est vérifiée que pour
  un argument nommé (lignes 228 à 232), et la **nature** du paramètre local n'est
  jamais comparée à celle de l'argument. Un paramètre `super.` nommé ne peut
  alimenter qu'un paramètre nommé du parent, un positionnel qu'un positionnel au
  même rang. Les deux sens ont été vus : nommé vers positionnel sur `smooth-app`
  (ci-dessus), positionnel vers nommé sur `flex_color_scheme`
  (`SizeAnimation(Animation<double> parent) : super(parent: parent)` donne
  `SUPER_FORMAL_PARAMETER_WITHOUT_ASSOCIATED_POSITIONAL` et
  `MISSING_REQUIRED_ARGUMENT: The named parameter 'parent' is required`).
- `_removeSuperCall`, lignes 148 à 180 : quand tous les arguments sont repliés,
  l'initialiseur `super(...)` est supprimé entièrement, même quand il appelle un
  constructeur **nommé** (`super._(...)`, `super.named(...)`). Il faut alors
  garder `: super._()`.
- Règle du langage à respecter aussi : un constructeur ne peut pas avoir à la fois
  des paramètres `super.` positionnels et des arguments positionnels dans son
  `super(...)`. `_keepRemainingArguments` produit ce cas, constaté sur `devtools`
  (`deep_links_model.dart` : `POSITIONAL_SUPER_FORMAL_PARAMETER_WITH_POSITIONAL_ARGUMENT`).

`devtools` confirme les trois défauts sur six fichiers (`sampler.dart`,
`cpu_profile_model.dart`, `custom_pointer_scroll_view.dart`, `table_data.dart`,
`deep_links_model.dart`...).

**Correction proposée :** n'accepter un argument positionnel que si le paramètre
local est positionnel, au même rang, et si tous les arguments positionnels sont
repliés ; garder `: super.nom()` vide pour un constructeur nommé. Tests : les deux
exemples ci-dessus, et un repli partiel avec un argument positionnel restant.

### B16. `dot-shorthands` dans un record renvoyé par une fonction `async`

**Gravité : haute.** Constaté sur `smooth-app`, sur `devtools`
(`heap_graph_loader.dart` : `return (snapshot, DateTime.now());` dans un
`Future<(HeapSnapshotGraph, DateTime)> load() async`) et sur `thunder` (trois clients
d'API, par exemple `lib/src/core/networking/lemmy_v3_api_client.dart`, où
`Future<GetCommunityResponse> getCommunity(...) async` renvoie un record à champs
nommés contenant `site: json['site'] != null ? ThunderSite.fromLemmySite(...) : null`).
Sur `smooth-app`, `lib/pages/prices/price_category_input_page.dart` :

```dart
Future<(bool, PriceMetaProduct?)> _mayExitPage({...}) async {
  ...
  return (true, PriceMetaProduct.category(categoryName: ...));
}
// Sortie : return (true, .category(...));
// DOT_SHORTHAND_UNDEFINED_MEMBER: The static method or constructor 'category'
// isn't defined for the context type '_'.
```

**Origine :** `dot_shorthands.dart`, lignes 510 à 515 : pour une fonction `async`,
la passe prend `T` dans `Future<T>` comme contexte du `return`. Pour le langage, ce
contexte est `FutureOr<T>`. Un dot shorthand placé directement dans le `return`
fonctionne, parce que la règle des dot shorthands déballe `FutureOr`. Mais
l'inférence ne propage pas `FutureOr<(bool, X?)>` vers les champs d'un littéral de
record : ils n'ont aucun contexte (`_`). `_recordFieldContext` (ligne 734) suppose
le contraire.

**Correction proposée :** dans `_recordFieldContext`, ne rien proposer quand le
record est l'expression d'un `return` (ou d'un `=>`) dans un corps `async`. Test :
le cas ci-dessus, plus la variante `=> (true, Foo.bar())` en `async`.

### B17. `dart fix` ajoute un `const` invalide après la promotion

**Gravité : haute.** Constaté sur `smooth-app` (4 fichiers, dont
`lib/pages/onboarding/currency_selector.dart`) et sur `devtools`
(`process_memory_view.dart`, `editable_list.dart`) :
`CONST_CONSTRUCTOR_WITH_FIELD_INITIALIZED_BY_NON_CONST`, et sur `devtools` aussi
`LATE_FINAL_FIELD_WITH_CONST_CONSTRUCTOR` (un champ `late final` resté dans le
corps de la classe devenue `const`).

```dart
// Avant : constructeur non const, à cause du champ initialisé.
class CurrencySelector extends StatelessWidget {
  CurrencySelector({this.textStyle, this.padding, this.icon});
  ...
  final CurrencySelectorHelper helper = CurrencySelectorHelper();
}
```

`primary-constructors` produit `class CurrencySelector({...}) extends StatelessWidget { final CurrencySelectorHelper helper = CurrencySelectorHelper(); ... }`,
qui compile. Puis `fix-all` lance `dart fix`, et le lint
`prefer_const_constructors_in_immutables` (activé par `flutter_lints`) se
déclenche **à tort** sur le constructeur primaire : il ne tient pas compte du champ
initialisé dans le corps. `dart fix` ajoute `const` et le fichier ne compile plus.

Reproduit sans Flutter avec le SDK 3.13.5 (`package:meta`, `@immutable`) : le lint
signale la classe à constructeur primaire et pas la classe équivalente écrite à
l'ancienne.

**Origine :** bug du lint dans le SDK Dart 3.13.5, déclenché par la promotion.

**Correction proposée :** dans `primary-constructors`, ne pas promouvoir une classe
non `const` qui garde dans son corps un champ d'instance avec un initialiseur ou
un champ `late`, si la classe ou un parent porte `@immutable` (donc tous les
widgets). Signaler le bug
au SDK (`dart-lang/sdk`) avec la reproduction minimale.

### B18. Des passes font apparaître des lints du projet

**Gravité : moyenne** (casse une CI en `--fatal-infos`). Constaté sur `smooth-app` :
25 nouveaux `avoid_classes_with_only_static_members` (et un
`use_late_for_private_fields_and_variables`).

```dart
// Avant
class CameraHelper {
  const CameraHelper._();
  static Set<CameraLensType>? _cameraLensTypesBack;
}
// Après
abstract final class CameraHelper {
  static Set<CameraLensType>? _cameraLensTypesBack;
}
```

Le constructeur privé faisait taire le lint, que le projet active. La passe le
supprime (comportement documenté), le lint se déclenche.

Même famille sur `flex_color_scheme` : 11 nouvelles infos `unnecessary_ignore`.
L'auteur avait volontairement laissé des constructeurs après les champs, avec
`// ignore: sort_constructors_first` (`example/lib/shared/utils/breakpoint.dart`,
`code_theme.dart`, `topic_theme.dart`...). `sort-constructors-first` les déplace
quand même, et les `// ignore` deviennent inutiles.

**Correction proposée :** si le projet active `avoid_classes_with_only_static_members`,
garder le constructeur privé, ou ne pas toucher ces classes ; dans
`sort-constructors-first`, ne pas toucher une classe qui porte un
`// ignore: sort_constructors_first` (ou `ignore_for_file`). Plus généralement, I3
(comparer aussi les infos et avertissements, pas seulement les erreurs).

### B19. Crash de la VM pendant la résolution des gros projets

**Gravité : critique.** L'outil s'arrête net pendant « Resolving… », sans message
exploitable.

| Projet | Conditions | Résultat |
|:--|:--|:--|
| `flex_color_scheme` | run 1, deux autres projets en parallèle | crash après 46 s : `ExceptionCode=-1073741819` (violation d'accès, `0xC0000005`) à l'adresse `00007FF709FA3AFC`, « Stack dump aborted because GetAndValidateCurrentThreadStackBounds failed » |
| `flex_color_scheme` | `--dry-run`, en parallèle | même crash |
| `flex_color_scheme` | 10 dry-runs `--only`, un par groupe de passes, en parallèle | 3 crashes avec des groupes sans rapport entre eux, et une fois `RangeError (length): Invalid value: Not in inclusive range 0..138638: 1125899906940397` dans `_StringCanonicalizer.hashString` de l'analyseur |
| `flex_color_scheme` | run 2 en parallèle, run 3 seul | pas de crash |
| `lichess` | run 1, en parallèle | crash après 4 s, même adresse |
| `lichess` | deux dry-runs, en parallèle | pas de crash |
| `devtools` | run 1, en parallèle | crash après 265 s, même adresse |
| `anda` | deux runs, trois projets en parallèle | `zone.cc: 95: error: Out of memory`, pendant la compilation JIT optimisée d'une fonction de l'analyseur (`informative_data.dart`) |
| version AOT de l'outil | `flex_color_scheme` (3 dry-runs complets), `lichess`, sonde ci-dessous | aucun crash |

**Relancés seuls sur la machine**, les trois projets vont au bout sans crash :
`flex_color_scheme` en 446 s, `lichess` en 861 s, `devtools` en 757 s. Tous les
crashes observés ont eu lieu avec deux ou trois autres projets en cours sur la
machine. La charge (mémoire disponible, compilation JIT concurrente) joue donc un
rôle, mais un utilisateur qui lance l'outil pendant un build Flutter ou avec son
IDE ouvert est dans cette situation.

**Reproduction déterministe d'un cas voisin.** Un projet minimal avec un
`operator ==` qui enchaîne 1000 comparaisons par `&&` :

- `dart analyze` : « No issues found! » ;
- l'outil (JIT, comme `dart run` ou `dart pub global activate`) :
  `Unhandled exception: Stack Overflow`, dans
  `package:analyzer/src/dart/resolver/binary_expression_resolver.dart`
  (6 658 appels dans la trace) ;
- l'outil compilé en AOT : aucune erreur.

`flex_color_scheme` contient justement une chaîne de 314 `&&` dans
`FlexSubThemesData.operator ==` (`lib/src/flex_sub_themes_data.dart`), le genre de
code qu'écrivent les générateurs d'égalité.

**Origine probable.** L'outil fait tourner l'analyseur dans la VM en mode JIT. Le
code pas encore optimisé y utilise des cadres de pile bien plus gros qu'en AOT,
le mode de `dart analyze`. La récursion de l'analyseur sur une expression très
profonde approche alors la limite de la pile. Quand le débordement survient dans
du code natif de la VM plutôt que dans du code Dart, la VM ne peut pas lever de
`StackOverflowError` et s'arrête sur une violation d'accès. Le moment où le
compilateur JIT optimise une fonction, et la mémoire disponible, expliqueraient le
caractère aléatoire. Hypothèse cohérente avec toutes les observations, mais non
prouvée au niveau de la VM.

**Correction proposée :**

1. tout de suite : capturer `StackOverflowError` autour de la résolution de
   chaque fichier, ignorer ce fichier et le signaler, au lieu de faire tomber
   tout le run (couvre le cas déterministe, pas la violation d'accès) ;
2. ensuite : proposer un exécutable AOT (binaires attachés aux releases GitHub),
   ce qui suppose de corriger B11 ;
3. documenter de ne pas lancer plusieurs instances en parallèle sur une machine
   chargée ;
4. signaler le crash à `dart-lang/sdk` avec la sonde des 1000 `&&` et l'adresse
   d'exception.

### B20. Déstructuration d'une valeur nullable

**Gravité : haute.** Constaté sur `devtools` (`debugger_controller.dart`, voir
B6) et sur `thunder`,
`lib/src/features/user/presentation/widgets/user_selector.dart` :

```dart
final response = await createUserRepository(targetAccount).getUser(username: username);
final user = response?.user;
// Réécrit en motif objet sur `response`, dont le type est nullable :
// PATTERN_TYPE_MISMATCH_IN_IRREFUTABLE_CONTEXT: The matched value of type
// '...?' isn't assignable to the required type '...'.
```

Si le code avait compilé, le sens aurait changé : `response?.user` vaut `null`
quand `response` est nul, alors qu'un motif irréfutable lèverait une exception.

**Origine :** `destructure_locals.dart`.

- `_fieldBinding`, lignes 178 à 187 : une `PropertyAccess` est acceptée quel que
  soit son opérateur, donc `response?.user` compte comme une lecture de champ
  ordinaire.
- `_pattern`, lignes 115 à 121 : le motif est construit à partir de
  `type.element.name` sans vérifier `type.nullabilitySuffix`.

`destructure_for_in.dart` (lignes 71 à 73) fait la même hypothèse pour l'élément
d'une boucle : une `List<Foo?>` donnerait `for (final Foo(:x) in list)`.

**Correction proposée :** exiger un type non nullable et un opérateur `.` (refuser
`?.`). Tests : initialiseur nullable, lecture `?.`, boucle sur une liste
d'éléments nullables.

### B21. Le formatage final réécrit tout le projet à 80 colonnes

**Gravité : haute** pour un projet formaté autrement. Constaté sur `thunder`, dont
la CI lance `dart format -o none --set-exit-if-changed -l 200 lib` :

- 630 fichiers modifiés, 37 706 lignes ajoutées et 18 800 supprimées, presque
  uniquement du reformatage ;
- 56 nouvelles infos `curly_braces_in_flow_control_structures` : un
  `if (...) return;` coupé sur deux lignes n'est plus accepté sans accolades ;
- 2 nouvelles infos `deprecated_member_use` : un `// ignore: deprecated_member_use`
  en fin de ligne a été déplacé par le formateur et ne couvre plus l'appel
  déprécié :

```dart
// Avant
    textScaleFactor: MediaQuery.textScaleFactorOf(context), // ignore: deprecated_member_use
// Après
        textScaleFactor: MediaQuery.textScaleFactorOf(
          context,
        ), // ignore: deprecated_member_use
```

- la CI du projet échouerait sur le formatage.

Sur `1618-mobile-app` (projet non formaté), le même mécanisme mélange le
formatage de 88 fichiers avec la modernisation.

**Origine :** `pipeline.dart`, lignes 384 à 398 : `dart format` tourne toujours,
sur **tous** les fichiers analysés, modifiés ou non, avec la largeur par défaut.
Seule une largeur déclarée dans `analysis_options.yaml` (`formatter: page_width:`)
est respectée, par `dart format` lui-même. Il n'existe ni `--no-format`, ni option
de largeur.

**Correction proposée :**

1. ne formater que les fichiers que l'outil a modifiés ;
2. ajouter `--no-format` (et `format` dans `disabled:` de la configuration) ;
3. ajouter `--line-length`, ou détecter la largeur utilisée par le projet ;
4. comparer les infos avant et après (I3) pour signaler les `// ignore` déplacés.

### B22. `dot-shorthands` dans une collection passée à un constructeur générique

**Gravité : haute.** Constaté sur `lichess` : 16 des 18 fichiers annulés ont des
erreurs de dot shorthand (36 `DOT_SHORTHAND_MISSING_CONTEXT`, 12
`DOT_SHORTHAND_UNDEFINED_MEMBER`, avec en cascade 23 `NON_CONSTANT_SET_ELEMENT`, 3
`NON_CONSTANT_MAP_KEY`, des `INVALID_CONSTANT`, `ARGUMENT_TYPE_NOT_ASSIGNABLE:
'Object?'` et `UNCHECKED_USE_OF_NULLABLE_VALUE`). Les cas examinés relèvent tous
de cette cause ; les autres fichiers n'ont pas été examinés un par un. Le projet
utilise beaucoup `fast_immutable_collections` :

```dart
// lib/src/model/explorer/opening_explorer_preferences.dart
static const kAvailableSpeeds = ISetConst({
  Speed.ultraBullet,
  Speed.bullet,
  ...
});
// Sortie : ISetConst({.ultraBullet, .bullet, ...})
// DOT_SHORTHAND_MISSING_CONTEXT et NON_CONSTANT_SET_ELEMENT

// lib/src/model/user/user_repository.dart, dans un littéral de map passé à IMap(...)
Perf.nameMap.get(entry.key)!: UserActivityScore.fromJson(entry.value),
// Sortie : ...: .fromJson(entry.value)  (contexte '_')
```

`ISetConst<T>(Set<T> set)` n'a pas d'argument de type explicite : `T` est inféré
**depuis** le littéral, donc ses éléments n'ont aucun contexte. Le type du
paramètre après inférence (`Set<Speed>`) n'est pas un contexte.

**Origine :** `dot_shorthands.dart`. `_enclosingCollectionElementType` (lignes 447
à 466) et `_listElementType` (lignes 618 à 635) prennent pour contexte des éléments
le type « descendant » du littéral calculé par `_contextType`, qui pour un argument
vaut le type du paramètre **après** substitution des arguments de type inférés.
`_listElementType` retombe même sur le type inféré du littéral. La garde qui
traite ce cas, `_invokedTypeParameters` (lignes 556 à 575, ajoutée en 0.7.0), ne
s'applique qu'à un argument qui est lui-même un dot shorthand, pas aux éléments
d'une collection passée en argument.

**Correction proposée :** appliquer la même garde quand le littéral est l'argument
d'un appel générique sans `<...>` explicite dont le paramètre mentionne un
paramètre de type de l'appel ; ne jamais utiliser le type inféré d'un littéral
comme contexte de ses propres éléments, sauf quand la passe écrit elle-même
l'argument de type (comme `_annotateInferredList` le fait pour les records).
Tests : `ISetConst({...})`, `IMap({...})`, `IList([...])`, et un `Set<T>`
générique maison.

### B23. `prefer-inferred-types` sur un champ qui redéfinit un membre hérité

**Gravité : critique** : c'est le seul bug qui a laissé du code qui ne compile
plus sur le disque à la fin d'un run réel (voir B7).

Constaté sur `devtools`, `lib/src/shared/memory/classes.dart` :

```dart
class SingleClassData extends ClassData {
  @override
  // ignore: avoid-explicit-type-declaration, required to override base class.
  final ObjectSet objects = ObjectSet();
}
// Sortie :
  @override
  final objects = ObjectSet();
```

Pour un champ d'instance sans type qui redéfinit un membre hérité, Dart ne prend
pas le type de l'initialiseur : il reprend celui du membre parent
(`ClassData.objects`, de type `ObjectSetStats`). Le champ passe de `ObjectSet` à
`ObjectSetStats`. Le fichier compile, mais les appelants cassent
(`classes_diff.dart`, `classes_table_single.dart` : `ARGUMENT_TYPE_NOT_ASSIGNABLE:
The argument type 'ObjectSetStats?' can't be assigned to the parameter type
'ObjectSet?'`). `--verify` annule ces appelants (qui avaient d'autres
modifications), pas `classes.dart` : **3 erreurs restent après le run.** L'auteur
avait justement écrit en commentaire que le type était nécessaire.

Même cause dans `test/test_infra/test_data/memory/heap/heap_graph_fakes.dart` :
`final List<FakeSnapshotObject> objects = <FakeSnapshotObject>[...]`, qui redéfinit
`HeapSnapshotGraph.objects`, devient `List<HeapSnapshotObject>`, et les tests qui
écrivent `shallowSize` ou appellent `addReference` sur ses éléments cassent
(`ASSIGNMENT_TO_FINAL_NO_SETTER`, `UNDEFINED_METHOD`, `UNDEFINED_GETTER`).

**Origine :** `prefer_inferred_types.dart`, `visitFieldDeclaration` (ligne 60) et
`_collect` (ligne 120) : un champ d'instance `final` avec initialiseur est traité
comme une variable locale. Rien ne vérifie s'il redéfinit un membre d'un
supertype, cas où l'inférence suit une autre règle.

**Correction proposée :** ne jamais retirer le type d'un champ d'instance qui
redéfinit un membre hérité (annotation `@override`, ou membre de même nom trouvé
dans les supertypes via l'élément de la classe). Tests : les deux cas ci-dessus,
plus un getter abstrait redéfini par un champ.

### B24. `null-aware-conditionals` casse une chaîne écrite sur plusieurs lignes

**Gravité : haute** (erreur de syntaxe). Constaté sur `devtools`,
`lib/src/screens/memory/shared/heap/class_filter.dart` :

```dart
// Avant
Set<String> stringToSet(String? s) => s == null
    ? {}
    : s
          .split(',')
          .map((e) => e.trim())
          .toSet();

// Sortie (invalide)
Set<String> stringToSet(String? s) => s?
          .split(',')
          .map((e) => e.trim())
          .toSet() ?? {};
```

`?` et `.` séparés par un saut de ligne ne forment plus l'opérateur `?.` : le
parseur voit un `? :` incomplet (`MISSING_IDENTIFIER`, `EXPECTED_TOKEN: Expected to
find ':'`, `NON_BOOL_CONDITION`, et un `.split` pris pour un dot shorthand).

**Origine :** `null_aware_conditionals.dart`, ligne 94 :
`_render(chain.expression, insertAt: chain.rootEnd)`. Le `?` est inséré à la fin
de la racine de la chaîne (`s`), pas juste avant le jeton `.` qui suit.

**Correction proposée :** insérer `?` à l'offset du jeton `.` (l'`operator` de la
`PropertyAccess` ou de la `MethodInvocation`). Test : la chaîne sur plusieurs
lignes ci-dessus, et une avec un commentaire entre la racine et le `.`.

### B25. `inline-return` change le contexte d'inférence de l'expression

**Gravité : haute.** Constaté sur `devtools`,
`lib/src/screens/debugger/breakpoint_manager.dart`, dans une fonction `async` qui
renvoie `Future<Map<String, ScriptRef>>` :

```dart
// Avant (méthode _scriptRefsForBreakpoints, corps async)
final scriptUriToRef = newScripts.fold(<String, ScriptRef>{}, (
  scriptMap,
  script,
) {
  final scriptUri = script.uri;
  if (scriptUri != null && bpScriptUris.contains(scriptUri)) {
    scriptMap[scriptUri] = script;
  }
  return scriptMap;
});

return scriptUriToRef;

// Sortie
return newScripts.fold(<String, ScriptRef>{}, (scriptMap, script) {
  ...
    scriptMap[scriptUri] = script;   // UNDEFINED_OPERATOR: The operator '[]='
  ...                                // isn't defined for the type
});                                  // 'FutureOr<Map<String, ScriptRef>>'
```

Dans la déclaration, l'appel générique `fold<T>` n'avait pas de contexte et `T`
valait `Map<String, ScriptRef>`. Dans le `return` d'une fonction `async`, le
contexte devient `FutureOr<Map<String, ScriptRef>>` et l'inférence choisit ce type
pour `T`.

**Origine :** `inline_return.dart` ne vérifie que la forme du code (une
déclaration, puis `return` de cette variable) et jamais les types. Le même
problème se pose avec une déclaration typée (`final Foo x = expr; return x;`), où
le contexte passe de `Foo` au type de retour de la fonction.

**Correction proposée :** n'inliner que si l'initialiseur n'a pas d'inférence
dépendant du contexte : pas d'appel générique sans `<...>` explicite, pas de
littéral de collection sans arguments de type, pas de closure ; ou bien comparer
le type statique de la variable au type de retour attendu, et s'abstenir dans un
corps `async` si l'expression n'est pas déjà un `Future`.

### Autres constats (pas des bugs)

- **Lisibilité de `dot-shorthands`** sur du code Flutter :
  `key: const .new('editTodoView_title_textFormField')`, `decoration: .new(`,
  `.new(color: .new(0x0A000000), blurRadius: 8, offset: .new(0, 2))`. Tout
  compile, mais beaucoup d'équipes trouveront cela moins lisible. Proposition :
  une option de configuration pour garder les constructeurs qualifiés tout en
  raccourcissant les valeurs d'enum et les membres statiques (I5).
- **Promotion incohérente des widgets :** `const _TitleField();` (sans paramètre)
  devient `class const _TitleField() extends StatelessWidget`, mais un widget avec
  `super.key` n'est jamais promu (paramètres `super.` refusés).
- **Le formatage s'applique à tous les fichiers** : sur un projet non formaté, le
  diff mélange formatage et modernisation (`1618-mobile-app`).
- **Projets refusés d'emblée :** contrainte SDK inférieure à 3.13
  (`1618-mobile-app` en `^3.7.0`). Message clair, mais aucun moyen de migrer avec
  l'outil (I2). Versions de Flutter figées (`lichess` 3.47.5, `immich` 3.47.2) :
  `pub get` échoue, ce n'est pas le problème de l'outil.

## 6. Nouvelles passes proposées

| ID | Passe | Dart | Défaut proposé | Étape | Lint équivalent | Priorité |
|:--|:--|:--|:--|:--|:--|:--|
| P1 | `constructor-shorthands` | 3.13 | activée | 8 | `unnecessary_type_name_in_constructor`, `unnecessary_const_in_enum_constructor` | 0.12.0 |
| P2 | `empty-bodies` | 3.13 | activée | 8 | `empty_container_bodies` | 0.12.0 |
| P3 | `primary-constructors` v2 | 3.13 | activée (sauf 3.f) | 3 | `use_declaring_parameters`, `initialize_in_field_declaration` | 0.12.0 pour 3.a et 3.b, 3.c à 3.e si le temps le permet |
| P4 | `future-pause` | 3.13 | activée | 4 | aucun | 0.12.0 |
| P5 | `wildcard-parameters` | 3.7 | activée | 8 | `unnecessary_underscores` | 0.12.0 |
| P6 | `null-aware-calls` | 2.x | activée | 4 | `prefer_null_aware_method_calls` | 0.12.0 ou 0.13.0 |
| P7 | `unmodifiable-of` | 3.13 | désactivée | 4 | aucun | plus tard |

Pourquoi des passes plutôt que d'activer les lints dans `fix-all` : les passes
s'appliquent quel que soit l'`analysis_options.yaml` du projet, apparaissent dans
`--dry-run`, se sélectionnent avec `--only` et se testent avec les suites golden,
d'idempotence et de convergence. L'alternative (injecter temporairement une liste
de lints et laisser `dart fix` corriger) est décrite en I6.

Règles communes à chaque nouvelle passe :

- vérifier la version de langage de la bibliothèque, comme le fait déjà
  `primary-constructors` (`featureSet.isEnabled(.primary_constructors)` pour P1,
  P2 et P3 ; `.wildcard_variables` pour P5) ;
- ne jamais toucher un passage qui contient un commentaire ;
- produire un texte que `dart format` ne réécrit pas, sinon le second run n'est
  pas vide ;
- fichiers à toucher : la passe dans `lib/src/pipeline/transformations/`, son
  étape dans `transformations.dart`, son option dans `lib/src/cli/options.dart`
  (et `defaultOffTransformations` si elle est désactivée par défaut),
  `README.md` (tableau des passes et exemples), `doc/ORDERING.md`,
  `test/fixtures/README.md` (le compte de passes), `CHANGELOG.md` ;
- tests : `test/golden/<passe>_test.dart` et `test/fixtures/<passe>/`
  (`*.input.dart`, `*.expected.dart`, `*.unchanged.dart`), un cas dans
  `test/support/triggers.dart`, `test/cli/pipeline_order_test.dart`,
  `test/cli/options_test.dart`, `test/cli/only_selection_test.dart`,
  `test/cli/idempotence_test.dart`, `test/e2e/pass_convergence_test.dart`, et la
  vérification de compilation de `test/semantic/analyzes_clean_test.dart`.

### P1. `constructor-shorthands`

C'est la passe demandée. Elle applique les règles de la section 3.1.

```dart
// Avant
class Point {
  const Point(this.x, this.y);
  const Point.origin() : x = 0, y = 0;
  factory Point.fromJson(Map<String, Object?> json) => Point(json['x'] as int, json['y'] as int);
  final int x;
  final int y;
}

enum Level {
  low(1),
  high(2);

  const Level(this.value);
  final int value;
}

// Après
class Point {
  const new(this.x, this.y);
  const new origin() : x = 0, y = 0;
  factory fromJson(Map<String, Object?> json) => Point(json['x'] as int, json['y'] as int);
  final int x;
  final int y;
}

enum Level {
  low(1),
  high(2);

  new(this.value);
  final int value;
}
```

**Mise en œuvre.** Pour chaque `ConstructorDeclaration` dont `typeName2` n'est pas
nul (ancienne forme), dans une classe, une `mixin class`, un enum ou un extension
type :

- génératif : remplacer l'intervalle `[typeName2.offset, (name ?? typeName2).end)`
  par `new` ou `new <nom>` (un nom explicite `new`, comme dans `C.new()`, donne
  `new`) ;
- `factory` : remplacer le même intervalle par `<nom>`, ou le supprimer avec
  l'espace qui suit pour un constructeur sans nom (`factory C(` devient
  `factory(`) ;
- enum : supprimer aussi `const ` d'un constructeur génératif ;
- ne rien faire s'il y a un commentaire entre `typeName2` et la parenthèse.

**API analyzer.** `ConstructorDeclaration.typeName2` (marqué `@experimental`) est
absent d'analyzer 14.0 et 14.1 et présent dans 14.3 et 14.4 (14.2 non vérifiée).
Les anciennes versions n'ont que `typeName`, annoncé comme bientôt déprécié.
`newKeyword`, `FormalParameter.defaultClause`, `PrimaryConstructorBody` et
`EmptyClassBody` existent dès 14.0. Utiliser `typeName2` et relever la contrainte
à `analyzer: ^14.5.0` (voir 8).

**Placement.** Étape 8. Elle doit venir après `primary-constructors` (étape 3),
qui recopie tels quels les membres conservés, factories comprises. Elle ne
modifie que l'en-tête du constructeur, que `dot-shorthands`,
`super-parameters` et `private-named-parameters` ne touchent pas.

**Points à vérifier :** `sort-constructors-first` et `MemberSorter` repèrent
déjà les constructeurs par leur type de nœud, donc la nouvelle forme ne change
rien ; `abstract-final-classes` cherche un constructeur privé par son nom (`_`),
toujours présent dans `new _()` ; `dot-shorthands` tire le contexte d'une factory
de son élément (ligne 504), pas de son nom.

**Tests golden :** sans nom, nommé, privé, `C.new()`, `const`, `external`,
redirection générative, factory sans nom et nommée, factory de redirection
`const`, classe générique, enum (`const` supprimé), extension type,
`mixin class`, commentaire dans l'en-tête (inchangé), forme déjà courte
(inchangée).

### P2. `empty-bodies`

Applique la section 3.3 : `{}` devient `;` pour une classe, une `mixin class`, un
mixin, un extension type ou une extension dont le corps est vide.

```dart
// Avant
sealed class TodosOverviewEvent {}
final class TodosOverviewSubscriptionRequested extends TodosOverviewEvent {}
class CacheMissException implements Exception {}

// Après
sealed class TodosOverviewEvent;
final class TodosOverviewSubscriptionRequested extends TodosOverviewEvent;
class CacheMissException implements Exception;
```

**Mise en œuvre.** `BlockClassBody` sans membre, sans commentaire entre les
accolades : remplacer l'intervalle de l'espace qui précède `{` jusqu'à `}` par
`;`. Enums exclus (un enum a toujours des valeurs).

**Placement.** Étape 8. `primary-constructors` produit déjà `;` quand il ne reste
aucun membre, donc pas de conflit. `abstract-final-classes` modifie le début de la
déclaration, P2 la fin.

### P3. `primary-constructors` v2

D'abord les corrections (obligatoires), puis des extensions, chacune avec ses
propres golden.

| Sous-partie | Contenu | Avant | Après |
|:--|:--|:--|:--|
| 3.a | corriger B1 | `Config({this.port = 8080})` | `class Config({final int port = 8080})` |
| 3.b | corriger B2 | constructeur documenté ou annoté | inchangé |
| 3.c | `assert` dans la liste d'initialisation | `Range(this.min, this.max) : assert(min <= max);` | `class Range(final int min, final int max) { this : assert(min <= max); }` |
| 3.d | constructeur nommé ou privé seul génératif | `Vec._(this.x, this.y);` plus des factories | `class Vec._(final int x, final int y) { factory zero() => Vec._(0, 0); }` |
| 3.e | champs déclarés ensemble | `final int x, y;` | `class P(final int x, final int y);` |
| 3.f | paramètres `super.` (widgets Flutter) | `const Title({super.key, required this.text});` | `class const Title({super.key, required final String text}) extends StatelessWidget { ... }` |
| 3.g | enums | `const Planet(this.mass);` | `enum Planet(final double mass) { ... }` |
| 3.h | initialisation depuis un paramètre non déclarant | `Scaled(int raw) : _value = raw * 2;` | `class Scaled(int raw) { final int _value = raw * 2; }` |

Recommandations :

- 3.a et 3.b d'abord, dans un commit à part, avec les tests de B1 et B2.
- 3.f transforme presque tous les widgets d'un projet Flutter : diff énorme et
  goût discutable. À proposer **désactivé par défaut**, par exemple sous un nom
  de passe distinct (`primary-constructors-super`), parce que la configuration ne
  sait aujourd'hui qu'activer ou désactiver une passe entière.
- 3.g et 3.h plus tard : faible gain et plus de cas limites.
- `sort-constructors-first` et `MemberSorter` doivent traiter la déclaration
  `this : ...` (`PrimaryConstructorBody`) comme un constructeur. Aujourd'hui ils
  ne regardent que `ConstructorDeclaration` (`constructor_sorter.dart:59`,
  `member_sorter.dart:155`).
- Ne jamais émettre de `this;` vide (lint `unnecessary_primary_constructor_body`).

### P4. `future-pause`

```dart
// Avant
await Future.delayed(const Duration(milliseconds: 300));
await Future.delayed(Duration.zero);

// Après
await Future.pause(const Duration(milliseconds: 300));
await Future.pause();
```

**Règles :** un seul argument (pas de callback) ; seulement quand le résultat est
attendu par `await` dans une instruction, utilisé comme instruction, ou renvoyé
dans une fonction `Future<void>`. `Future<int>.delayed(d)` sans callback est
exclu : il échoue à l'exécution et la réécriture changerait le type.

**Placement.** Étape 4 : avant `expression-bodies` (étape 5), qui recopie le
corps, et avant `dot-shorthands` (étape 8), qui voudrait réduire le même appel en
`.delayed(...)`.

### P5. `wildcard-parameters`

Depuis Dart 3.7, `_` ne crée plus de variable et peut se répéter. Les `__`,
`___` écrits pour contourner l'ancienne règle deviennent inutiles. Très fréquent
dans les builders Flutter.

```dart
// Avant
separatorBuilder: (_, __) => const Divider(),
errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),

// Après
separatorBuilder: (_, _) => const Divider(),
errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
```

**Règles :** paramètres positionnels (et `catch`) dont le nom ne contient que des
`_`, jamais lus ; les paramètres nommés sont exclus, leur nom fait partie de
l'API. Étape 8.

### P6. `null-aware-calls`

```dart
// Avant
if (onChanged != null) onChanged!(value);
if (widget.onTap != null) {
  widget.onTap!();
}
if (controller != null) controller.dispose();

// Après
onChanged?.call(value);
widget.onTap?.call();
controller?.dispose();
```

**Règles :** `if` sans `else`, condition `x != null`, corps réduit à une seule
instruction-expression dont la cible est exactement `x` (avec ou sans `!`) ; `x`
est une variable locale, un paramètre, un champ `final` ou un getter d'un champ
`final` d'un autre objet (`widget.onTap`). Avec un getter, la version null-aware
n'évalue `x` qu'une fois au lieu de deux, ce qui ne change rien pour un champ
`final`.

**Placement.** Étape 4. Avant `expression-bodies` (étape 5), qui pourra ensuite
écrire `void dispose() => controller?.dispose();`, et avant
`null-aware-conditionals` (étape 6), qui pourrait sinon éditer un `?:` à
l'intérieur du même `if` et entrer en conflit dans `EditCollector`.

### P7. `unmodifiable-of` (plus tard)

`List.unmodifiable(x)` vers `List.unmodifiableOf(x)`, `Map.unmodifiable(m)` vers
`Map.unmodifiableOf(m)`. Le SDK prépare la dépréciation de l'ancienne forme. Le
risque est l'inférence : `List.unmodifiable([1, 2])` sans contexte donne un
`List<dynamic>`, `unmodifiableOf` un `List<int>`. Réécrire seulement si le type
statique du résultat ne change pas. À reporter tant que la dépréciation n'est pas
effective ; `dart fix` proposera probablement alors un correctif.

### Idées écartées

- **Classes scellées automatiques** (`sealed` quand toutes les sous-classes sont
  dans la bibliothèque) : change la sémantique (exhaustivité, interdiction
  d'étendre ailleurs).
- **Enum à partir d'une classe à constantes statiques** : change le type et
  l'identité des valeurs.
- **`if (x case final v?)` à la place d'une variable locale puis d'un test** :
  question de goût, gain faible.

## 7. Améliorations de l'outil hors passes

Les corrections de B7 (vérification de tout le projet), B8 (restauration en cas
de crash), B9 (rapport de succès partiel), B10 (performance), B11 (`sdkPath`) et
B12 (`--check`) sont décrites avec les bugs. Les améliorations ci-dessous vont
plus loin.

| ID | Amélioration | Gain | Coût |
|:--|:--|:--|:--|
| I1 | Annulation par passe au lieu de par fichier | garde les bonnes éditions d'un fichier annulé | moyen |
| I2 | Option `--upgrade-sdk` | permet de lancer l'outil sur un projet en dessous de 3.13 | faible |
| I3 | Signaler les nouveaux avertissements et infos | évite de casser une CI en `--fatal-infos` (B18) | faible |
| I4 | Vérification à chaque étape, en mémoire | rattrape les erreurs avant toute écriture, passe par passe | moyen |
| I5 | Sous-options de configuration par passe | lisibilité (`dot-shorthands` sans `.new`) | moyen |
| I6 | Correctifs de lints choisis appliqués via `dart fix` | nouvelles réécritures sans écrire de passe | faible à moyen |
| I7 | Campagne sur projets réels en CI | non-régression sur du vrai code | moyen |

### I1. Annulation par passe

Aujourd'hui un seul défaut annule **tout** le fichier : sur `1618-mobile-app`, les
dot shorthands, expression bodies et autres éditions correctes de 14 fichiers
sont perdues à cause de `primary-constructors`. `passesByFile` sait quelles passes
ont touché le fichier. En cas d'échec, rejouer ce fichier sans la dernière passe
suspecte (ou par dichotomie sur les passes), revérifier, et ne garder l'annulation
complète qu'en dernier recours. Le rapport indique alors la passe désactivée pour
ce fichier.

### I2. `--upgrade-sdk`

`1618-mobile-app` (`sdk: ^3.7.0`) est refusé d'emblée, avec un message clair mais
sans issue. L'option ferait, avant tout le reste :

1. passer la borne basse de la contrainte SDK à `^3.13.0` dans `pubspec.yaml` ;
2. `dart pub get` ;
3. `dart fix --apply --code=extraneous_modifier` pour retirer les `final` et `var`
   devenus illégaux (section 3.5) ;
4. continuer le run normalement.

Elle exige un arbre Git propre, comme le reste, pour que l'utilisateur puisse
tout annuler.

### I3. Nouveaux avertissements et infos

`_analyzeErrors` (`pipeline.dart:147`) ne garde que la sévérité `ERROR`. Garder
aussi `WARNING` et `INFO`, et lister ceux qui apparaissent (sans annuler) : un
projet qui tourne avec `--fatal-infos` saura avant de pousser que sa CI va
échouer. Sur `smooth-app`, cela aurait montré les 26 infos de B18.

### I4. Vérification à chaque étape, en mémoire

Le pipeline résout déjà tout le projet au début de chaque étape
(`applyStagedChanges` puis `resolvedUnits`). Il suffit de comparer, pour chaque
fichier, les erreurs avant et après l'étape précédente : si une étape en a
ajouté, on retire les éditions de la passe en cause pour ce fichier (on sait
laquelle grâce à `passesByFile`) et on recalcule, sans rien avoir écrit sur le
disque. Les fichiers non modifiés sont résolus aussi, donc les erreurs chez les
appelants (B7) sont vues. Cela aurait rattrapé B1, B3 à B6, B14 à B16, B20 et
B22 à B25 avant l'écriture, et réduit `--verify` à un dernier filet pour `dart fix`
et le formatage (B17, B21). C'est la meilleure protection structurelle, à faire après les
corrections ponctuelles.

### I5. Sous-options de configuration

La section `dart_modernize:` de `analysis_options.yaml` ne connaît que `enabled`,
`disabled` et `exclude` (`lib/src/cli/config.dart`). Pour régler une passe sans
la couper entièrement :

```yaml
dart_modernize:
  options:
    dot-shorthands:
      constructors: false   # garde InputDecoration(...), raccourcit .center, .zero
    primary-constructors:
      super-parameters: true
```

Cela éviterait de multiplier les noms de passes (comme
`primary-constructors-super` en P3).

### I6. Correctifs de lints choisis, appliqués par `dart fix`

Alternative ou complément aux passes : pendant l'étape `fix-all`, ajouter
temporairement à l'`analysis_options.yaml` du projet une liste de lints dont les
correctifs sont sûrs (`unnecessary_type_name_in_constructor`,
`empty_container_bodies`, `unnecessary_underscores`,
`prefer_null_aware_method_calls`...), lancer `dart fix --apply`, puis restaurer le
fichier. Avantage : correctifs écrits et maintenus par l'équipe Dart. Limites :
invisible dans `--dry-run`, pas de sélection fine, et `dart fix` corrige aussi les
lints que le projet active déjà. À garder comme repli si une passe s'avère trop
coûteuse.

### I7. Campagne sur projets réels en CI

Un workflow GitHub Actions hebdomadaire (et déclenchable à la main) qui rejoue la
campagne de la section 4 sur quelques projets publics figés sur un commit
(`flutter_todos` de bloc, `saber`, `flex_color_scheme`...). Il échoue si un
fichier est annulé, si une nouvelle erreur apparaît, si un test du projet passe
au rouge, ou si le second run modifie quelque chose. C'est le seul filet qui
aurait attrapé B1 à B6 avant publication. Le script de l'annexe 10.1 sert de
base.

## 8. Dépendances et merges

### 8.1 PR Dependabot ouverte

| PR | Contenu | État |
|:--|:--|:--|
| [#45](https://github.com/isyll/dart_modernize/pull/45) | `analyzer` 14.3.0 vers 14.4.0 (et `_fe_analyzer_shared` 107.0.0 vers 108.0.0) | ouverte le 2026-10-06, CI verte (`test`, `gitleaks`), fusionnable sans conflit |

La PR ne modifie que `pubspec.lock`. La contrainte de `pubspec.yaml` reste
`analyzer: ^14.0.0`.

### 8.2 Ce qui est déjà plus récent

`dart pub outdated` sur `main` :

| Paquet | Verrouillé | Dernière |
|:--|:--|:--|
| `analyzer` | 14.3.0 | 14.5.0 |
| `_fe_analyzer_shared` (transitif) | 107.0.0 | 109.0.0 |
| `frontend_server_client` (dev, transitif) | 4.0.0 | 4.1.0 |
| `io` (dev, transitif) | 1.0.5 | 1.1.0 |
| `mime` (dev, transitif) | 2.0.0 | 2.1.0 |
| `pool` (dev, transitif) | 1.5.2 | 1.5.3 |
| `source_maps` (dev, transitif) | 0.10.13 | 0.10.14 |
| `stack_trace` (dev, transitif) | 1.12.1 | 1.12.2 |
| `vm_service` (dev, transitif) | 15.2.0 | 15.3.0 |

### 8.3 Plan

1. Merger #45 tel quel, en commit de merge comme les PR précédentes (« Merge pull
   request #45 »). La CI est verte et le changement ne touche que le lockfile.
2. Sur la branche de la version : `dart pub upgrade` (analyzer 14.5.0 et les
   transitifs ci-dessus), puis relever la contrainte à `analyzer: ^14.5.0`. Raison :
   P1 a besoin de `ConstructorDeclaration.typeName2`, absent d'analyzer 14.0 et
   14.1 ; une contrainte `^14.0.0` laisserait un utilisateur résoudre une version
   où le code ne compile pas.
3. `dart test` complet, puis rejouer la campagne : elle a été faite avec
   analyzer 14.3.0.
4. Dependabot ouvrira ensuite sa PR suivante d'elle-même, ou la fermera si le
   lockfile est déjà à jour.

## 9. Prochaine version : 0.12.0

### 9.1 Pourquoi 0.12.0 et pas 1.0.0

La campagne sur de vrais projets est justement ce qui montre que l'outil n'est pas
prêt pour un 1.0.0 :

- **Sur les projets testés, il casse du code ou en change le comportement sans
  le signaler** (B1, B2, B7). Un 1.0.0 dit l'inverse : « vous pouvez le lancer
  sur votre projet ».
- **Un 1.0.0 fige l'interface.** En semver, toute rupture ensuite impose 2.0.0.
  Or plusieurs corrections prévues changent justement l'interface : code de
  sortie distinct pour un succès partiel (B9), comportement de `--check` (B12),
  sous-options de configuration (I5), nouvelles passes actives par défaut qui
  changent la sortie. Mieux vaut les faire en 0.x.
- **Les nouvelles passes n'ont encore tourné sur aucun projet réel.**
- Sur pub.dev, `^0.12.0` n'accepte que `<0.13.0` : chaque version 0.x reste un
  choix explicite pour qui l'épingle. C'est adapté tant que la sortie de l'outil
  bouge beaucoup.

**Critères proposés pour 1.0.0**, mesurés avec la campagne de la section 4 (et I7
en CI) sur au moins dix projets réels, dont les quatre projets personnels :

1. zéro fichier annulé par `--verify` avec la configuration par défaut ;
2. zéro nouvelle erreur d'analyse dans tout le projet, fichiers non modifiés
   compris (B7 corrigé) ;
3. tests des projets identiques avant et après ;
4. second run vide (idempotence) ;
5. durée raisonnable : par exemple moins de 2 minutes pour 150 fichiers sur une
   machine de développement (B10) ;
6. interface stable depuis au moins une version : options, configuration, codes
   de sortie documentés.

Un chemin réaliste : 0.12.0 (corrections et passes 3.13), 0.13.0 (performance,
annulation par passe, campagne en CI), puis 1.0.0 quand les critères tiennent sur
deux versions de suite.

### 9.2 Contenu proposé

| Niveau | Éléments |
|:--|:--|
| Indispensable | merge #45 et `dart pub upgrade` (8.3) ; B14 ; B1 à B6, B15, B16, B20, B22 à B25 ; contournement de B17 ; B7 ; B9 ; B21 points 1 et 2 (formater seulement les fichiers modifiés, `--no-format`) ; B19 : capturer le débordement de pile fichier par fichier ; documentation de B12 ; P1, P2, P3.a et P3.b |
| Souhaitable | B8 ; B13 ; B18 ; pistes 1, 2 et 5 de B10 ; I1 ; I2 ; I3 ; vraie correction de B12 en mode `--check` ; B21 point 3 ; P4, P5 |
| Possible | I4 ; P6 ; P3.c à P3.e ; I5 ; I7 |
| Plus tard | binaire AOT (B11 et suite de B19) ; P7 ; P3.f à P3.h ; I6 ; pistes 3 et 4 de B10 |

### 9.3 Ordre de travail

Chaque étape est un commit (ou une PR) qui laisse `dart format`,
`dart analyze --fatal-infos` et `dart test` au vert, avec des messages de commit
simples, sans préfixe ni ligne de fin (règles d'`AGENTS.md`).

1. Merger #45, puis `dart pub upgrade` et `analyzer: ^14.5.0`.
2. B14 en premier : une garde de version de langage dans le pipeline, simple et
   qui protège toutes les passes.
3. Pour chaque bug de passe, d'abord un test qui échoue (golden ou test CLI),
   puis la correction : B1, B2, B23, B3, B4, B5, B6, B20, B15, B16, B22, B24,
   B25, puis le contournement de B17.
4. Pipeline : B7, B9, B21 (portée du formatage et `--no-format`), capture du
   débordement de pile (B19), B8.
5. Rejouer la campagne : plus aucun fichier annulé ne doit venir des passes
   existantes, et aucun crash.
6. P1, puis P2, puis P3 (3.a et 3.b sont déjà faits à l'étape 3), puis P4 et P5.
7. Mettre à jour `doc/ORDERING.md` (tableau des étapes ci-dessous), `README.md`
   (dont `--no-format` et la portée réelle de `--check`),
   `test/fixtures/README.md`.
8. Rejouer la campagne complète, comparer avec la section 4.2.
9. Publier (9.5).

Tableau des étapes après 0.12.0 (les ajouts sont en gras) :

| Étape | Passes |
|:--|:--|
| 1 | `collection-elements` |
| 2 | `switch-expressions`, `cascades`, `super-parameters`, `private-named-parameters` |
| 3 | `primary-constructors` |
| 4 | `inline-return`, `prefer-inferred-types`, **`future-pause`**, **`null-aware-calls`** |
| 5 | `expression-bodies`, `final-locals` |
| 6 | `null-aware-conditionals` |
| 7 | `destructure-for-in`, `destructure-locals` |
| 8 | `dot-shorthands`, `string-interpolation`, `null-aware-spread`, `null-aware-elements`, `abstract-final-classes`, **`constructor-shorthands`**, **`empty-bodies`**, **`wildcard-parameters`** |

### 9.4 Validation avant publication

- Suite complète : `dart test`, dont `pass_convergence_test.dart`,
  `idempotence_test.dart`, `full_pipeline_idempotence_test.dart` et le test
  sémantique avec les nouvelles passes.
- Campagne de la section 4 sur les mêmes projets. Objectifs : zéro fichier annulé,
  zéro nouvelle erreur, tests identiques, second run vide.
- Lancer l'outil sur ses propres sources, comme pour 0.11.0.

### 9.5 Publication

Deux voies, décrites dans `AGENTS.md` :

- **Automatique (recommandée)** : créer la milestone `0.12.0` sur GitHub, une
  issue par élément retenu en 9.2 (B1 à B9, P1, P2...), les fermer au fil des PR.
  À la fermeture de la dernière, `milestone-release.yml` écrit la section
  `## 0.12.0` du `CHANGELOG.md` à partir des issues, met la version à jour aux
  trois endroits, commite sur `main` et pousse le tag `v0.12.0` ; `release.yml`
  relance les tests sur le tag et publie sur pub.dev. Il faut le secret
  `RELEASE_PAT`. 0.12.0 est bien la prochaine version attendue par le workflow
  (au-dessus de 0.11.1, aucune milestone plus basse ouverte).
- **Manuelle** : mettre `0.12.0` dans `pubspec.yaml`, dans `_version` de
  `lib/src/runner.dart` et en tête de `CHANGELOG.md`
  (`test/cli/version_sync_test.dart` vérifie qu'ils concordent), commiter,
  pousser `main`, puis pousser le tag `v0.12.0`.

Ébauche de `CHANGELOG` :

```markdown
## 0.12.0

- New `constructor-shorthands` pass: `Point(...)` becomes `new(...)`, `Point.origin()` becomes `new origin()`, `factory Point.fromJson` becomes `factory fromJson`, and enum constructors drop their redundant `const` (Dart 3.13).
- New `empty-bodies` pass: an empty class, mixin or extension type body `{}` becomes `;` (Dart 3.13).
- New `future-pause` and `wildcard-parameters` passes.
- Fixed `primary-constructors` dropping default values and the brackets of optional positional parameters.
- Fixed `primary-constructors` deleting a constructor's doc comment, annotations and comments.
- Fixed `prefer-inferred-types` emitting `<T>const [...]`, and turning `double x = -1` into an `int`.
- Fixed `final-locals` missing pattern assignments and `for (x in ...)` loops.
- Fixed `destructure-for-in` and `destructure-locals` writing a type name the file does not import, and destructuring a nullable value.
- Fixed `super-parameters` folding a named parameter into a positional argument (and the reverse), and dropping a call to a named super constructor.
- Fixed `dot-shorthands` shortening a record field returned from an `async` function, or an element of a collection passed to a generic call such as `ISetConst({...})`, where Dart gives no context type.
- Fixed `prefer-inferred-types` dropping the type of a field that overrides an inherited member, which changed the field's type.
- Fixed `null-aware-conditionals` breaking a member chain written over several lines.
- Fixed `inline-return` moving a generic call into a `return` whose context changed its inferred type.
- `primary-constructors` no longer promotes an `@immutable` class that keeps a field initialized in its body, which made `dart fix` add an invalid `const`.
- Every pass now skips a library whose language version is older than 3.13 (a `// @dart = 2.x` comment).
- `--verify` now checks the whole project, not only the changed files.
- A run that reverts some files now reports what it applied and exits with a distinct code.
- `dart format` now only touches the files the tool changed, and `--no-format` turns it off.
- A file too deeply nested for the analyzer is skipped with a warning instead of crashing the run.
- Updated `analyzer` to 14.5.0.
```

## 10. Annexes

### 10.1 Script de la campagne

Python 3, lancé depuis un dossier court (voir 10.2) contenant `dm.dill`, l'outil
compilé avec `dart compile kernel bin/dart_modernize.dart -o dm.dill`.

```
python campaign.py bedrock --local C:/Users/isyll/my_projects/bedrock --tests
python campaign.py bloc --git https://github.com/felangel/bloc.git --sub examples/flutter_todos
python campaign.py devtools --git https://github.com/flutter/devtools.git --sub packages/devtools_app --root-get --no-run2
python campaign.py lichess --git https://github.com/lichess-org/mobile.git --codegen --no-run2
```

```python
"""Run dart_modernize over a copy of a real project and record what breaks.

usage: python campaign.py NAME (--local DIR | --git URL) [--sub SUBDIR]
                          [--root-get] [--codegen] [--tests] [--no-run2]

Never touches the source project: a local one is copied, a remote one cloned.
Reports land in _reports/NAME/.
"""

import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DM = os.path.join(HERE, 'dm.dill')
IGNORE = {'build', '.dart_tool', '.git', 'Pods', '.symlinks', 'ephemeral',
          '.idea', '.gradle', 'node_modules'}


def run(cmd, cwd, log=None, timeout=3600):
    t0 = time.time()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace', shell=True,
                       timeout=timeout)
    dt = time.time() - t0
    if log:
        with open(log, 'w', encoding='utf-8') as f:
            f.write(f'$ {cmd}\n# exit {p.returncode} in {dt:.0f}s\n')
            f.write(p.stdout)
            f.write('\n--- stderr ---\n')
            f.write(p.stderr)
    return p.returncode, p.stdout + p.stderr, dt


def analyze(proj, log):
    _, out, _ = run('dart analyze --format=machine --no-fatal-warnings .',
                    proj, log)
    diags = []
    for line in out.splitlines():
        parts = line.split('|')
        if len(parts) >= 8 and parts[0] in ('ERROR', 'WARNING', 'INFO'):
            path = os.path.relpath(parts[3], proj).replace('\\', '/')
            diags.append({'sev': parts[0], 'code': parts[2], 'file': path,
                          'line': int(parts[4]), 'msg': '|'.join(parts[7:])})
    return diags


def bump_sdk(pubspec):
    text = open(pubspec, encoding='utf-8').read()
    m = re.search(r'^environment:\s*\n((?:[ \t]+.*\n?)*)', text, re.M)
    if not m:
        return None
    block = m.group(1)
    sm = re.search(r'^([ \t]+sdk:\s*)(.+)$', block, re.M)
    if not sm:
        return None
    old = sm.group(2).strip()
    lm = re.search(r'3\.(\d+)', old)
    if lm and int(lm.group(1)) >= 13:
        return None
    new_block = block[:sm.start()] + sm.group(1) + '^3.13.0' + block[sm.end():]
    text = text[:m.start(1)] + new_block + text[m.end(1):]
    open(pubspec, 'w', encoding='utf-8').write(text)
    return old


def git(cmd, cwd):
    return run('git -c core.longpaths=true -c core.autocrlf=false '
               f'-c core.safecrlf=false {cmd}', cwd)


def summarize(diags):
    return dict(collections.Counter(f"{d['sev']} {d['code']}" for d in diags))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('name')
    ap.add_argument('--local')
    ap.add_argument('--git')
    ap.add_argument('--sub', default='')
    ap.add_argument('--root-get', action='store_true')
    ap.add_argument('--codegen', action='store_true')
    ap.add_argument('--tests', action='store_true')
    ap.add_argument('--no-run2', action='store_true')
    a = ap.parse_args()

    work = os.path.join(HERE, 'work', a.name)
    rep = os.path.join(HERE, '_reports', a.name)
    os.makedirs(rep, exist_ok=True)
    report = {'name': a.name, 'source': a.local or a.git, 'sub': a.sub}

    if not os.path.exists(work):
        if a.local:
            shutil.copytree(a.local, work,
                            ignore=lambda d, names: [n for n in names if n in IGNORE])
            git('init -q', work)
        else:
            code, _, _ = run(f'git -c core.longpaths=true clone -q --depth 1 '
                             f'{a.git} "{work}"', HERE,
                             os.path.join(rep, '00_clone.log'))
            if code != 0:
                report['fatal'] = 'clone failed'
                json.dump(report, open(os.path.join(rep, 'report.json'), 'w'), indent=2)
                return
    proj = os.path.join(work, a.sub) if a.sub else work
    report['bumped_sdk_from'] = bump_sdk(os.path.join(proj, 'pubspec.yaml'))

    pub = open(os.path.join(proj, 'pubspec.yaml'), encoding='utf-8').read()
    flutter = re.search(r'sdk:\s*flutter', pub) is not None
    tool = 'flutter' if flutter else 'dart'
    code, _, _ = run(f'{tool} pub get', work if a.root_get else proj,
                     os.path.join(rep, '01_pub_get.log'))
    report['pub_get'] = code
    if code != 0:
        report['fatal'] = 'pub get failed'
        json.dump(report, open(os.path.join(rep, 'report.json'), 'w'), indent=2)
        return
    if a.codegen:
        code, _, dt = run('dart run build_runner build -d', proj,
                          os.path.join(rep, '02_codegen.log'))
        report['codegen'] = [code, round(dt)]

    git('add -A', work)
    git('commit -q --no-verify -m baseline --allow-empty', work)

    base = analyze(proj, os.path.join(rep, '03_analyze_before.log'))
    report['before'] = summarize(base)

    has_tests = a.tests and os.path.isdir(os.path.join(proj, 'test'))
    if has_tests:
        code, out, dt = run(f'{tool} test --reporter=compact', proj,
                            os.path.join(rep, '04_tests_before.log'))
        report['tests_before'] = [code, out.strip().splitlines()[-1:], round(dt)]

    code, _, dt = run(f'dart "{DM}" --no-color --verbose .', proj,
                      os.path.join(rep, '05_run1.log'))
    report['run1'] = {'exit': code, 'seconds': round(dt)}
    _, stat, _ = git('diff --shortstat --ignore-cr-at-eol', work)
    report['run1']['diff'] = stat.strip()
    git('diff --ignore-cr-at-eol > "' + os.path.join(rep, '05_run1.diff') + '"', work)

    after = analyze(proj, os.path.join(rep, '06_analyze_after.log'))
    report['after'] = summarize(after)
    before_keys = collections.Counter((d['sev'], d['code'], d['file']) for d in base)
    after_keys = collections.Counter((d['sev'], d['code'], d['file']) for d in after)
    new = after_keys - before_keys
    gone = before_keys - after_keys
    new_detail = [d for d in after if (d['sev'], d['code'], d['file']) in new]
    report['new_diagnostics'] = summarize(new_detail)
    report['fixed_diagnostics'] = dict(collections.Counter(
        f'{k[0]} {k[1]}' for k in gone.elements()))
    json.dump(new_detail, open(os.path.join(rep, 'new_diagnostics.json'), 'w'), indent=1)

    if has_tests:
        code, out, dt = run(f'{tool} test --reporter=compact', proj,
                            os.path.join(rep, '07_tests_after.log'))
        report['tests_after'] = [code, out.strip().splitlines()[-1:], round(dt)]

    git('add -A', work)
    git('commit -q --no-verify -m run1 --allow-empty', work)
    if not a.no_run2:
        code, _, dt = run(f'dart "{DM}" --no-color --verbose .', proj,
                          os.path.join(rep, '08_run2.log'))
        _, stat, _ = git('diff --shortstat --ignore-cr-at-eol', work)
        report['run2'] = {'exit': code, 'seconds': round(dt), 'diff': stat.strip()}
        git('diff --ignore-cr-at-eol > "' + os.path.join(rep, '08_run2.diff') + '"', work)
        git('add -A', work)
        git('commit -q --no-verify -m run2 --allow-empty', work)

    json.dump(report, open(os.path.join(rep, 'report.json'), 'w'), indent=2)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
```

### 10.2 Pièges rencontrés pendant la campagne (Windows)

- **Chemins trop longs.** Cloner sous le dossier temporaire de l'utilisateur
  dépasse la limite de 260 caractères de Windows (`Filename too long` sur
  `flex_color_scheme`, `thunder`, `lichess`, `bloc`, `smooth-app`). Solution :
  un dossier court (`C:\dmc`) et `git -c core.longpaths=true`.
- **Exécutable compilé.** `dart compile exe` ne fonctionne pas (B11) : utiliser
  `dart compile kernel` et lancer `dart dm.dill`.
- **Fins de ligne.** Avec `core.autocrlf=true`, un clone a des fichiers CRLF sur
  le disque mais LF dans Git : `git diff` montre alors des fichiers entiers
  modifiés. Comparer avec `--ignore-cr-at-eol`. L'outil, lui, conserve bien les
  fins de ligne.
- **Mémoire.** Trois projets Flutter en parallèle (outil, `dart analyze` et
  `flutter test` en même temps) saturent 16 Go et provoquent le crash de B8. Deux
  à la fois passent.
- **Versions figées.** `lichess` (Flutter 3.47.5), `immich` (3.47.2) et
  `smooth-app` (`intl: 0.20.2`) exigent une version exacte : contrainte assouplie
  dans la copie pour pouvoir lancer `pub get`.
- **Code généré.** `lichess` et `immich` ne commitent pas leurs fichiers générés :
  `build_runner` avant l'analyse.

### 10.3 Sources

- [Announcing Dart 3.13](https://dart.dev/blog/announcing-dart-3-13)
- [CHANGELOG du SDK Dart](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md), sections 3.12.0 et 3.13.0
- [Spécification des constructeurs primaires](https://github.com/dart-lang/language/blob/main/accepted/3.13/primary-constructors/feature-specification.md)
- Lints : [`unnecessary_type_name_in_constructor`](https://dart.dev/tools/linter-rules/unnecessary_type_name_in_constructor),
  [`empty_container_bodies`](https://dart.dev/tools/linter-rules/empty_container_bodies),
  [`use_declaring_parameters`](https://dart.dev/tools/linter-rules/use_declaring_parameters),
  [`initialize_in_field_declaration`](https://dart.dev/tools/linter-rules/initialize_in_field_declaration),
  [`unnecessary_primary_constructor_body`](https://dart.dev/tools/linter-rules/unnecessary_primary_constructor_body),
  [`unnecessary_const_in_enum_constructor`](https://dart.dev/tools/linter-rules/unnecessary_const_in_enum_constructor)
- Code source de `analyzer` 14.0.0 à 14.4.0 (cache pub local) pour `typeName2`,
  `newKeyword`, `defaultClause`, `PrimaryConstructorBody`, `EmptyClassBody`
- SDK Dart 3.13.5 : `lib/async/future.dart` (`Future.pause`), `lib/core/list.dart`
  (`List.unmodifiableOf`)
