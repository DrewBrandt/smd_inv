import 'package:flutter/material.dart';

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

/// Builds an image widget that handles both HTTPS URLs and base64 data URIs.
/// Shows [fallback] on error or if the data URI is malformed.
Widget buildBoardImage({
  required String imageUrl,
  required Widget fallback,
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  if (imageUrl.startsWith('data:')) {
    try {
      final uriData = UriData.parse(imageUrl);
      return Image.memory(
        uriData.contentAsBytes(),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, e, _) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }
  return Image.network(
    imageUrl,
    fit: fit,
    width: width,
    height: height,
    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
    errorBuilder: (_, e, _) => fallback,
  );
}
