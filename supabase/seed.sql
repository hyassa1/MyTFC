-- =============================================================================
-- MonTFC — Données de démonstration
-- -----------------------------------------------------------------------------
-- 3 chapitres de guide, 3 modèles de page de garde (UNIKIN, UPN, générique),
-- 1 modèle de mémoire de licence, les établissements, les offres et un code
-- promo d'ambassadeur de démonstration.
--
-- ATTENTION : les prix et le libellé exact des pages de garde sont des
-- exemples. Faites valider chaque modèle auprès de l'établissement concerné
-- (intitulés officiels, ordre des mentions) avant la mise en production.
--
-- Règle éditoriale : aucun texte de TFC ou de mémoire déjà rédigé. Les modèles
-- ne contiennent que la structure, des consignes et des champs à remplir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Établissements
-- -----------------------------------------------------------------------------
insert into public.institutions (id, code, name, position) values
  ('00000000-0000-4000-8000-000000000101', 'UNIKIN',    'Université de Kinshasa', 1),
  ('00000000-0000-4000-8000-000000000102', 'UPN',       'Université pédagogique nationale', 2),
  ('00000000-0000-4000-8000-000000000103', 'ISTA',      'Institut supérieur de techniques appliquées', 3),
  ('00000000-0000-4000-8000-000000000104', 'ISS',       'Institut supérieur de statistique de Kinshasa', 4),
  ('00000000-0000-4000-8000-000000000105', 'UPC',       'Université protestante au Congo', 5),
  ('00000000-0000-4000-8000-000000000106', 'UCC',       'Université catholique du Congo', 6),
  ('00000000-0000-4000-8000-000000000107', 'ULK',       'Université libre de Kinshasa', 7),
  ('00000000-0000-4000-8000-000000000108', 'ISP_GOMBE', 'Institut supérieur pédagogique de la Gombe', 8),
  ('00000000-0000-4000-8000-000000000199', 'AUTRE',     'Autre établissement', 99);

-- -----------------------------------------------------------------------------
-- Paramètres de l'application
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value) values
  -- Canaux de paiement affichés selon la variante et la plateforme (voir
  -- ARCHITECTURE.md §2). Modifiable sans republier l'application.
  ('payment_channels', '{
     "store":  {"android": ["google_play"], "ios": ["app_store"]},
     "direct": {"android": ["mobile_money"]},
     "web":    {"web": ["mobile_money"]}
   }'::jsonb),
  ('mobile_money_operators', '[
     {"code": "vodacom", "label": "M-Pesa (Vodacom)", "prefixes": ["81", "82", "83"]},
     {"code": "orange",  "label": "Orange Money",     "prefixes": ["84", "85", "89"]},
     {"code": "airtel",  "label": "Airtel Money",     "prefixes": ["97", "98", "99"]}
   ]'::jsonb),
  ('min_app_version', '"1.0.0"'::jsonb),
  ('support_whatsapp', '"+243000000000"'::jsonb);

