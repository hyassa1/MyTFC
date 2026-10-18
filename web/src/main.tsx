import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AdminApp } from './admin/AdminApp';
import { PayPage } from './pay/PayPage';
import { isConfigured } from './lib/supabase';
import './styles.css';

function App() {
  if (!isConfigured) {
    return (
      <div className="narrow card">
        Configuration manquante : copie <code>.env.example</code> en <code>.env.local</code> et renseigne l'adresse
        et la clé publique Supabase.
      </div>
    );
  }
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/payer" element={<PayPage />} />
        <Route path="/admin/*" element={<AdminApp />} />
        <Route path="*" element={<Navigate to="/payer" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
