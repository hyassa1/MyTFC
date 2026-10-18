import { NavLink, Navigate, Route, Routes } from 'react-router-dom';
import { PhoneLogin } from '../components/PhoneLogin';
import { useAdminRole, useSession } from '../lib/session';
import { supabase } from '../lib/supabase';
import { CrudPage } from './Crud';
import { Dashboard } from './Dashboard';
import { SettingsPage } from './SettingsPage';
import { UsersPage } from './UsersPage';
import {
  ambassadorsConfig, chaptersConfig, coversConfig, documentTemplatesConfig, institutionsConfig,
  productsConfig, promosConfig, questionnairesConfig,
} from './configs';

/**
 * Panneau d'administration. L'accès est vérifié par la base (RLS + is_admin()) :
 * ce garde-fou d'interface ne sert qu'à afficher un message clair.
 * Rôle « editor » : contenus seulement ; rôle « admin » : tout.
 */
export function AdminApp() {
  const session = useSession();
  const role = useAdminRole(session?.user.id);

  if (session === undefined || (session && role === undefined)) return <p className="narrow muted">Chargement…</p>;
  if (!session) {
    return (
      <div className="narrow">
        <PhoneLogin title="MonTFC — Administration" intro="Connexion réservée à l'équipe MonTFC." />
      </div>
    );
  }
  if (!role) {
    return (
      <div className="narrow card">
        <p>Ce compte ({session.user.phone}) n'a pas accès à l'administration.</p>
        <button onClick={() => supabase.auth.signOut()}>Se déconnecter</button>
      </div>
    );
  }

  const isAdmin = role === 'admin';
  const links: [string, string, boolean][] = [
    ['', 'Tableau de bord', isAdmin],
    ['etudiants', 'Étudiants', isAdmin],
    ['guide', 'Guide', true],
    ['pages-de-garde', 'Pages de garde', true],
    ['modeles', 'Modèles de document', true],
    ['questionnaires', 'Questionnaires', true],
    ['etablissements', 'Établissements', true],
    ['offres', 'Offres et prix', isAdmin],
    ['promos', 'Codes promo', isAdmin],
    ['ambassadeurs', 'Ambassadeurs', isAdmin],
    ['reglages', 'Réglages', isAdmin],
  ];

  return (
    <div className="shell">
      <nav className="side">
        <div className="brand">MonTFC</div>
        {links.filter(([, , ok]) => ok).map(([path, label]) => (
          <NavLink key={path} to={`/admin/${path}`} end={path === ''}>{label}</NavLink>
        ))}
        <a href="#" onClick={(e) => { e.preventDefault(); supabase.auth.signOut(); }}>Se déconnecter</a>
      </nav>
      <main>
        <Routes>
          <Route index element={isAdmin ? <Dashboard /> : <Navigate to="guide" replace />} />
          <Route path="guide" element={<CrudPage config={chaptersConfig} />} />
          <Route path="pages-de-garde" element={<CrudPage config={coversConfig} />} />
          <Route path="modeles" element={<CrudPage config={documentTemplatesConfig} />} />
          <Route path="questionnaires" element={<CrudPage config={questionnairesConfig} />} />
          <Route path="etablissements" element={<CrudPage config={institutionsConfig} />} />
          {isAdmin && (
            <>
              <Route path="etudiants" element={<UsersPage />} />
              <Route path="offres" element={<CrudPage config={productsConfig} />} />
              <Route path="promos" element={<CrudPage config={promosConfig} />} />
              <Route path="ambassadeurs" element={<CrudPage config={ambassadorsConfig} />} />
              <Route path="reglages" element={<SettingsPage />} />
            </>
          )}
          <Route path="*" element={<Navigate to="/admin" replace />} />
        </Routes>
      </main>
    </div>
  );
}