-- -----------------------------------------------------------------------------
-- Guide de méthodologie (3 chapitres de démonstration)
-- -----------------------------------------------------------------------------
insert into public.guide_chapters (id, slug, position, title, summary, body_md, is_published) values
(
  '00000000-0000-4000-8000-000000000201', 'choix-du-sujet', 1,
  'Choisir son sujet',
  'Les critères d''un bon sujet et la démarche pour le faire valider.',
$md$
# Choisir son sujet

Le sujet est la porte d'entrée de tout ton travail. Un sujet mal choisi te fera perdre des semaines ; un sujet bien délimité rend la recherche, la rédaction et la soutenance beaucoup plus simples.

## 1. Les quatre critères d'un bon sujet

1. **L'intérêt personnel** : tu vas vivre plusieurs mois avec ce sujet. Choisis un domaine qui te motive vraiment.
2. **La faisabilité** : as-tu accès aux données, au terrain, aux personnes à interroger ? Une entreprise qui refuse de te recevoir peut bloquer tout ton travail.
3. **La pertinence** : le sujet doit répondre à un vrai problème, dans ta discipline, et apporter quelque chose (même modeste) à la connaissance ou à la pratique.
4. **La délimitation** : un bon sujet précise **quoi**, **où** et **quand**. Un sujet trop large est le défaut le plus fréquent.

## 2. Délimiter dans l'espace et dans le temps

Un sujet se délimite sur trois axes :

| Axe | Question à se poser | Exemple de précision |
|---|---|---|
| Thématique | Quel aspect précis du phénomène ? | la gestion des stocks, et non « la gestion » |
| Spatial | Où ? | une commune, une entreprise, un service |
| Temporel | Sur quelle période ? | de telle année à telle année |

> **Astuce** : écris ton sujet, puis demande-toi pour chaque mot « lequel ? », « où ? », « depuis quand ? ». Si tu ne sais pas répondre, le sujet n'est pas encore assez précis.

## 3. La démarche pratique

1. **Liste trois à cinq idées** liées à tes cours, à ton stage ou à ton milieu.
2. **Lis un peu sur chacune** (deux ou trois travaux antérieurs à la bibliothèque de ta faculté) pour voir ce qui a déjà été fait.
3. **Vérifie l'accès au terrain** avant de t'engager : un appel ou une visite suffit souvent.
4. **Formule une première version** du sujet en une phrase.
5. **Présente-la à ton directeur ou encadreur** avec une courte note : ce que tu veux étudier, pourquoi, et comment tu comptes t'y prendre.

## 4. Les erreurs à éviter

- Reprendre un sujet déjà traité sans angle nouveau.
- Choisir un sujet pour lequel aucune donnée n'est accessible.
- Formuler le sujet comme une opinion (« l'importance de… », « la nécessité de… ») plutôt que comme un objet d'étude.
- Changer de sujet en cours de route sans l'accord de ton directeur.

## À retenir

Un bon sujet est **motivant, faisable, pertinent et précis**. Prends le temps de le délimiter : chaque heure passée ici t'en fera gagner dix plus tard.
$md$,
  true
),
(
  '00000000-0000-4000-8000-000000000202', 'problematique', 2,
  'Formuler la problématique',
  'Passer d''un constat à une question de recherche claire.',
$md$
# Formuler la problématique

La problématique explique **pourquoi** ton sujet pose question. Elle part d'un constat, montre ce qui fait problème, et aboutit à une ou plusieurs **questions de recherche**.

## 1. La structure en entonnoir

Une bonne problématique va du général au particulier :

1. **Le contexte** : situe le phénomène étudié (quelques phrases, avec des sources).
2. **Le constat** : ce que tu as observé ou lu, idéalement chiffré et daté.
3. **L'écart** : la différence entre ce qui devrait être (la norme, l'objectif, la théorie) et ce qui est réellement observé.
4. **La question principale** : la question à laquelle ton travail va répondre.
5. **Les questions spécifiques** (facultatif) : deux ou trois sous-questions qui découpent la question principale.

## 2. Les qualités d'une bonne question de recherche

- **Claire** : une seule idée, sans mots vagues.
- **Précise** : elle reprend la délimitation du sujet (lieu, période, population).
- **Vérifiable** : on peut y répondre avec des données ou des sources.
- **Neutre** : elle ne contient pas déjà la réponse.

> **Test rapide** : si ta question peut se répondre par « oui » ou « non » sans aucune recherche, reformule-la. Les questions qui commencent par « Dans quelle mesure… », « Comment… », « Quels sont les facteurs qui… » fonctionnent bien.

## 3. Méthode pour rédiger ta problématique

- Commence par écrire **ton constat en trois phrases**, sans chercher à bien écrire.
- Cherche **deux ou trois sources** qui confirment ou éclairent ce constat (rapports, statistiques, travaux antérieurs).
- Identifie **l'écart** : qu'est-ce qui ne va pas, ou qu'est-ce qu'on ignore encore ?
- Écris **ta question principale**, puis vérifie qu'elle respecte les quatre qualités ci-dessus.
- Fais relire par ton encadreur avant de passer aux hypothèses.

## 4. Les erreurs fréquentes

- Une problématique qui raconte l'histoire du sujet sans jamais poser de question.
- Des questions trop nombreuses (plus de trois ou quatre questions spécifiques).
- Une question principale sans lien avec le titre du travail.
- Des affirmations non sourcées dans le constat.

## À retenir

Constat → écart → question. Ta question principale est la boussole de tout ton travail : les hypothèses, les objectifs, la méthode et la conclusion doivent tous s'y rapporter.
$md$,
  true
),
(
  '00000000-0000-4000-8000-000000000203', 'hypotheses-objectifs', 3,
  'Hypothèses et objectifs',
  'Proposer des réponses provisoires et fixer ce que le travail doit atteindre.',
$md$
# Hypothèses et objectifs

Une fois ta question de recherche posée, tu proposes des **réponses provisoires** (les hypothèses) et tu fixes **ce que ton travail doit accomplir** (les objectifs).

## 1. Les hypothèses

Une hypothèse est une **réponse anticipée** à ta question de recherche, que ton travail va confirmer ou infirmer.

**Ses qualités :**

- Elle répond directement à une question de recherche (une hypothèse par question spécifique, en général).
- Elle met en relation **au moins deux éléments** (une cause et un effet, un facteur et un résultat).
- Elle est **vérifiable** avec les données que tu vas recueillir.
- Elle est formulée au **présent de l'indicatif**, de façon affirmative.

**Structure type :** « [tel facteur] influence / explique / est lié à [tel phénomène] dans [tel contexte] ».

> **Important** : une hypothèse infirmée n'est pas un échec. Ce qui compte, c'est que ta démarche de vérification soit rigoureuse et honnête.

## 2. Les objectifs

### Objectif général

Il reprend la question principale sous forme d'action : **ce que le travail veut atteindre**. Il commence par un verbe à l'infinitif : *analyser*, *évaluer*, *déterminer*, *identifier*, *comparer*…

### Objectifs spécifiques

Ce sont les **étapes concrètes** pour atteindre l'objectif général. En général deux à quatre, chacun mesurable et lié à une hypothèse ou à une partie du plan.

| Niveau | Verbes conseillés | Verbes à éviter |
|---|---|---|
| Général | analyser, évaluer, déterminer | comprendre, connaître (trop vagues) |
| Spécifique | identifier, mesurer, décrire, comparer, proposer | améliorer, résoudre (hors de portée d'un travail académique) |

## 3. Vérifier la cohérence

Prépare un petit tableau de cohérence et garde-le sous les yeux pendant toute la rédaction :

| Question | Hypothèse | Objectif spécifique | Partie du plan | Outil de collecte |
|---|---|---|---|---|
| Q1 | H1 | OS1 | Chapitre … | questionnaire, entretien, documents… |
| Q2 | H2 | OS2 | Chapitre … | … |

Chaque ligne doit être complète. Une hypothèse sans outil de vérification, ou un chapitre sans lien avec un objectif, est le signe d'un problème à corriger.

## À retenir

Les hypothèses répondent aux questions ; les objectifs disent ce que tu vas faire pour vérifier ces réponses. Le tableau de cohérence est ton meilleur allié devant le jury.
$md$,
  true
);

-- -----------------------------------------------------------------------------
-- Modèles de page de garde
-- -----------------------------------------------------------------------------
-- Format de layout (version 1), interprété par l'application (aperçu, PDF, DOCX) :
--   page   : { size, margins_cm {top,bottom,left,right}, border: none|single|double }
--   font   : { family, size }
--   blocks : liste de blocs
--     text   : { text, align: left|center|right|justify, size, bold, italic,
--                space_before_pt, space_after_pt, indent_left_ratio (0-1), if }
--     spacer : { height_cm }
--     rule   : { thickness_pt }
--     box    : { border: single|double, padding_cm, blocks: [...] }
--   Les textes acceptent des champs {{cle}} et le filtre {{cle|upper}}.
--   « if » : le bloc n'est affiché que si le champ indiqué est rempli.
--
-- Format de fields_schema : liste de champs
--   { key, label, type: text|textarea|select|academic_year, required,
--     max_length, prefill (ex. "profile.full_name"), options, default, help }

-- Champs communs, réutilisés par les trois modèles.
create temporary table _cover_fields (fields jsonb);
insert into _cover_fields values ($json$[
  {"key": "student_name", "label": "Nom complet (nom, post-nom et prénom)", "type": "text",
   "required": true, "max_length": 120, "prefill": "profile.full_name"},
  {"key": "title", "label": "Sujet du travail", "type": "textarea", "required": true, "max_length": 400,
   "help": "Recopie exactement l'intitulé validé par ton directeur."},
  {"key": "faculty", "label": "Faculté", "type": "text", "required": true, "max_length": 120,
   "prefill": "profile.faculty"},
  {"key": "department", "label": "Département", "type": "text", "required": false, "max_length": 120,
   "prefill": "profile.department"},
  {"key": "grade", "label": "Type de travail", "type": "select", "required": true,
   "prefill": "profile.work_type",
   "options": [
     {"value": "tfc", "label": "Travail de fin de cycle présenté et défendu en vue de l'obtention du grade de gradué"},
     {"value": "memoire_licence", "label": "Mémoire présenté et défendu en vue de l'obtention du grade de licencié"},
     {"value": "memoire_master", "label": "Mémoire présenté et défendu en vue de l'obtention du diplôme de master"}
   ]},
  {"key": "discipline", "label": "Discipline ou option (ex. sciences commerciales)", "type": "text",
   "required": true, "max_length": 120},
  {"key": "director", "label": "Directeur (titre et nom, ex. Prof. …)", "type": "text",
   "required": true, "max_length": 120},
  {"key": "supervisor", "label": "Encadreur (titre et nom, ex. C.T. …)", "type": "text",
   "required": false, "max_length": 120},
  {"key": "academic_year", "label": "Année académique", "type": "academic_year", "required": true,
   "prefill": "profile.academic_year"}
]$json$::jsonb);

insert into public.cover_templates (id, code, institution_id, name, description, fields_schema, position, is_published)
select '00000000-0000-4000-8000-000000000301'::uuid, 'COVER_UNIKIN', '00000000-0000-4000-8000-000000000101'::uuid,
       'Université de Kinshasa (UNIKIN)', 'Page de garde au format courant de l''UNIKIN.', fields, 1, true
  from _cover_fields
union all
select '00000000-0000-4000-8000-000000000302'::uuid, 'COVER_UPN', '00000000-0000-4000-8000-000000000102'::uuid,
       'Université pédagogique nationale (UPN)', 'Page de garde au format courant de l''UPN.', fields, 2, true
  from _cover_fields
union all
select '00000000-0000-4000-8000-000000000303'::uuid, 'COVER_GENERIQUE', null::uuid,
       'Modèle générique', 'Pour tout établissement sans modèle spécifique.',
       jsonb_build_array(jsonb_build_object(
         'key', 'institution_name', 'label', 'Nom de l''établissement', 'type', 'text',
         'required', true, 'max_length', 150, 'prefill', 'profile.institution_name')) || fields,
       99, true
  from _cover_fields;

drop table _cover_fields;

insert into public.cover_template_bodies (template_id, layout) values
(
  '00000000-0000-4000-8000-000000000301',
  $json${
    "schema_version": 1,
    "page": {"size": "A4", "margins_cm": {"top": 2, "bottom": 2, "left": 2.5, "right": 2}, "border": "double"},
    "font": {"family": "Times New Roman", "size": 12},
    "blocks": [
      {"type": "text", "text": "UNIVERSITÉ DE KINSHASA", "align": "center", "size": 16, "bold": true},
      {"type": "text", "text": "FACULTÉ DE {{faculty|upper}}", "align": "center", "size": 13, "bold": true, "space_before_pt": 6},
      {"type": "text", "text": "DÉPARTEMENT DE {{department|upper}}", "align": "center", "size": 12, "bold": true, "if": "department"},
      {"type": "rule", "thickness_pt": 1},
      {"type": "spacer", "height_cm": 3},
      {"type": "box", "border": "single", "padding_cm": 0.4, "blocks": [
        {"type": "text", "text": "{{title|upper}}", "align": "center", "size": 14, "bold": true}
      ]},
      {"type": "spacer", "height_cm": 2},
      {"type": "text", "text": "Par", "align": "center", "italic": true},
      {"type": "text", "text": "{{student_name|upper}}", "align": "center", "size": 13, "bold": true, "space_before_pt": 4},
      {"type": "spacer", "height_cm": 2},
      {"type": "text", "text": "{{grade}} en {{discipline}}", "align": "justify", "indent_left_ratio": 0.45, "italic": true},
      {"type": "spacer", "height_cm": 1},
      {"type": "text", "text": "Directeur : {{director}}", "align": "left", "indent_left_ratio": 0.45, "bold": true},
      {"type": "text", "text": "Encadreur : {{supervisor}}", "align": "left", "indent_left_ratio": 0.45, "bold": true, "if": "supervisor"},
      {"type": "spacer", "height_cm": 3},
      {"type": "text", "text": "Année académique {{academic_year}}", "align": "center", "bold": true}
    ]
  }$json$::jsonb
),
(
  '00000000-0000-4000-8000-000000000302',
  $json${
    "schema_version": 1,
    "page": {"size": "A4", "margins_cm": {"top": 2, "bottom": 2, "left": 2.5, "right": 2}, "border": "single"},
    "font": {"family": "Times New Roman", "size": 12},
    "blocks": [
      {"type": "text", "text": "RÉPUBLIQUE DÉMOCRATIQUE DU CONGO", "align": "center", "size": 12, "bold": true},
      {"type": "text", "text": "ENSEIGNEMENT SUPÉRIEUR ET UNIVERSITAIRE", "align": "center", "size": 11},
      {"type": "text", "text": "UNIVERSITÉ PÉDAGOGIQUE NATIONALE", "align": "center", "size": 15, "bold": true, "space_before_pt": 8},
      {"type": "text", "text": "U.P.N.", "align": "center", "size": 12, "bold": true},
      {"type": "text", "text": "FACULTÉ DE {{faculty|upper}}", "align": "center", "size": 12, "bold": true, "space_before_pt": 8},
      {"type": "text", "text": "DÉPARTEMENT DE {{department|upper}}", "align": "center", "size": 12, "if": "department"},
      {"type": "spacer", "height_cm": 3},
      {"type": "rule", "thickness_pt": 1.5},
      {"type": "text", "text": "{{title|upper}}", "align": "center", "size": 14, "bold": true, "space_before_pt": 6, "space_after_pt": 6},
      {"type": "rule", "thickness_pt": 1.5},
      {"type": "spacer", "height_cm": 2},
      {"type": "text", "text": "{{student_name|upper}}", "align": "center", "size": 13, "bold": true},
      {"type": "spacer", "height_cm": 1.5},
      {"type": "text", "text": "{{grade}} en {{discipline}}", "align": "justify", "indent_left_ratio": 0.45},
      {"type": "spacer", "height_cm": 1},
      {"type": "text", "text": "Directeur : {{director}}", "align": "left", "indent_left_ratio": 0.45},
      {"type": "text", "text": "Encadreur : {{supervisor}}", "align": "left", "indent_left_ratio": 0.45, "if": "supervisor"},
      {"type": "spacer", "height_cm": 2.5},
      {"type": "text", "text": "Année académique {{academic_year}}", "align": "center", "bold": true}
    ]
  }$json$::jsonb
),
(
  '00000000-0000-4000-8000-000000000303',
  $json${
    "schema_version": 1,
    "page": {"size": "A4", "margins_cm": {"top": 2.5, "bottom": 2.5, "left": 3, "right": 2.5}, "border": "none"},
    "font": {"family": "Times New Roman", "size": 12},
    "blocks": [
      {"type": "text", "text": "{{institution_name|upper}}", "align": "center", "size": 15, "bold": true},
      {"type": "text", "text": "FACULTÉ DE {{faculty|upper}}", "align": "center", "size": 12, "bold": true, "space_before_pt": 6},
      {"type": "text", "text": "DÉPARTEMENT DE {{department|upper}}", "align": "center", "size": 12, "if": "department"},
      {"type": "spacer", "height_cm": 4},
      {"type": "text", "text": "{{title|upper}}", "align": "center", "size": 14, "bold": true},
      {"type": "spacer", "height_cm": 2.5},
      {"type": "text", "text": "Présenté par : {{student_name}}", "align": "center", "size": 12, "bold": true},
      {"type": "spacer", "height_cm": 2},
      {"type": "text", "text": "{{grade}} en {{discipline}}", "align": "justify", "indent_left_ratio": 0.4},
      {"type": "spacer", "height_cm": 1},
      {"type": "text", "text": "Directeur : {{director}}", "align": "left", "indent_left_ratio": 0.4},
      {"type": "text", "text": "Encadreur : {{supervisor}}", "align": "left", "indent_left_ratio": 0.4, "if": "supervisor"},
      {"type": "spacer", "height_cm": 3},
      {"type": "text", "text": "Année académique {{academic_year}}", "align": "center", "bold": true}
    ]
  }$json$::jsonb
);

-- -----------------------------------------------------------------------------
-- Modèle de document : mémoire de licence
-- -----------------------------------------------------------------------------
-- structure : liste de parties { id, title, kind: preliminary|body|annex,
--   heading_level (0 = hors numérotation), page_break_before, required,
--   guidance (consignes, jamais de texte rédigé), children }
-- formatting : normes de mise en forme appliquées à l'export DOCX/PDF.
insert into public.document_templates (id, code, work_type, title, description, position, is_published) values
  ('00000000-0000-4000-8000-000000000401', 'MEMOIRE_LICENCE_STANDARD', 'memoire_licence',
   'Mémoire de licence — plan classique',
   'Plan en trois ou quatre chapitres avec introduction et conclusion générales, aux normes courantes des facultés de Kinshasa.',
   1, true);

insert into public.document_template_bodies (template_id, structure, formatting) values
(
  '00000000-0000-4000-8000-000000000401',
  $json$[
    {"id": "epigraphe", "title": "Épigraphe", "kind": "preliminary", "heading_level": 0, "page_break_before": true, "required": false,
     "guidance": "Facultatif. Une courte citation en lien avec ton sujet, avec le nom de son auteur. Place-la en bas à droite de la page."},
    {"id": "dedicace", "title": "Dédicace", "kind": "preliminary", "heading_level": 0, "page_break_before": true, "required": false,
     "guidance": "Facultatif. Quelques lignes pour les personnes à qui tu dédies ton travail."},
    {"id": "remerciements", "title": "Remerciements", "kind": "preliminary", "heading_level": 0, "page_break_before": true, "required": true,
     "guidance": "Remercie d'abord ton directeur et ton encadreur, puis les autorités académiques, les personnes rencontrées sur le terrain, ta famille. Une page maximum."},
    {"id": "sigles", "title": "Liste des sigles et abréviations", "kind": "preliminary", "heading_level": 0, "page_break_before": true, "required": false,
     "guidance": "Par ordre alphabétique : le sigle, puis sa signification complète."},
    {"id": "tableaux", "title": "Liste des tableaux et figures", "kind": "preliminary", "heading_level": 0, "page_break_before": true, "required": false,
     "guidance": "Numéro, titre et page de chaque tableau et figure."},
    {"id": "introduction", "title": "Introduction générale", "kind": "body", "heading_level": 1, "numbered": false, "page_break_before": true, "required": true,
     "guidance": "Huit à quinze pages en général. Elle présente tout le cadre de ta recherche ; rédige-la au début, puis reprends-la à la fin.",
     "children": [
       {"id": "intro-etat", "title": "État de la question", "heading_level": 2, "guidance": "Présente les travaux antérieurs proches de ton sujet (auteur, année, objet, résultats) et montre ce qui distingue ton travail."},
       {"id": "intro-problematique", "title": "Problématique", "heading_level": 2, "guidance": "Contexte, constat, écart, puis ta question principale (voir le chapitre « Formuler la problématique » du guide)."},
       {"id": "intro-hypotheses", "title": "Hypothèses", "heading_level": 2, "guidance": "Une réponse provisoire par question de recherche, au présent de l'indicatif."},
       {"id": "intro-objectifs", "title": "Objectifs", "heading_level": 2, "guidance": "Un objectif général et deux à quatre objectifs spécifiques, avec des verbes d'action."},
       {"id": "intro-choix-interet", "title": "Choix et intérêt du sujet", "heading_level": 2, "guidance": "Pourquoi ce sujet ? Intérêt personnel, scientifique et pratique."},
       {"id": "intro-delimitation", "title": "Délimitation du sujet", "heading_level": 2, "guidance": "Délimitation thématique, spatiale et temporelle, en justifiant chaque choix."},
       {"id": "intro-methodes", "title": "Méthodes et techniques", "heading_level": 2, "guidance": "La ou les méthodes (démarche intellectuelle) et les techniques (outils de collecte : questionnaire, entretien, analyse documentaire, observation). Indique la population, l'échantillon et la façon de le calculer."},
       {"id": "intro-difficultes", "title": "Difficultés rencontrées", "heading_level": 2, "required": false, "guidance": "Les obstacles réels et la façon dont tu les as surmontés. Reste bref et factuel."},
       {"id": "intro-subdivision", "title": "Subdivision du travail", "heading_level": 2, "guidance": "Annonce le contenu de chaque chapitre en une ou deux phrases."}
     ]},
    {"id": "chap1", "title": "Considérations générales (cadre conceptuel et théorique)", "kind": "body", "heading_level": 1, "page_break_before": true, "required": true,
     "guidance": "Définis les concepts clés de ton sujet en t'appuyant sur des auteurs, puis présente la ou les théories qui éclairent ton analyse.",
     "children": [
       {"id": "chap1-s1", "title": "Définition des concepts", "heading_level": 2, "guidance": "Chaque concept du titre : définitions d'auteurs (avec références), puis la définition que tu retiens pour ton travail."},
       {"id": "chap1-s2", "title": "Cadre théorique", "heading_level": 2, "guidance": "La théorie ou le modèle de référence, et en quoi il t'aide à répondre à ta question."}
     ]},
    {"id": "chap2", "title": "Présentation du milieu d'étude", "kind": "body", "heading_level": 1, "page_break_before": true, "required": true,
     "guidance": "Présente l'organisation, la commune ou le service étudié.",
     "children": [
       {"id": "chap2-s1", "title": "Situation géographique et historique", "heading_level": 2, "guidance": "Localisation, date de création, évolution."},
       {"id": "chap2-s2", "title": "Organisation et fonctionnement", "heading_level": 2, "guidance": "Missions, structure (organigramme), ressources, activités en lien avec ton sujet."}
     ]},
    {"id": "chap3", "title": "Présentation, analyse et interprétation des résultats", "kind": "body", "heading_level": 1, "page_break_before": true, "required": true,
     "guidance": "Le cœur de ton travail : tes propres données.",
     "children": [
       {"id": "chap3-s1", "title": "Démarche de collecte", "heading_level": 2, "guidance": "Rappelle l'échantillon, les outils et le déroulement de la collecte."},
       {"id": "chap3-s2", "title": "Présentation et analyse des résultats", "heading_level": 2, "guidance": "Tableaux et figures numérotés, chacun suivi de son commentaire."},
       {"id": "chap3-s3", "title": "Vérification des hypothèses", "heading_level": 2, "guidance": "Pour chaque hypothèse : confirmée, partiellement confirmée ou infirmée, avec les résultats qui le montrent."}
     ]},
    {"id": "conclusion", "title": "Conclusion générale", "kind": "body", "heading_level": 1, "numbered": false, "page_break_before": true, "required": true,
     "guidance": "Rappelle la question de recherche, la démarche, les principaux résultats et le sort des hypothèses. Termine par des suggestions concrètes et des pistes pour de futures recherches. Aucun élément nouveau."},
    {"id": "bibliographie", "title": "Bibliographie", "kind": "annex", "heading_level": 1, "numbered": false, "page_break_before": true, "required": true,
     "guidance": "Générée depuis ton gestionnaire de bibliographie, classée par type de source puis par ordre alphabétique des auteurs."},
    {"id": "annexes", "title": "Annexes", "kind": "annex", "heading_level": 1, "numbered": false, "page_break_before": true, "required": false,
     "guidance": "Questionnaire vierge, guide d'entretien, documents de l'organisation. Chaque annexe est numérotée et citée dans le texte."},
    {"id": "table-matieres", "title": "Table des matières", "kind": "annex", "heading_level": 1, "numbered": false, "page_break_before": true, "required": true,
     "guidance": "Générée automatiquement à l'export."}
  ]$json$::jsonb,
  $json${
    "page": {"size": "A4", "margins_cm": {"top": 2.5, "bottom": 2.5, "left": 3, "right": 2.5}},
    "font": {"family": "Times New Roman", "size": 12},
    "line_spacing": 1.5,
    "paragraph": {"align": "justify", "first_line_indent_cm": 1.25, "space_after_pt": 6},
    "headings": [
      {"level": 1, "size": 14, "bold": true, "uppercase": true, "align": "center", "numbering": "CHAPITRE {roman}", "page_break_before": true},
      {"level": 2, "size": 12, "bold": true, "align": "left", "numbering": "Section {arabic}."},
      {"level": 3, "size": 12, "bold": true, "align": "left", "numbering": "§{arabic}."},
      {"level": 4, "size": 12, "bold": true, "italic": true, "align": "left", "numbering": "{alpha_upper}."},
      {"level": 5, "size": 12, "italic": true, "align": "left", "numbering": "{arabic}."}
    ],
    "page_numbers": {"position": "bottom_center", "preliminary": "roman_lower", "body": "arabic", "body_starts_at": "introduction"},
    "footnotes": {"size": 10, "line_spacing": 1.0},
    "long_quotes": {"indent_cm": 1.5, "size": 11, "line_spacing": 1.0, "min_lines": 3},
    "tables": {"caption_position": "above", "source_position": "below", "size": 10}
  }$json$::jsonb
);

-- -----------------------------------------------------------------------------
-- Modèle de questionnaire (démonstration)
-- -----------------------------------------------------------------------------
-- body : { variables: [{key, label, example}], intro, sections: [{ title, guidance,
--   questions: [{ id, type: single|multiple|scale|number|open, text, options, scale }] }],
--   closing, tips }
-- Les {{cle}} sont remplacés par les réponses de l'étudiant (nom de l'organisation…).
-- Un modèle de questionnaire est une STRUCTURE à adapter : l'étudiant ajoute
-- les questions propres à ses hypothèses.
insert into public.questionnaire_templates (id, code, domain, title, description, position, is_published) values
  ('00000000-0000-4000-8000-000000000451', 'Q_GESTION_SATISFACTION', 'gestion',
   'Satisfaction des clients ou usagers d''un service',
   'Structure de questionnaire pour mesurer la satisfaction (accueil, délais, coût, qualité) dans une entreprise ou un service public.',
   1, true);

