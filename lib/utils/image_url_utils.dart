Uri? parseBoardImageUri(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final withScheme =
      _hasUriScheme(trimmed) || trimmed.startsWith('data:')
          ? trimmed
          : 'https://$trimmed';
  final encoded = Uri.encodeFull(withScheme);
  final uri = Uri.tryParse(encoded);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme == 'data') return uri;
  if ((uri.host).isEmpty) return null;
  return uri;
}

String? normalizeBoardImageUrl(String? raw) => parseBoardImageUri(raw)?.toString();

bool _hasUriScheme(String value) =>
    RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(value);
