import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


CSV_HEADERS = [
    "part_#",
    "type",
    "value",
    "package",
    "description",
    "qty",
    "location",
    "price_per_unit",
    "notes",
    "vendor_link",
    "datasheet",
]

TOKEN_URL = "https://api.digikey.com/v1/oauth2/token"
PRODUCT_DETAILS_URL = "https://{host}/products/v4/search/{product_number}/productdetails"
KEYWORD_SEARCH_URL = "https://{host}/products/v4/search/keyword"
DEFAULT_HOST = "api.digikey.com"
SANDBOX_HOST = "sandbox-api.digikey.com"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read DigiKey part numbers from a text file and build an inventory CSV "
            "using DigiKey Product Information V4."
        )
    )
    parser.add_argument(
        "-i",
        "--input",
        default="ICs.txt",
        help="Path to a text file containing one DigiKey part number per line.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="ics_from_digikey.csv",
        help="Path to the CSV file to write.",
    )
    parser.add_argument(
        "--site",
        default="US",
        help="DigiKey locale site header value. Default: US",
    )
    parser.add_argument(
        "--language",
        default="en",
        help="DigiKey locale language header value. Default: en",
    )
    parser.add_argument(
        "--currency",
        default="USD",
        help="DigiKey locale currency header value. Default: USD",
    )
    parser.add_argument(
        "--sandbox",
        action="store_true",
        help="Use DigiKey sandbox endpoints instead of production.",
    )
    return parser.parse_args()


def get_required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if value:
        return value
    raise SystemExit(
        f"Missing required environment variable: {name}\n"
        "Set DigiKey credentials before running this script."
    )


def read_part_numbers(path: str) -> list[str]:
    seen: set[str] = set()
    part_numbers: list[str] = []

    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            part_number = raw_line.strip()
            if not part_number or part_number in seen:
                continue
            seen.add(part_number)
            part_numbers.append(part_number)

    if not part_numbers:
        raise SystemExit(f"No DigiKey part numbers found in {path}.")

    return part_numbers


def format_price(value: Any) -> str:
    if value in (None, ""):
        return ""
    if isinstance(value, str):
        return value.strip()
    text = f"{float(value):.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
) -> dict[str, Any]:
    request = urllib.request.Request(url=url, data=body, method=method)
    for key, value in (headers or {}).items():
        request.add_header(key, value)

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read().decode("utf-8")
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        retry_after = exc.headers.get("Retry-After")
        message = f"HTTP {exc.code} for {url}"
        if details:
            message = f"{message}\n{details}"
        if retry_after:
            message = f"{message}\nRetry-After: {retry_after}"
        raise RuntimeError(message) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error while requesting {url}: {exc}") from exc


class DigiKeyClient:
    def __init__(
        self,
        *,
        client_id: str,
        client_secret: str,
        account_id: str,
        site: str,
        language: str,
        currency: str,
        sandbox: bool,
    ) -> None:
        self.client_id = client_id
        self.client_secret = client_secret
        self.account_id = account_id
        self.site = site
        self.language = language
        self.currency = currency
        self.sandbox = sandbox
        self.host = SANDBOX_HOST if sandbox else DEFAULT_HOST
        self._token: str | None = None
        self._token_expires_at = 0.0

    def _api_headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._get_access_token()}",
            "X-DIGIKEY-Client-Id": self.client_id,
            "X-DIGIKEY-Locale-Site": self.site,
            "X-DIGIKEY-Locale-Language": self.language,
            "X-DIGIKEY-Locale-Currency": self.currency,
            "X-DIGIKEY-Account-Id": self.account_id,
        }

    def _get_access_token(self) -> str:
        now = time.time()
        if self._token and now < self._token_expires_at - 30:
            return self._token

        body = urllib.parse.urlencode(
            {
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "grant_type": "client_credentials",
            }
        ).encode("utf-8")

        token_url = TOKEN_URL
        if self.sandbox:
            token_url = token_url.replace(DEFAULT_HOST, SANDBOX_HOST)

        payload = request_json(
            token_url,
            method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            body=body,
        )

        access_token = payload.get("access_token")
        expires_in = int(payload.get("expires_in", 0))
        if not access_token:
            raise RuntimeError("DigiKey token response did not include an access_token.")

        self._token = str(access_token)
        self._token_expires_at = now + expires_in
        return self._token

    def get_product_details(self, digi_key_part_number: str) -> dict[str, Any]:
        encoded_part = urllib.parse.quote(digi_key_part_number, safe="")
        url = PRODUCT_DETAILS_URL.format(
            host=self.host,
            product_number=encoded_part,
        )
        return request_json(url, headers=self._api_headers())

    def keyword_search(self, keywords: str) -> dict[str, Any]:
        url = KEYWORD_SEARCH_URL.format(host=self.host)
        body = json.dumps(
            {
                "Keywords": keywords,
                "Limit": 10,
                "Offset": 0,
            }
        ).encode("utf-8")
        headers = self._api_headers()
        headers["Content-Type"] = "application/json"
        return request_json(url, method="POST", headers=headers, body=body)

    def get_best_product(self, digi_key_part_number: str) -> dict[str, Any]:
        exact_error: Exception | None = None
        try:
            details_payload = self.get_product_details(digi_key_part_number)
            product = extract_product(details_payload)
            if product:
                return product
        except Exception as exc:
            exact_error = exc

        search_terms = build_search_terms(digi_key_part_number)
        for term in search_terms:
            try:
                search_payload = self.keyword_search(term)
                product = pick_product_from_search(search_payload, digi_key_part_number)
                if product:
                    return product
            except Exception:
                continue

        if exact_error is not None:
            raise exact_error
        raise RuntimeError(
            f"Unable to resolve DigiKey part number {digi_key_part_number} via ProductDetails or KeywordSearch."
        )