insert into public.questionnaire_template_bodies (template_id, body) values
(
  '00000000-0000-4000-8000-000000000451',
  $json${
    "schema_version": 1,
    "variables": [
      {"key": "organisation", "label": "Nom de l'organisation étudiée", "example": "la SNEL Kinshasa-Est"},
      {"key": "service", "label": "Service ou produit évalué", "example": "le paiement des factures"},
      {"key": "etablissement", "label": "Ton établissement", "example": "l'Université de Kinshasa"}
    ],
    "intro": "Madame, Monsieur,\nÉtudiant(e) finaliste à {{etablissement}}, je mène une enquête sur {{service}} de {{organisation}} dans le cadre de mon travail de fin d'études. Vos réponses sont anonymes et serviront uniquement à cette recherche. Merci de cocher la case qui correspond le mieux à votre avis.",
    "sections": [
      {"title": "Identification du répondant",
       "guidance": "Garde seulement les variables que tu analyseras dans ton chapitre de résultats (elles servent aux tableaux croisés).",
       "questions": [
         {"id": "q1", "type": "single", "text": "Sexe", "options": ["Masculin", "Féminin"]},
         {"id": "q2", "type": "single", "text": "Tranche d'âge", "options": ["Moins de 25 ans", "25 à 34 ans", "35 à 49 ans", "50 ans et plus"]},
         {"id": "q3", "type": "single", "text": "Niveau d'études", "options": ["Primaire", "Secondaire", "Supérieur ou universitaire", "Aucun"]},
         {"id": "q4", "type": "single", "text": "Depuis combien de temps utilisez-vous {{service}} ?", "options": ["Moins d'un an", "1 à 3 ans", "Plus de 3 ans"]}
       ]},
      {"title": "Accueil et information",
       "guidance": "Une section par dimension de ta variable dépendante. Adapte les intitulés à ton terrain.",
       "questions": [
         {"id": "q5", "type": "scale", "text": "Comment jugez-vous l'accueil reçu à {{organisation}} ?", "scale": ["Très mauvais", "Mauvais", "Moyen", "Bon", "Très bon"]},
         {"id": "q6", "type": "single", "text": "Les informations reçues étaient-elles claires ?", "options": ["Oui", "En partie", "Non"]}
       ]},
      {"title": "Délais et coût",
       "guidance": "Formule des questions neutres, sans suggérer la réponse.",
       "questions": [
         {"id": "q7", "type": "number", "text": "Combien de temps (en minutes) avez-vous attendu lors de votre dernier passage ?"},
         {"id": "q8", "type": "scale", "text": "Le coût de {{service}} vous paraît :", "scale": ["Très élevé", "Élevé", "Raisonnable", "Bas"]}
       ]},
      {"title": "Appréciation générale",
       "guidance": "Termine par une question ouverte : elle enrichit l'interprétation de tes tableaux.",
       "questions": [
         {"id": "q9", "type": "multiple", "text": "Quels aspects faudrait-il améliorer en priorité ? (plusieurs réponses possibles)", "options": ["Accueil", "Délais", "Coût", "Information", "Autre (préciser)"]},
         {"id": "q10", "type": "open", "text": "Quelles suggestions feriez-vous à {{organisation}} ?"}
       ]}
    ],
    "closing": "Merci pour votre participation.",
    "tips": [
      "Chaque question doit servir à vérifier une de tes hypothèses : supprime les autres.",
      "Teste ton questionnaire auprès de 5 personnes avant l'enquête et corrige les questions mal comprises.",
      "Le nombre de questionnaires à distribuer vient du calcul de l'échantillon (outil gratuit de MonTFC)."
    ]
  }$json$::jsonb
);

