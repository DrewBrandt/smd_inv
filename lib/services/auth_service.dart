import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static bool Function(User?)? canEditOverride;
  static FirebaseAuth? Function()? authOverride;
  static GoogleAuthProvider Function()? googleProviderOverride;

  static const Set<String> allowedEditorDomains = {
    'umd.edu',
    'terpmail.umd.edu',
  };

  static FirebaseAuth? _safeAuth() {
    try {
      final override = authOverride;
      if (override != null) return override();
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  static Stream<User?> authStateChanges() {
    final auth = _safeAuth();
    if (auth == null) return Stream<User?>.value(null);
    return auth.authStateChanges();
  }

  static User? get currentUser => _safeAuth()?.currentUser;

  static bool canEdit(User? user) {
    final override = canEditOverride;
    if (override != null) return override(user);
    return canEditEmail(user?.email);
  }

  static bool canEditEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final parts = email.trim().toLowerCase().split('@');
    if (parts.length != 2) return false;
    return allowedEditorDomains.contains(parts.last);
  }

  static Future<UserCredential> signInWithGoogle() async {
    final auth = _safeAuth();
    if (auth == null) {
      throw StateError('Firebase is not initialized.');
    }
    final providerFactory = googleProviderOverride;
    final provider =
        (providerFactory != null ? providerFactory() : GoogleAuthProvider())
          ..addScope('email')
          ..setCustomParameters({'prompt': 'select_account'});

    if (kIsWeb) {
      return auth.signInWithPopup(provider);
    }
    return auth.signInWithProvider(provider);
  }

  static Future<void> signOut() async {
    final auth = _safeAuth();
    if (auth == null) return;
    await auth.signOut();
  }

  static String editorPolicySummary() {
    return 'Editors must sign in with @umd.edu or @terpmail.umd.edu.';
  }
}
