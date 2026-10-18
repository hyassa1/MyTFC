// Les pages de contenu et de vente, décrites par leurs champs.

import { checkCoverLayout } from '../lib/json';
import { formatMoney } from '../lib/money';
import type { CrudConfig, Row } from './Crud';
import type { Field, Option } from './forms';

const CODE: Pick<Field, 'upper' | 'pattern' | 'patternHelp' | 'required'> = {
  required: true,
  upper: true,
  pattern: /^[A-Z0-9_]+$/,
  patternHelp: 'Majuscules, chiffres et _ uniquement (ex. UNIKIN_TFC).',
};

const published = (r: Row) => (r.is_published ? <span className="ok">Publié</span> : <span className="muted">Brouillon</span>);
const active = (r: Row) => (r.is_active ? <span className="ok">Actif</span> : <span className="muted">Inactif</span>);
const date = (v: unknown) => (typeof v === 'string' ? new Date(v).toLocaleDateString('fr-FR') : '—');

const workTypes: Option[] = [
  { value: 'tfc', label: 'TFC' },
  { value: 'memoire_licence', label: 'Mémoire de licence' },
  { value: 'memoire_master', label: 'Mémoire de master' },
];
const domains: Option[] = ['gestion', 'economie', 'droit', 'sante', 'informatique', 'education'].map((d) => ({
  value: d,
  label: d === 'economie' ? 'Économie' : d === 'sante' ? 'Santé' : d === 'education' ? 'Éducation' : d[0].toUpperCase() + d.slice(1),
}));
const features: Option[] = [
  { value: 'cover_page', label: 'Page de garde' },
  { value: 'doc_template', label: 'Modèle de document' },
  { value: 'questionnaire', label: 'Modèle de questionnaire' },
  { value: 'bibliography', label: 'Bibliographie' },
  { value: 'export', label: 'Export complet' },
  { value: 'all', label: 'Tout (Pack Finaliste)' },
];
const operators: Option[] = [
  { value: 'vodacom', label: 'M-Pesa (Vodacom)' },
  { value: 'orange', label: 'Orange Money' },
  { value: 'airtel', label: 'Airtel Money' },
  { value: 'afrimoney', label: 'Afrimoney' },
];

const publishFields: Field[] = [
  { key: 'position', label: 'Ordre d\'affichage', type: 'number' },
  { key: 'is_published', label: 'Publié (visible dans l\'application)', type: 'checkbox' },
];

export const institutionsConfig: CrudConfig = {
  title: 'Établissements',
  table: 'institutions',
  order: 'position',
  defaults: { city: 'Kinshasa', is_active: true },
  fields: [
    { key: 'code', label: 'Code', type: 'text', ...CODE, help: 'Repris dans les codes des pages de garde. Ne pas changer après publication.' },
    { key: 'name', label: 'Nom complet', type: 'text', required: true },
    { key: 'city', label: 'Ville', type: 'text', required: true },
    { key: 'position', label: 'Ordre d\'affichage', type: 'number' },
    { key: 'is_active', label: 'Proposé dans le profil', type: 'checkbox' },
  ],
  columns: [
    { label: 'Code', render: (r) => <code>{String(r.code)}</code> },
    { label: 'Nom', render: (r) => String(r.name) },
    { label: 'Ville', render: (r) => String(r.city) },
    { label: 'État', render: active },
  ],
};

