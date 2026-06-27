// ============================================================================
// YeboSell — Shared Configuration
// Sell smarter. Reach further. Grow together.
// All vars attached to window so Babel-transpiled scripts can access them
// ============================================================================

window.SUPABASE_URL = 'https://nizrqwvfuxbuhertypva.supabase.co';
window.SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5penJxd3ZmdXhidWhlcnR5cHZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3NTg3MjMsImV4cCI6MjA5MTMzNDcyM30.nqduzFlkaYWq2kYYFQysb8nBU_l1Eom88uoS7l6pkCw';
window.SITE_URL = window.location.origin || 'https://yebosell.com';
window.BRAND_NAME = 'YeboSell';
window.BRAND_TAGLINE = 'Sell smarter. Reach further. Grow together.';

// Initialize Supabase
window.supabaseClient = null;
try {
    window.supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);
} catch (e) {
    console.warn('Supabase initialization error:', e);
}

// ============================================================================
// UTILITY FUNCTIONS (all on window for Babel compatibility)
// ============================================================================

window.hashPin = (pin) => {
    let hash = 0;
    for (let i = 0; i < pin.length; i++) {
        const char = pin.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return hash.toString();
};

// Lesotho Loti / Maloti (symbol "M", 1:1 with the Rand). Change to 'R' if launching in SA.
window.formatCurrency = (amount) => `M${parseFloat(amount || 0).toFixed(2)}`;

window.generateSlug = (name) => {
    return name.toLowerCase()
        .replace(/[^a-z0-9\s-]/g, '')
        .replace(/\s+/g, '-')
        .replace(/-+/g, '-')
        .trim();
};

window.generateOrderNumber = () => {
    const d = new Date();
    const dateStr = d.toISOString().slice(0, 10).replace(/-/g, '');
    const rand = Math.floor(Math.random() * 900 + 100);
    return `ORD-${dateStr}-${rand}`;
};

window.getStatusColor = (status) => {
    const map = {
        new: '#3b82f6', confirmed: '#8b5cf6', paid: '#10b981',
        shipped: '#f59e0b', delivered: '#059669', cancelled: '#ef4444',
        pending: '#f59e0b', in_transit: '#3b82f6', dispatched: '#8b5cf6',
        preparing: '#6b7280', failed: '#ef4444',
        rejected: '#ef4444',
        ready_for_pickup: '#8b5cf6', out_for_delivery: '#f59e0b'
    };
    return map[status] || '#6b7280';
};

// Canonical order lifecycle (single source of truth, shown identically to
// buyer & seller). Step 4 is delivery-method-aware. Payment is a separate axis.
window.ORDER_STAGE_LABELS = {
    new: 'New', confirmed: 'Confirmed', preparing: 'Preparing',
    ready_for_pickup: 'Ready for Pickup', out_for_delivery: 'Out for Delivery',
    delivered: 'Delivered', cancelled: 'Cancelled'
};
// Ordered stages for an order, adapted to its delivery method: pickup orders
// get 'Ready for Pickup' at step 4, every other method gets 'Out for Delivery'.
// Excludes 'cancelled' (a separate terminal state).
window.orderStages = (deliveryMethod) => {
    const isPickup = deliveryMethod === 'pickup';
    return [
        { key: 'new', label: 'New', desc: 'Order placed' },
        { key: 'confirmed', label: 'Confirmed', desc: 'Seller confirmed your order' },
        { key: 'preparing', label: 'Preparing', desc: 'Your order is being prepared' },
        isPickup
            ? { key: 'ready_for_pickup', label: 'Ready for Pickup', desc: 'Your order is ready to collect' }
            : { key: 'out_for_delivery', label: 'Out for Delivery', desc: 'Your order is on its way' },
        { key: 'delivered', label: 'Delivered', desc: isPickup ? 'Your order has been collected' : 'Your order has been delivered' }
    ];
};

window.getStatusLabel = (status) => {
    if (window.ORDER_STAGE_LABELS && window.ORDER_STAGE_LABELS[status]) return window.ORDER_STAGE_LABELS[status];
    return (status || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
};

// Convert any local or international phone into WhatsApp digits (E.164 without the +).
// Routes through normalizePhone so local numbers get their country code (Lesotho +266 / SA +27).
window.waNumber = (raw) => (window.normalizePhone ? window.normalizePhone(raw) : ('' + (raw || ''))).replace(/[^0-9]/g, '');

// WhatsApp deep link helper — always targets the full international number.
window.whatsappLink = (phone, message) => {
    return `https://wa.me/${window.waNumber(phone)}?text=${encodeURIComponent(message)}`;
};

// WhatsApp share link (for sharing to groups)
window.whatsappShareLink = (message) => {
    return `https://wa.me/?text=${encodeURIComponent(message)}`;
};

// ============================================================================
// BUYER NOTIFICATIONS (click-to-chat, no WhatsApp API)
// Pre-filled messages the SELLER sends from their own WhatsApp. EN + Sesotho.
// ctx: { name, order, seller, total, link, pickup, statusLabel, lang }
// ============================================================================
window.BUYER_TEMPLATES = {
    en: {
        order_confirmation: c => `Hi ${c.name || 'there'} 👋 Thanks for your order *${c.order}* with ${c.seller} — total ${c.total}. Track it anytime here:\n${c.link}`,
        payment_received:   c => `✅ Payment received for order *${c.order}*. We're preparing it now. Track your order:\n${c.link}`,
        status_update:      c => `📦 Update on your order *${c.order}*: ${c.statusLabel}. Track it here:\n${c.link}`,
        ready_for_pickup:   c => `🏪 Your order *${c.order}* is ready for pickup${c.pickup ? ' at ' + c.pickup : ''}. Details:\n${c.link}`,
        out_for_delivery:   c => `🚗 Your order *${c.order}* is out for delivery. Follow it here:\n${c.link}`,
        delivered:          c => `✅ Your order *${c.order}* has been delivered. Thank you for shopping with ${c.seller}! 🙏\n${c.link}`
    },
    st: {
        order_confirmation: c => `Lumela ${c.name || ''} 👋 Kea leboha ka oda ea hau *${c.order}* ho ${c.seller} — kakaretso ${c.total}. Lekola oda ea hau mona:\n${c.link}`,
        payment_received:   c => `✅ Tefo e amohetsoe bakeng sa oda *${c.order}*. Re ea e lokisa hona joale. Lekola oda:\n${c.link}`,
        status_update:      c => `📦 Tlhahiso ka oda ea hau *${c.order}*: ${c.statusLabel}. Lekola mona:\n${c.link}`,
        ready_for_pickup:   c => `🏪 Oda ea hau *${c.order}* e se e loketse ho nkuoa${c.pickup ? ' ' + c.pickup : ''}. Lintlha:\n${c.link}`,
        out_for_delivery:   c => `🚗 Oda ea hau *${c.order}* e tsamaisoa ho uena. E sale morao mona:\n${c.link}`,
        delivered:          c => `✅ Oda ea hau *${c.order}* e fihlile. Kea leboha ka ho reka le ${c.seller}! 🙏\n${c.link}`
    }
};

window.buildBuyerNotice = (milestone, ctx) => {
    const lang = (ctx && ctx.lang === 'st') ? 'st' : 'en';
    const set = window.BUYER_TEMPLATES[lang] || window.BUYER_TEMPLATES.en;
    const fn = set[milestone] || set.status_update;
    return fn(ctx || {});
};

// Opens the SELLER's own WhatsApp with a pre-filled buyer message. No API, no WABA.
window.notifyBuyer = (phone, milestone, ctx) => {
    if (!phone) { alert('No buyer phone number on this order.'); return false; }
    window.open(window.whatsappLink(phone, window.buildBuyerNotice(milestone, ctx)), '_blank');
    return true;
};

// Build the tokenized tracking link for an order
window.trackLink = (trackToken) => trackToken
    ? `${window.SITE_URL}/track/?t=${trackToken}`
    : `${window.SITE_URL}/track/`;

// Canonical phone normalization to E.164 — accepts the local formats people type:
//   South Africa: 0XX XXX XXXX        -> +27XXXXXXXXX
//   Lesotho:      XXXX XXXX (8 digits) -> +266XXXXXXXX
//   Also handles +.., 00.., 27.., 266.. prefixes.
window.normalizePhone = (raw) => {
    let s = (raw || '').toString().trim();
    if (s.startsWith('+')) return '+' + s.slice(1).replace(/\D/g, '');
    const p = s.replace(/\D/g, '');
    if (p.startsWith('00')) return '+' + p.slice(2);
    if (p.startsWith('266')) return '+' + p;          // Lesotho with country code
    if (p.startsWith('27')) return '+' + p;           // SA with country code
    if (p.startsWith('0')) return '+27' + p.slice(1); // SA local  0XX XXX XXXX
    if (p.length === 8) return '+266' + p;            // Lesotho local  XXXX XXXX
    if (p.length === 9) return '+27' + p;             // SA local without leading 0
    return '+' + p;
};

// Live input masking: format digits AS THE USER TYPES into the local layout.
//   SA (starts 0):   0XX XXX XXXX   ·   Lesotho (8 digits): XXXX XXXX
//   Country-code / + entries pass through as digits (normalizePhone handles E.164).
window.formatLocalPhone = (raw) => {
    const s = (raw || '').toString();
    const hasPlus = s.trim().startsWith('+');
    let d = s.replace(/\D/g, '');
    if (hasPlus || d.startsWith('266') || d.startsWith('27')) {
        return (hasPlus ? '+' : '') + d.slice(0, 12);
    }
    if (d.startsWith('0')) {                 // SA local: 0XX XXX XXXX
        d = d.slice(0, 10);
        const m = d.match(/^(\d{0,3})(\d{0,3})(\d{0,4})$/);
        return [m[1], m[2], m[3]].filter(Boolean).join(' ');
    }
    d = d.slice(0, 8);                        // Lesotho local: XXXX XXXX
    const m = d.match(/^(\d{0,4})(\d{0,4})$/);
    return [m[1], m[2]].filter(Boolean).join(' ');
};

// ============================================================================
// BRANDED UI: toasts + confirm dialog (shared by all app pages).
// Written in plain JS (React.createElement) so config.js stays node --check-able
// and no per-page JSX is needed. Replaces native alert()/confirm().
//   window.toast(message, 'success'|'error'|'info')
//   await window.confirmDialog({ message, title?, confirmLabel?, cancelLabel?, danger? })
// ============================================================================
(function () {
    if (typeof React === 'undefined' || typeof ReactDOM === 'undefined') return;
    const h = React.createElement;
    let pushToast = null, openConfirm = null;
    const BRAND = { success: '#15803d', error: '#dc2626', info: '#a16207' };

    function ToastHost() {
        const [items, setItems] = React.useState([]);
        React.useEffect(function () {
            pushToast = function (msg, type) {
                const id = Date.now() + '-' + Math.random();
                setItems(function (prev) { return prev.concat([{ id: id, msg: msg, type: type || 'info' }]); });
                setTimeout(function () {
                    setItems(function (prev) { return prev.filter(function (t) { return t.id !== id; }); });
                }, 3800);
            };
        }, []);
        return h('div', { style: { position: 'fixed', top: 16, left: 0, right: 0, zIndex: 9999, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, pointerEvents: 'none', padding: '0 12px' } },
            items.map(function (t) {
                const c = BRAND[t.type] || BRAND.info;
                const glyph = t.type === 'success' ? '✓' : t.type === 'error' ? '×' : 'i';
                return h('div', { key: t.id, className: 'slide-up', style: { pointerEvents: 'auto', maxWidth: 440, width: '100%', background: '#fff', color: '#111827', borderLeft: '4px solid ' + c, boxShadow: '0 10px 30px rgba(0,0,0,0.14)', borderRadius: 12, padding: '12px 16px', fontSize: 14, fontWeight: 500, fontFamily: 'Inter, sans-serif', display: 'flex', alignItems: 'center', gap: 11 } },
                    h('span', { style: { flexShrink: 0, width: 22, height: 22, borderRadius: '50%', background: c, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 14, lineHeight: 1 } }, glyph),
                    h('span', { style: { flex: 1 } }, t.msg)
                );
            })
        );
    }

    function ConfirmHost() {
        const [state, setState] = React.useState(null);
        React.useEffect(function () {
            openConfirm = function (opts) {
                return new Promise(function (resolve) {
                    setState(Object.assign({ title: '', message: '', confirmLabel: 'Confirm', cancelLabel: 'Cancel', danger: false }, opts, { resolve: resolve }));
                });
            };
        }, []);
        if (!state) return null;
        const close = function (val) { var r = state.resolve; setState(null); if (r) r(val); };
        return h('div', { style: { position: 'fixed', inset: 0, zIndex: 10000, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 }, onClick: function () { close(false); } },
            h('div', { className: 'modal-enter', onClick: function (e) { e.stopPropagation(); }, style: { background: '#fff', borderRadius: 16, maxWidth: 380, width: '100%', padding: 24, fontFamily: 'Inter, sans-serif', boxShadow: '0 20px 50px rgba(0,0,0,0.25)' } },
                state.title ? h('h3', { style: { fontSize: 18, fontWeight: 700, color: '#111827', marginBottom: 8 } }, state.title) : null,
                h('p', { style: { fontSize: 14.5, color: '#4b5563', lineHeight: 1.5, marginBottom: 22 } }, state.message),
                h('div', { style: { display: 'flex', gap: 10, justifyContent: 'flex-end' } },
                    h('button', { onClick: function () { close(false); }, style: { padding: '10px 18px', borderRadius: 10, border: '1px solid #e5e7eb', background: '#fff', color: '#374151', fontWeight: 600, fontSize: 14, cursor: 'pointer' } }, state.cancelLabel),
                    h('button', { onClick: function () { close(true); }, style: { padding: '10px 18px', borderRadius: 10, border: 'none', background: state.danger ? '#dc2626' : '#15803d', color: '#fff', fontWeight: 700, fontSize: 14, cursor: 'pointer' } }, state.confirmLabel)
                )
            )
        );
    }

    function mount() {
        if (document.getElementById('__yebo_ui_host')) return;
        const el = document.createElement('div');
        el.id = '__yebo_ui_host';
        document.body.appendChild(el);
        ReactDOM.createRoot(el).render(h(React.Fragment, null, h(ToastHost, null), h(ConfirmHost, null)));
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();

    window.toast = function (msg, type) { if (pushToast) pushToast(msg, type); else alert(msg); };
    window.confirmDialog = function (opts) {
        if (typeof opts === 'string') opts = { message: opts };
        if (openConfirm) return openConfirm(opts);
        return Promise.resolve(window.confirm((opts && opts.message) || 'Are you sure?'));
    };
})();