-- -----------------------------------------------------------------------------
-- Offres et prix (exemples, modifiables depuis l'admin)
-- Montants ×100 : 200 = 2,00 USD ; 580000 = 5 800 CDF.
-- -----------------------------------------------------------------------------
insert into public.products (id, code, name, description, kind, feature, requires_resource, duration_days,
                             play_product_id, position) values
  ('00000000-0000-4000-8000-000000000501', 'COVER_PAGE', 'Page de garde',
   'Générateur de page de garde pour tous les établissements, avec export PDF et Word. Accès permanent.',
   'unit', 'cover_page', false, null, 'montfc_cover_page', 1),
  ('00000000-0000-4000-8000-000000000502', 'DOC_TEMPLATE', 'Un modèle de document',
   'Un modèle de TFC ou de mémoire prêt à remplir, aux normes de mise en forme. Accès permanent.',
   'unit', 'doc_template', true, null, 'montfc_doc_template', 2),
  ('00000000-0000-4000-8000-000000000503', 'QUESTIONNAIRE', 'Un modèle de questionnaire',
   'Un modèle de questionnaire d''enquête à adapter à ton sujet. Accès permanent.',
   'unit', 'questionnaire', true, null, 'montfc_questionnaire', 3),
  ('00000000-0000-4000-8000-000000000504', 'PACK_FINALISTE', 'Pack Finaliste',
   'Tout MonTFC pendant 12 mois : pages de garde, tous les modèles, questionnaires, bibliographie et export complet.',
   'pack', 'all', false, 365, 'montfc_pack_finaliste', 0);

insert into public.product_prices (product_id, currency, amount_minor) values
  ('00000000-0000-4000-8000-000000000501', 'USD', 200),
  ('00000000-0000-4000-8000-000000000501', 'CDF', 580000),
  ('00000000-0000-4000-8000-000000000502', 'USD', 300),
  ('00000000-0000-4000-8000-000000000502', 'CDF', 870000),
  ('00000000-0000-4000-8000-000000000503', 'USD', 200),
  ('00000000-0000-4000-8000-000000000503', 'CDF', 580000),
  ('00000000-0000-4000-8000-000000000504', 'USD', 1000),
  ('00000000-0000-4000-8000-000000000504', 'CDF', 2900000);

-- -----------------------------------------------------------------------------
-- Ambassadeur et code promo de démonstration
-- -----------------------------------------------------------------------------
insert into public.ambassadors (id, full_name, phone, institution_id, payout_msisdn, payout_operator, notes) values
  ('00000000-0000-4000-8000-000000000601', 'Ambassadeur Démo', '+243000000001',
   '00000000-0000-4000-8000-000000000101', '+243000000001', 'vodacom', 'Compte de démonstration');

insert into public.promo_codes (id, code, ambassador_id, discount_percent, commission_percent) values
  ('00000000-0000-4000-8000-000000000701', 'DEMO10', '00000000-0000-4000-8000-000000000601', 10, 20);