export const chaptersConfig: CrudConfig = {
  title: 'Guide méthodologique',
  table: 'guide_chapters',
  order: 'position',
  softDelete: true,
  intro: <p>Chapitres gratuits, lisibles hors ligne. Le texte est en Markdown (# titres, **gras**, listes « - »).</p>,
  fields: [
    { key: 'slug', label: 'Identifiant d\'adresse', type: 'text', required: true, pattern: /^[a-z0-9-]+$/, patternHelp: 'Minuscules, chiffres et tirets (ex. problematique).' },
    { key: 'title', label: 'Titre', type: 'text', required: true },
    { key: 'summary', label: 'Résumé', type: 'textarea' },
    { key: 'body_md', label: 'Contenu (Markdown)', type: 'markdown' },
    ...publishFields,
  ],
  columns: [
    { label: '#', render: (r) => String(r.position) },
    { label: 'Titre', render: (r) => String(r.title) },
    { label: 'État', render: published },
    { label: 'Modifié', render: (r) => date(r.updated_at) },
  ],
};

export const coversConfig: CrudConfig = {
  title: 'Pages de garde',
  table: 'cover_templates',
  bodyTable: 'cover_template_bodies',
  order: 'position',
  softDelete: true,
  intro: <p>La mise en page (format version 1) est protégée : seuls les étudiants qui l'ont débloquée la reçoivent. Voir le README, section « Formats des contenus ».</p>,
  fields: [
    { key: 'code', label: 'Code', type: 'text', ...CODE },
    { key: 'name', label: 'Nom', type: 'text', required: true },
    { key: 'description', label: 'Description', type: 'textarea' },
    { key: 'institution_id', label: 'Établissement', type: 'select', options: 'institutions', help: 'Aucun = modèle générique.' },
    { key: 'fields_schema', label: 'Champs à remplir (JSON, liste)', type: 'json', expected: 'array' },
    { key: 'layout', label: 'Mise en page (JSON, objet)', type: 'json', expected: 'object', inBody: true, check: checkCoverLayout },
    ...publishFields,
  ],
  columns: [
    { label: 'Code', render: (r) => <code>{String(r.code)}</code> },
    { label: 'Nom', render: (r) => String(r.name) },
    { label: 'État', render: published },
  ],
};

export const documentTemplatesConfig: CrudConfig = {
  title: 'Modèles de document',
  table: 'document_templates',
  bodyTable: 'document_template_bodies',
  order: 'position',
  softDelete: true,
  intro: <p>Plans et normes de mise en forme. Les consignes guident l'étudiant ; aucun texte rédigé à sa place.</p>,
  fields: [
    { key: 'code', label: 'Code', type: 'text', ...CODE },
    { key: 'title', label: 'Titre', type: 'text', required: true },
    { key: 'work_type', label: 'Type de travail', type: 'select', options: workTypes, required: true },
    { key: 'description', label: 'Description', type: 'textarea' },
    { key: 'structure', label: 'Plan (JSON, liste)', type: 'json', expected: 'array', inBody: true },
    { key: 'formatting', label: 'Normes de mise en forme (JSON, objet)', type: 'json', expected: 'object', inBody: true },
    ...publishFields,
  ],
  columns: [
    { label: 'Code', render: (r) => <code>{String(r.code)}</code> },
    { label: 'Titre', render: (r) => String(r.title) },
    { label: 'Type', render: (r) => workTypes.find((w) => w.value === r.work_type)?.label ?? String(r.work_type) },
    { label: 'État', render: published },
  ],
};

export const questionnairesConfig: CrudConfig = {
  title: 'Modèles de questionnaire',
  table: 'questionnaire_templates',
  bodyTable: 'questionnaire_template_bodies',
  order: 'position',
  softDelete: true,
  fields: [
    { key: 'code', label: 'Code', type: 'text', ...CODE },
    { key: 'title', label: 'Titre', type: 'text', required: true },
    { key: 'domain', label: 'Domaine', type: 'select', options: domains, required: true },
    { key: 'description', label: 'Description', type: 'textarea' },
    { key: 'body', label: 'Questionnaire (JSON, objet)', type: 'json', expected: 'object', inBody: true },
    ...publishFields,
  ],
  columns: [
    { label: 'Code', render: (r) => <code>{String(r.code)}</code> },
    { label: 'Titre', render: (r) => String(r.title) },
    { label: 'Domaine', render: (r) => domains.find((d) => d.value === r.domain)?.label ?? String(r.domain) },
    { label: 'État', render: published },
  ],
};

export const productsConfig: CrudConfig = {
  title: 'Offres et prix',
  table: 'products',
  order: 'position',
  withPrices: true,
  defaults: { kind: 'unit', is_active: true },
  intro: (
    <p>
      Les prix s'appliquent aux prochains paiements mobile money. Sur Google Play, le prix affiché est celui de la
      Play Console : garde-les cohérents.
    </p>
  ),
  fields: [
    { key: 'code', label: 'Code', type: 'text', ...CODE },
    { key: 'name', label: 'Nom', type: 'text', required: true },
    { key: 'description', label: 'Description', type: 'textarea' },
    { key: 'kind', label: 'Type', type: 'select', required: true, options: [{ value: 'unit', label: 'Achat à l\'unité' }, { value: 'pack', label: 'Pack' }] },
    { key: 'feature', label: 'Fonction débloquée', type: 'select', required: true, options: features },
    { key: 'requires_resource', label: 'Achat d\'un modèle précis (page de garde, document, questionnaire)', type: 'checkbox' },
    { key: 'duration_days', label: 'Durée en jours', type: 'number', help: 'Vide = permanent. Pack Finaliste : 365.' },
    { key: 'price_cdf', label: 'Prix en francs congolais (FC)', type: 'money', currency: 'CDF' },
    { key: 'price_usd', label: 'Prix en dollars ($)', type: 'money', currency: 'USD' },
    { key: 'play_product_id', label: 'Identifiant Google Play', type: 'text', help: 'Produit consommable de la Play Console (ex. montfc_pack_finaliste).' },
    { key: 'position', label: 'Ordre d\'affichage', type: 'number' },
    { key: 'is_active', label: 'En vente', type: 'checkbox' },
  ],
  columns: [
    { label: 'Offre', render: (r) => String(r.name) },
    { label: 'Fonction', render: (r) => features.find((f) => f.value === r.feature)?.label ?? String(r.feature) },
    {
      label: 'Prix',
      render: (r) =>
        ((r.product_prices as { currency: string; amount_minor: number }[]) ?? [])
          .map((p) => formatMoney(p.amount_minor, p.currency))
          .join(' · ') || '—',
    },
    { label: 'Durée', render: (r) => (r.duration_days ? `${r.duration_days} j` : 'Permanent') },
    { label: 'État', render: active },
  ],
};

export const ambassadorsConfig: CrudConfig = {
  title: 'Ambassadeurs',
  table: 'ambassadors',
  order: 'full_name',
  defaults: { is_active: true },
  fields: [
    { key: 'full_name', label: 'Nom complet', type: 'text', required: true },
    { key: 'phone', label: 'Téléphone', type: 'text', required: true, pattern: /^\+?\d{9,15}$/, patternHelp: 'Chiffres uniquement, ex. +243812345678.' },
    { key: 'institution_id', label: 'Établissement', type: 'select', options: 'institutions' },
    { key: 'payout_msisdn', label: 'Numéro mobile money pour les commissions', type: 'text', pattern: /^\+?\d{9,15}$/, patternHelp: 'Chiffres uniquement.' },
    { key: 'payout_operator', label: 'Service mobile money', type: 'select', options: operators },
    { key: 'notes', label: 'Notes', type: 'textarea' },
    { key: 'is_active', label: 'Actif', type: 'checkbox' },
  ],
  columns: [
    { label: 'Nom', render: (r) => String(r.full_name) },
    { label: 'Téléphone', render: (r) => String(r.phone) },
    { label: 'Paiement', render: (r) => (r.payout_msisdn ? String(r.payout_msisdn) : '—') },
    { label: 'État', render: active },
  ],
};

export const promosConfig: CrudConfig = {
  title: 'Codes promo',
  table: 'promo_codes',
  order: 'created_at',
  desc: true,
  defaults: { is_active: true, discount_percent: 10, commission_percent: 10 },
  intro: <p>Un code lié à un ambassadeur lui rapporte une commission sur chaque paiement confirmé.</p>,
  fields: [
    { key: 'code', label: 'Code', type: 'text', required: true, upper: true, pattern: /^[A-Z0-9_-]{3,32}$/, patternHelp: '3 à 32 caractères : majuscules, chiffres, - et _.' },
    { key: 'ambassador_id', label: 'Ambassadeur', type: 'select', options: 'ambassadors' },
    { key: 'discount_percent', label: 'Réduction pour l\'étudiant (%)', type: 'number', required: true, help: 'De 0 à 90.' },
    { key: 'commission_percent', label: 'Commission de l\'ambassadeur (% du montant payé)', type: 'number', required: true },
    { key: 'applies_to', label: 'Offres concernées', type: 'multiselect', options: 'products', help: 'Aucune cochée = toutes les offres.' },
    { key: 'valid_from', label: 'Valable à partir du', type: 'datetime' },
    { key: 'valid_to', label: 'Valable jusqu\'au', type: 'datetime' },
    { key: 'max_uses', label: 'Nombre maximal d\'utilisations', type: 'number', help: 'Vide = illimité.' },
    { key: 'is_active', label: 'Actif', type: 'checkbox' },
  ],
  columns: [
    { label: 'Code', render: (r) => <code>{String(r.code)}</code> },
    { label: 'Réduction', render: (r) => `${Number(r.discount_percent)} %` },
    { label: 'Commission', render: (r) => `${Number(r.commission_percent)} %` },
    { label: 'Utilisations', render: (r) => `${r.uses_count}${r.max_uses ? ` / ${r.max_uses}` : ''}` },
    { label: 'Fin', render: (r) => date(r.valid_to) },
    { label: 'État', render: active },
  ],
};
