/// Point de la liste de vérification avant dépôt.
class ChecklistItem {
  const ChecklistItem(this.id, this.label);

  /// Identifiant stable : ne jamais le changer (il sert de clé d'enregistrement).
  final String id;
  final String label;
}

class ChecklistSection {
  const ChecklistSection(this.title, this.items);

  final String title;
  final List<ChecklistItem> items;
}

/// Liste par défaut. Elle est embarquée dans l'application pour fonctionner
/// sans connexion ; les cases cochées sont enregistrées sur le téléphone.
const depositChecklist = [
  ChecklistSection('Fond', [
    ChecklistItem('fond-sujet-valide', 'Le sujet a été validé par mon directeur et correspond au titre final.'),
    ChecklistItem('fond-problematique', 'La problématique se termine par une question de recherche claire.'),
    ChecklistItem('fond-hypotheses', 'Chaque hypothèse est vérifiée (confirmée ou infirmée) dans le travail.'),
    ChecklistItem('fond-objectifs', 'Les objectifs annoncés sont atteints et repris dans la conclusion.'),
    ChecklistItem('fond-methode', 'Les méthodes, techniques et l\'échantillon sont décrits et justifiés.'),
    ChecklistItem('fond-conclusion', 'La conclusion ne contient aucun élément nouveau.'),
    ChecklistItem('fond-relecture-encadreur', 'Mon encadreur a relu la dernière version.'),
  ]),
  ChecklistSection('Sources et citations', [
    ChecklistItem('src-citations', 'Toute idée empruntée est citée avec sa source (pas de plagiat).'),
    ChecklistItem('src-bibliographie', 'Chaque source citée figure dans la bibliographie, et inversement.'),
    ChecklistItem('src-style', 'Un seul style de citation est utilisé du début à la fin.'),
    ChecklistItem('src-ordre', 'La bibliographie est classée par type de source puis par ordre alphabétique.'),
  ]),
  ChecklistSection('Mise en forme', [
    ChecklistItem('mef-page-garde', 'La page de garde est conforme au modèle de mon établissement.'),
    ChecklistItem('mef-police', 'Police Times New Roman 12, interligne 1,5, texte justifié.'),
    ChecklistItem('mef-marges', 'Marges respectées (souvent 2,5 cm, et 3 cm à gauche pour la reliure).'),
    ChecklistItem('mef-pagination', 'Pages numérotées : chiffres romains avant l\'introduction, arabes ensuite.'),
    ChecklistItem('mef-titres', 'Titres hiérarchisés et numérotés de la même façon partout.'),
    ChecklistItem('mef-tableaux', 'Tableaux et figures numérotés, titrés et sourcés.'),
    ChecklistItem('mef-table-matieres', 'La table des matières correspond aux titres et aux pages réels.'),
    ChecklistItem('mef-orthographe', 'Orthographe et grammaire relues (de préférence par une autre personne).'),
  ]),
  ChecklistSection('Dépôt', [
    ChecklistItem('depot-exemplaires', 'Le nombre d\'exemplaires demandé est imprimé et relié.'),
    ChecklistItem('depot-version-numerique', 'La version numérique (Word et PDF) est enregistrée et sauvegardée.'),
    ChecklistItem('depot-documents', 'Les documents administratifs exigés sont prêts (frais, formulaires, attestations).'),
    ChecklistItem('depot-date', 'Je connais la date limite de dépôt et le bureau où déposer.'),
  ]),
  ChecklistSection('Soutenance', [
    ChecklistItem('sout-presentation', 'Ma présentation tient dans le temps imparti (souvent 15 à 20 minutes).'),
    ChecklistItem('sout-questions', 'J\'ai préparé des réponses aux questions probables du jury.'),
    ChecklistItem('sout-repetition', 'J\'ai répété au moins une fois devant quelqu\'un.'),
  ]),
];
