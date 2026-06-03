import 'package:cloud_functions/cloud_functions.dart';

import '../models/digikey_part_info.dart';

/// Thin client around the `digikeyLookup` callable Cloud Function.
///
/// The function holds the DigiKey OAuth credentials server-side, enforces the
/// 24h-per-part refresh window, and writes results to inventory docs /
/// `digikey_cache`. This wrapper never throws to the UI: on any failure
/// (function undeployed, missing secrets, auth/permission error, DigiKey
/// outage) it returns whatever it could resolve — typically an empty map — so
/// the purchase planner keeps working with existing data.
class DigiKeyApiService {
  final FirebaseFunctions _functions;

  DigiKeyApiService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  static const String _callableName = 'digikeyLookup';

  Future<Map<String, DigiKeyPartInfo>> lookupParts(
    List<DigiKeyLookupRequest> requests, {
    int maxAgeHours = 24,
  }) async {
    if (requests.isEmpty) return const <String, DigiKeyPartInfo>{};

    try {
      final callable = _functions.httpsCallable(_callableName);
      final response = await callable.call<Map<String, dynamic>>({
        'parts': requests.map((r) => r.toJson()).toList(),
        'maxAgeHours': maxAgeHours,
      });

      final results = response.data['results'];
      if (results is! Map) return const <String, DigiKeyPartInfo>{};

      final out = <String, DigiKeyPartInfo>{};
      results.forEach((key, value) {
        if (value is Map) {
          out['$key'] = DigiKeyPartInfo.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
      return out;
    } on FirebaseFunctionsException {
      // Undeployed function, missing secrets, or permission-denied — degrade
      // gracefully; the planner still renders existing data.
      return const <String, DigiKeyPartInfo>{};
    } catch (_) {
      return const <String, DigiKeyPartInfo>{};
    }
  }
}
