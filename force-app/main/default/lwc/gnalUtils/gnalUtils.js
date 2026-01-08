/**
 * GNAL shared JavaScript utilities.
 *
 * Keep helpers here when they are used by multiple LWCs (formatting, parsing, etc.).
 */

/**
 * Normalizes a phone number for tel: links.
 * Keeps digits and an optional leading "+"; removes spaces, hyphens, parentheses, etc.
 */
export function normalizePhoneForTel(rawPhone) {
    const input = (rawPhone || '').trim();
    if (!input) {
        return '';
    }

    // Business rule: allow international dialing by preserving "+".
    return input.replace(/[^\d+]/g, '');
}

