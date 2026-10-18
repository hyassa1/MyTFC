import { useState } from 'react';
import { parsePhone } from '../lib/phone';
import { supabase } from '../lib/supabase';

/** Connexion par numéro de téléphone et code SMS (même compte que l'application). */
export function PhoneLogin({ title, intro }: { title: string; intro?: string }) {
  const [phone, setPhone] = useState('');
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    const parsed = parsePhone(phone);
    if (!parsed) return setError('Numéro invalide. Exemple : 0812345678.');
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({ phone: parsed.e164 });
    setBusy(false);
    if (error) return setError('Le code n\'a pas pu être envoyé. Réessaie dans un instant.');
    setSentTo(parsed.e164);
  }

  async function verify() {
    if (!sentTo) return;
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.verifyOtp({ phone: sentTo, token: code.trim(), type: 'sms' });
    setBusy(false);
    if (error) setError('Code incorrect ou expiré.');
  }

  return (
    <div className="card">
      <h2>{title}</h2>
      {intro && <p className="muted">{intro}</p>}
      {!sentTo ? (
        <>
          <label htmlFor="phone">Numéro de téléphone</label>
          <input id="phone" inputMode="tel" placeholder="0812345678" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <p><button className="primary" disabled={busy} onClick={send}>Recevoir le code par SMS</button></p>
        </>
      ) : (
        <>
          <p>Code envoyé au {sentTo}.</p>
          <label htmlFor="code">Code à 6 chiffres</label>
          <input id="code" inputMode="numeric" maxLength={6} value={code} onChange={(e) => setCode(e.target.value)} />
          <p className="row">
            <button className="primary" disabled={busy || code.trim().length < 6} onClick={verify}>Se connecter</button>
            <button onClick={() => setSentTo(null)}>Changer de numéro</button>
          </p>
        </>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
