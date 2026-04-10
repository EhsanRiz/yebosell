// ============================================================================
// WhatsApp Seller OS — Shared Configuration
// ============================================================================

// ============================================================================
// WhatsApp Seller OS — Shared Configuration
// All vars attached to window so Babel-transpiled scripts can access them
// ============================================================================

window.SUPABASE_URL = 'https://nizrqwvfuxbuhertypva.supabase.co';
window.SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5penJxd3ZmdXhidWhlcnR5cHZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3NTg3MjMsImV4cCI6MjA5MTMzNDcyM30.nqduzFlkaYWq2kYYFQysb8nBU_l1Eom88uoS7l6pkCw';
window.SITE_URL = window.location.origin || 'https://selleros.co.za';

// Convenience aliases for non-Babel scripts
const SUPABASE_URL = window.SUPABASE_URL;
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY;
const SITE_URL = window.SITE_URL;

// Initialize Supabase
window.supabaseClient = null;
try {
    window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
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

window.formatCurrency = (amount) => `R${parseFloat(amount || 0).toFixed(2)}`;

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
        preparing: '#6b7280', failed: '#ef4444', screenshot_uploaded: '#f59e0b',
        confirmed: '#10b981', rejected: '#ef4444'
    };
    return map[status] || '#6b7280';
};

window.getStatusLabel = (status) => {
    return (status || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
};

// WhatsApp deep link helper
window.whatsappLink = (phone, message) => {
    const cleanPhone = phone.replace(/[^0-9+]/g, '');
    return `https://wa.me/${cleanPhone}?text=${encodeURIComponent(message)}`;
};

// WhatsApp share link (for sharing to groups)
window.whatsappShareLink = (message) => {
    return `https://wa.me/?text=${encodeURIComponent(message)}`;
};
