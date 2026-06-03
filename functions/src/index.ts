/**
 * Cloud Function: digikeyLookup
 *
 * A callable proxy for the DigiKey Product Information API (v4). It exists
 * because:
 *  - the Flutter app ships a web build, and DigiKey's API sends no CORS
 *    headers, so the browser cannot call it directly;
 *  - DigiKey uses a confidential client_id/secret that must never reach the
 *    client.
 *
 * The function holds the credentials as secrets, restricts access to the same
 * UMD accounts as the Firestore rules, enforces a per-part 24h refresh window,
 * and writes results back to inventory docs (or a `digikey_cache` collection
 * for parts that have no inventory document).
 */
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

const DIGIKEY_CLIENT_ID = defineSecret("DIGIKEY_CLIENT_ID");
const DIGIKEY_CLIENT_SECRET = defineSecret("DIGIKEY_CLIENT_SECRET");

// Override to "https://sandbox-api.digikey.com" while testing.
const BASE_URL = process.env.DIGIKEY_BASE_URL ?? "https://api.digikey.com";
const ALLOWED_EMAIL = /(@umd\.edu|@terpmail\.umd\.edu)$/i;

interface NormalizedInfo {
  digiKeyPartNumber: string | null;
  manufacturerProductNumber: string | null;
  description: string | null;
  unitPrice: number | null;
  productUrl: string | null;
  datasheetUrl: string | null;
  packageCase: string | null;
  quantityAvailable: number | null;
}

type LookupResult = NormalizedInfo | { notFound: true };

// ---------------------------------------------------------------------------
// OAuth (client_credentials) — token cached in module memory across warm calls
// ---------------------------------------------------------------------------
let cachedToken: { value: string; expiresAt: number } | null = null;

