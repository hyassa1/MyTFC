import { useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { PhoneLogin } from '../components/PhoneLogin';
import { errorMessage, functionErrorCode } from '../lib/errors';
import { formatMoney } from '../lib/money';
import { parsePhone } from '../lib/phone';
import { useSession } from '../lib/session';
import { supabase } from '../lib/supabase';
import { buildOffers, nextStep, type Offer, type PublicPayment } from './payment';

interface Quote {
  currency: string;
  amount_gross_minor: number;
  discount_minor: number;
  amount_net_minor: number;
  promo_error: string | null;
}

const OPERATORS = [
  ['vodacom', 'M-Pesa (Vodacom)'],
  ['orange', 'Orange Money'],
  ['airtel', 'Airtel Money'],
  ['afrimoney', 'Afrimoney (Africell)'],
] as const;

/**
 * Paiement mobile money depuis un navigateur (étudiants qui n'utilisent pas
 * l'APK direct). Le serveur lance la transaction ; l'étudiant confirme avec son
 * code PIN ; l'accès est débloqué sur son compte et apparaît dans l'application.
 */
export function PayPage() {
  const session = useSession();
  return (
    <div className="narrow">
      <h1>MonTFC : paiement</h1>
      {session === undefined ? (
        <p className="muted">Chargement…</p>
      ) : session === null ? (
        <PhoneLogin title="Connexion" intro="Utilise le même numéro que dans l'application MonTFC." />
      ) : (
        <Checkout accountPhone={session.user.phone ?? ''} />
      )}
    </div>
  );
}

function Checkout({ accountPhone }: { accountPhone: string }) {
  const [params] = useSearchParams();
  const [offers, setOffers] = useState<Offer[]>([]);
  const [resources, setResources] = useState<Array<{ id: string; title: string; kind: string }>>([]);
  const [offerId, setOfferId] = useState('');
  const [resourceId, setResourceId] = useState(params.get('modele') ?? '');
  const [currency, setCurrency] = useState('CDF');
  const [promo, setPromo] = useState('');
  const [quote, setQuote] = useState<Quote | null>(null);
  const [phone, setPhone] = useState(accountPhone ? `0${accountPhone.replace(/^243/, '')}` : '');
  const [operator, setOperator] = useState<string>(parsePhone(accountPhone)?.operator ?? 'vodacom');
  const [payment, setPayment] = useState<PublicPayment | null>(null);
  const [outcome, setOutcome] = useState<'success' | 'failure' | 'timeout' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const idempotencyKey = useRef(crypto.randomUUID());

  useEffect(() => {
    (async () => {
      const [products, prices, docs, quests] = await Promise.all([
        supabase.from('products').select('id, code, name, description, feature, requires_resource, is_active, position'),
        supabase.from('product_prices').select('product_id, currency, amount_minor'),
        supabase.from('document_templates').select('id, title').eq('is_published', true).is('deleted_at', null),
        supabase.from('questionnaire_templates').select('id, title').eq('is_published', true).is('deleted_at', null),
      ]);
      const list = buildOffers(products.data ?? [], prices.data ?? []);
      setOffers(list);
      const wanted = list.find((o) => o.code === params.get('offre')) ?? list[0];
      if (wanted) setOfferId(wanted.id);
      setResources([
        ...(docs.data ?? []).map((d) => ({ ...d, kind: 'doc_template' })),
        ...(quests.data ?? []).map((q) => ({ ...q, kind: 'questionnaire' })),
      ]);
    })();
  }, [params]);

  const offer = useMemo(() => offers.find((o) => o.id === offerId), [offers, offerId]);

  useEffect(() => {
    if (offer && !offer.prices[currency]) setCurrency(Object.keys(offer.prices)[0]);
  }, [offer, currency]);

  async function refreshQuote(code = promo) {
    if (!offer || !offer.prices[currency]) return;
    const { data, error } = await supabase.rpc('quote_price', {
      p_product_id: offer.id,
      p_currency: currency,
      p_promo_code: code.trim() || null,
    });
    if (!error) setQuote(data as Quote);
  }

  useEffect(() => {
    void refreshQuote();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offer, currency]);

  // Suivi du paiement jusqu'au résultat.
  useEffect(() => {
    if (!payment || outcome) return;
    const timer = setInterval(async () => {
      const { data, error } = await supabase.functions.invoke('payment-status', { body: { payment_id: payment.id } });
      if (error) return; // réseau instable : on réessaie au prochain tour
      const p = (data as { payment: PublicPayment }).payment;
      setPayment(p);
      const step = nextStep(p, Date.now());
      if (step !== 'wait') setOutcome(step);
    }, 5000);
    return () => clearInterval(timer);
  }, [payment, outcome]);

  async function pay() {
    if (!offer || !quote) return;
    const parsed = parsePhone(phone);
    if (!parsed) return setError('Numéro mobile money invalide. Exemple : 0812345678.');
    if (offer.requires_resource && !resourceId) return setError(errorMessage('resource_required'));
    if (quote.promo_error) return setError(errorMessage(quote.promo_error));
    setBusy(true);
    setError(null);
    const { data, error } = await supabase.functions.invoke('payment-init', {
      body: {
        product_id: offer.id,
        resource_id: offer.requires_resource ? resourceId : null,
        currency,
        msisdn: parsed.e164,
        operator,
        promo_code: promo.trim() || null,
        idempotency_key: idempotencyKey.current,
        channel: 'mobile_money_web',
      },
    });
    setBusy(false);
    if (error) return setError(errorMessage(await functionErrorCode(error)));
    const p = (data as { payment: PublicPayment }).payment;
    setPayment(p);
    const step = nextStep(p, Date.now());
    if (step !== 'wait') setOutcome(step);
  }

  if (payment) {
    return (
      <div className="card">
        {outcome === 'success' ? (
          <>
            <h2 className="ok">Paiement confirmé</h2>
            <p>{offer?.name} est débloqué sur ton compte. Ouvre l'application MonTFC : l'accès apparaît à la prochaine synchronisation.</p>
          </>
        ) : outcome ? (
          <>
            <h2 className="error">{outcome === 'timeout' ? 'Délai dépassé' : 'Paiement non abouti'}</h2>
            <p>{errorMessage(outcome === 'timeout' ? 'timeout' : payment.failure_reason)}</p>
            <button onClick={() => { idempotencyKey.current = crypto.randomUUID(); setPayment(null); setOutcome(null); }}>Réessayer</button>
          </>
        ) : (
          <>
            <h2>Confirme sur ton téléphone</h2>
            <p>Un message de ton opérateur va s'afficher : saisis ton code PIN pour payer {formatMoney(payment.amount_net_minor, payment.currency)}.</p>
            <p className="muted">Cette page se met à jour toute seule. Ne communique jamais ton code PIN.</p>
          </>
        )}
      </div>
    );
  }

  const resourceKind = offer?.feature === 'questionnaire' ? 'questionnaire' : 'doc_template';
  return (
    <div className="card">
      <label htmlFor="offer">Offre</label>
      <select id="offer" value={offerId} onChange={(e) => setOfferId(e.target.value)}>
        {offers.map((o) => (
          <option key={o.id} value={o.id}>{o.name}</option>
        ))}
      </select>
      {offer?.description && <p className="muted">{offer.description}</p>}

      {offer?.requires_resource && (
        <>
          <label htmlFor="res">Modèle</label>
          <select id="res" value={resourceId} onChange={(e) => setResourceId(e.target.value)}>
            <option value="">Choisis…</option>
            {resources.filter((r) => r.kind === resourceKind).map((r) => (
              <option key={r.id} value={r.id}>{r.title}</option>
            ))}
          </select>
        </>
      )}

      <label htmlFor="cur">Devise</label>
      <select id="cur" value={currency} onChange={(e) => setCurrency(e.target.value)}>
        {offer && Object.keys(offer.prices).map((c) => (
          <option key={c} value={c}>{c === 'CDF' ? 'Francs congolais (FC)' : 'Dollars ($)'}</option>
        ))}
      </select>

      <label htmlFor="promo">Code promo (facultatif)</label>
      <div className="row">
        <input id="promo" style={{ flex: 1, width: 'auto' }} value={promo} onChange={(e) => setPromo(e.target.value.toUpperCase())} />
        <button onClick={() => refreshQuote()}>Appliquer</button>
      </div>
      {quote?.promo_error && <p className="error">{errorMessage(quote.promo_error)}</p>}

      {quote && (
        <p>
          {quote.discount_minor > 0 && (
            <span className="muted">
              Prix : {formatMoney(quote.amount_gross_minor, quote.currency)}, réduction : −{formatMoney(quote.discount_minor, quote.currency)}
              <br />
            </span>
          )}
          <strong>À payer : {formatMoney(quote.amount_net_minor, quote.currency)}</strong>
        </p>
      )}

      <label htmlFor="mm">Numéro mobile money</label>
      <input id="mm" inputMode="tel" value={phone} onChange={(e) => { setPhone(e.target.value); const op = parsePhone(e.target.value)?.operator; if (op) setOperator(op); }} />
      <label htmlFor="op">Service</label>
      <select id="op" value={operator} onChange={(e) => setOperator(e.target.value)}>
        {OPERATORS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>

      {error && <p className="error">{error}</p>}
      <p>
        <button className="primary" disabled={busy || !quote} onClick={pay}>
          {quote ? `Payer ${formatMoney(quote.amount_net_minor, quote.currency)}` : 'Payer'}
        </button>
      </p>
      <p className="row">
        <button onClick={() => supabase.auth.signOut()}>Se déconnecter</button>
      </p>
    </div>
  );
}