def normalize_digi_key_part_number(value: str | None) -> str:
    if not value:
        return ""
    return value.strip().upper()


def extract_product(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {}

    if payload.get("ManufacturerProductNumber"):
        return payload

    nested = payload.get("Product")
    if isinstance(nested, dict) and nested.get("ManufacturerProductNumber"):
        return nested

    return {}


def product_candidate_numbers(product: dict[str, Any]) -> set[str]:
    candidates: set[str] = set()

    for key in ("DigiKeyProductNumber", "ProductNumber"):
        value = normalize_digi_key_part_number(str(product.get(key, "")).strip())
        if value:
            candidates.add(value)

    product_url = str(product.get("ProductUrl", "")).strip()
    if product_url:
        parsed = urllib.parse.urlparse(product_url)
        for segment in parsed.path.split("/"):
            value = normalize_digi_key_part_number(segment)
            if value.endswith("-ND"):
                candidates.add(value)

    return candidates


def pick_product_from_search(
    payload: dict[str, Any],
    requested_part_number: str,
) -> dict[str, Any]:
    requested = normalize_digi_key_part_number(requested_part_number)
    products = payload.get("Products") or []
    if not isinstance(products, list):
        return {}

    unwrapped_products = [extract_product(product) for product in products]
    unwrapped_products = [product for product in unwrapped_products if product]
    if not unwrapped_products:
        return {}

    for product in unwrapped_products:
        if requested in product_candidate_numbers(product):
            return product

    return unwrapped_products[0]


def build_search_terms(digi_key_part_number: str) -> list[str]:
    term = digi_key_part_number.strip()
    if not term:
        return []

    variants = [term]

    upper_term = term.upper()
    for suffix in ("CT-ND", "TR-ND", "DKR-ND"):
        if upper_term.endswith(suffix):
            variants.append(term[: -len(suffix)] + "-ND")
            break

    return list(dict.fromkeys(v for v in variants if v))


def pick_description(product: dict[str, Any], manufacturer_part_number: str) -> str:
    description = product.get("Description") or {}
    return (
        (description.get("DetailedDescription") or "").strip()
        or (description.get("ProductDescription") or "").strip()
        or manufacturer_part_number
    )


def find_parameter_value(product: dict[str, Any], candidates: list[str]) -> str:
    wanted = {candidate.casefold() for candidate in candidates}
    for parameter in product.get("Parameters") or []:
        name = str(parameter.get("ParameterText", "")).strip().casefold()
        value = str(parameter.get("ValueText", "")).strip()
        if name in wanted and value:
            return value
    return ""


def pick_package(product: dict[str, Any]) -> str:
    parameter_package = find_parameter_value(
        product,
        [
            "Package / Case",
            "Package / Case (Supplier Device Package)",
            "Supplier Device Package",
        ],
    )
    if parameter_package:
        return parameter_package

    variations = product.get("ProductVariations") or []
    for variation in variations:
        package_type = variation.get("PackageType") or {}
        name = str(package_type.get("Name", "")).strip()
        if name:
            return name

    return ""


def pick_unit_price(product: dict[str, Any]) -> str:
    direct_price = product.get("UnitPrice")
    if direct_price not in (None, ""):
        return format_price(direct_price)

    for variation in product.get("ProductVariations") or []:
        for pricing_key in ("MyPricing", "StandardPricing"):
            for price_break in variation.get(pricing_key) or []:
                unit_price = price_break.get("UnitPrice")
                if unit_price not in (None, ""):
                    return format_price(unit_price)

    return ""


def build_row(product: dict[str, Any]) -> dict[str, str]:
    manufacturer_part_number = str(product.get("ManufacturerProductNumber", "")).strip()
    if not manufacturer_part_number:
        raise RuntimeError("Product response did not include ManufacturerProductNumber.")

    return {
        "part_#": manufacturer_part_number,
        "type": "ic",
        "value": "",
        "package": pick_package(product),
        "description": pick_description(product, manufacturer_part_number),
        "qty": "",
        "location": "",
        "price_per_unit": pick_unit_price(product),
        "notes": "",
        "vendor_link": str(product.get("ProductUrl", "")).strip(),
        "datasheet": str(product.get("DatasheetUrl", "")).strip(),
    }


def write_csv(path: str, rows: list[dict[str, str]]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_HEADERS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    args = parse_args()
    part_numbers = read_part_numbers(args.input)

    client = DigiKeyClient(
        client_id=get_required_env("DIGIKEY_CLIENT_ID"),
        client_secret=get_required_env("DIGIKEY_CLIENT_SECRET"),
        account_id=get_required_env("DIGIKEY_ACCOUNT_ID"),
        site=args.site,
        language=args.language,
        currency=args.currency,
        sandbox=args.sandbox,
    )

    rows: list[dict[str, str]] = []
    failures: list[tuple[str, str]] = []

    for index, digi_key_part_number in enumerate(part_numbers, start=1):
        print(f"[{index}/{len(part_numbers)}] Looking up {digi_key_part_number}...")
        try:
            product = client.get_best_product(digi_key_part_number)
            rows.append(build_row(product))
        except Exception as exc:
            failures.append((digi_key_part_number, str(exc)))

    write_csv(args.output, rows)

    print(f"\nWrote {len(rows)} rows to {args.output}")

    if failures:
        print("\nThe following part numbers could not be processed:", file=sys.stderr)
        for part_number, error in failures:
            print(f"- {part_number}: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