async function getToken(clientId: string, clientSecret: string): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.value;
  }
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
  });
  const res = await fetch(`${BASE_URL}/v1/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!res.ok) {
    throw new HttpsError("internal", `DigiKey auth failed (${res.status})`);
  }
  const json = (await res.json()) as { access_token: string; expires_in?: number };
  const expiresIn = json.expires_in ?? 600;
  cachedToken = { value: json.access_token, expiresAt: now + expiresIn * 1000 };
  return cachedToken.value;
}

function dkHeaders(token: string, clientId: string): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    "X-DIGIKEY-Client-Id": clientId,
    "X-DIGIKEY-Locale-Site": "US",
    "X-DIGIKEY-Locale-Language": "en",
    "X-DIGIKEY-Locale-Currency": "USD",
    "Content-Type": "application/json",
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function fetchByDkPn(dkPn: string, token: string, clientId: string): Promise<any | null> {
  const url = `${BASE_URL}/products/v4/search/${encodeURIComponent(dkPn)}/productdetails`;
  const res = await fetch(url, { headers: dkHeaders(token, clientId) });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`productdetails failed (${res.status})`);
  const json = (await res.json()) as { Product?: unknown };
  return json.Product ?? null;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function fetchByKeyword(mpn: string, token: string, clientId: string): Promise<any | null> {
  const url = `${BASE_URL}/products/v4/search/keyword`;
  const res = await fetch(url, {
    method: "POST",
    headers: dkHeaders(token, clientId),
    body: JSON.stringify({ Keywords: mpn, Limit: 1 }),
  });
  if (!res.ok) throw new Error(`keyword search failed (${res.status})`);
  const json = (await res.json()) as { Products?: unknown[] };
  const products = json.Products ?? [];
  return products.length > 0 ? products[0] : null;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function normalize(product: any): NormalizedInfo {
  const variations = product?.ProductVariations ?? [];
  const dkPn =
    variations.length > 0
      ? variations[0]?.DigiKeyProductNumber
      : product?.DigiKeyProductNumber;
  const params = product?.Parameters ?? [];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const pkg = params.find((p: any) => p?.ParameterText === "Package / Case");
  return {
    digiKeyPartNumber: dkPn ?? null,
    manufacturerProductNumber: product?.ManufacturerProductNumber ?? null,
    description: product?.Description?.ProductDescription ?? null,
    unitPrice: typeof product?.UnitPrice === "number" ? product.UnitPrice : null,
    productUrl: product?.ProductUrl ?? null,
    datasheetUrl: product?.DatasheetUrl ?? null,
    packageCase: pkg?.ValueText ?? null,
    quantityAvailable:
      typeof product?.QuantityAvailable === "number" ? product.QuantityAvailable : null,
  };
}

// ---------------------------------------------------------------------------
// Firestore cache (inventory doc for backed parts; digikey_cache otherwise)
// ---------------------------------------------------------------------------
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function readCached(d: any, fromInventory: boolean): LookupResult {
  if (d.notFound === true) return { notFound: true };
  if (fromInventory) {
    return {
      digiKeyPartNumber: d["digikey_part_#"] ?? null,
      manufacturerProductNumber: d["part_#"] ?? null,
      description: d.description ?? null,
      unitPrice: typeof d.price_per_unit === "number" ? d.price_per_unit : null,
      productUrl: d.vendor_link ?? null,
      datasheetUrl: d.datasheet ?? null,
      packageCase: d.package ?? null,
      quantityAvailable: typeof d.digikey_stock === "number" ? d.digikey_stock : null,
    };
  }
  return {
    digiKeyPartNumber: d.digiKeyPartNumber ?? null,
    manufacturerProductNumber: d.manufacturerProductNumber ?? null,
    description: d.description ?? null,
    unitPrice: typeof d.unitPrice === "number" ? d.unitPrice : null,
    productUrl: d.productUrl ?? null,
    datasheetUrl: d.datasheetUrl ?? null,
    packageCase: d.packageCase ?? null,
    quantityAvailable: typeof d.quantityAvailable === "number" ? d.quantityAvailable : null,
  };
}

async function writeBack(
  ref: FirebaseFirestore.DocumentReference,
  fromInventory: boolean,
  info: NormalizedInfo,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  existing: any | undefined,
): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();
  if (fromInventory) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const update: any = { digikey_fetched_at: now };
    // Overwrite volatile / DigiKey-owned values on every refresh.
    if (typeof info.unitPrice === "number") update.price_per_unit = info.unitPrice;
    if (typeof info.quantityAvailable === "number") update.digikey_stock = info.quantityAvailable;
    // Fill stable identity fields only when the inventory doc has none, so we
    // never clobber curated values.
    const fillIfEmpty = (field: string, value: string | null) => {
      if (!value) return;
      const cur = existing?.[field];
      if (cur === undefined || cur === null || String(cur).trim() === "") {
        update[field] = value;
      }
    };
    fillIfEmpty("digikey_part_#", info.digiKeyPartNumber);
    fillIfEmpty("vendor_link", info.productUrl);
    fillIfEmpty("datasheet", info.datasheetUrl);
    fillIfEmpty("description", info.description);
    await ref.set(update, { merge: true });
  } else {
    await ref.set({ ...info, notFound: false, fetched_at: now }, { merge: true });
  }
}

async function writeNegative(
  ref: FirebaseFirestore.DocumentReference,
  fromInventory: boolean,
): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();
  if (fromInventory) {
    // No clean way to flag "not found" on an inventory doc; just stamp the
    // refresh time so we don't re-query for the next window.
    await ref.set({ digikey_fetched_at: now }, { merge: true });
  } else {
    await ref.set({ notFound: true, fetched_at: now }, { merge: true });
  }
}

interface PartRequest {
  key?: string;
  dkPn?: string;
  mpn?: string;
  inventoryDocId?: string;
  forceRefresh?: boolean;
}

async function resolvePart(
  part: PartRequest,
  key: string,
  maxAgeMs: number,
  clientId: string,
  clientSecret: string,
): Promise<LookupResult> {
  const inventoryDocId = part.inventoryDocId ? String(part.inventoryDocId) : null;
  const fromInventory = inventoryDocId !== null;
  const ref = fromInventory
    ? db.collection("inventory").doc(inventoryDocId as string)
    : db.collection("digikey_cache").doc(key.toUpperCase());

  // 1. Freshness check (skipped when the caller forces a refresh, e.g. the
  //    user just set/corrected the part number).
  const snap = await ref.get();
  const existing = snap.exists ? snap.data() : undefined;
  if (existing && part.forceRefresh !== true) {
    const ts = fromInventory ? existing.digikey_fetched_at : existing.fetched_at;
    const fetchedMs = ts && typeof ts.toMillis === "function" ? ts.toMillis() : 0;
    if (fetchedMs && Date.now() - fetchedMs < maxAgeMs) {
      return readCached(existing, fromInventory);
    }
  }

  // 2. Call DigiKey: prefer the DK part number, else resolve via the MPN.
  const token = await getToken(clientId, clientSecret);
  const dkPn = part.dkPn ? String(part.dkPn) : null;
  const mpn = part.mpn ? String(part.mpn) : null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let product: any | null = null;
  if (dkPn) product = await fetchByDkPn(dkPn, token, clientId);
  if (!product && mpn) product = await fetchByKeyword(mpn, token, clientId);

  if (!product) {
    await writeNegative(ref, fromInventory);
    return { notFound: true };
  }

  const info = normalize(product);
  await writeBack(ref, fromInventory, info, existing);
  return info;
}

export const digikeyLookup = onCall(
  { secrets: [DIGIKEY_CLIENT_ID, DIGIKEY_CLIENT_SECRET], maxInstances: 3 },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async (request: CallableRequest<any>) => {
    // Auth: signed-in AND a UMD account (mirrors firestore.rules isEditorEmail).
    const email = request.auth?.token?.email as string | undefined;
    if (!request.auth || !email || !ALLOWED_EMAIL.test(email)) {
      throw new HttpsError("permission-denied", "Not authorized for DigiKey lookups.");
    }

    const data = request.data ?? {};
    const parts: PartRequest[] = Array.isArray(data.parts) ? data.parts : [];
    const maxAgeHours = typeof data.maxAgeHours === "number" ? data.maxAgeHours : 24;
    const maxAgeMs = maxAgeHours * 3_600_000;

    const clientId = DIGIKEY_CLIENT_ID.value();
    const clientSecret = DIGIKEY_CLIENT_SECRET.value();

    const results: Record<string, LookupResult> = {};
    for (const part of parts) {
      const key = String(part.key ?? "").trim();
      if (!key || results[key]) continue;
      try {
        results[key] = await resolvePart(part, key, maxAgeMs, clientId, clientSecret);
      } catch (err) {
        // One failure shouldn't sink the batch; the client keeps existing data.
        logger.error(`DigiKey lookup failed for "${key}"`, err);
      }
    }
    return { results };
  },
);
