import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static bool Function(User?)? canEditOverride;
  static FirebaseAuth? Function()? authOverride;
  static GoogleAuthProvider Function()? googleProviderOverride;
  static bool Function()? isWebOverride;
  static TargetPlatform Function()? targetPlatformOverride;

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

  static bool get _isWebPlatform => isWebOverride?.call() ?? kIsWeb;

  static TargetPlatform get _targetPlatform =>
      targetPlatformOverride?.call() ?? defaultTargetPlatform;

  static bool get supportsGoogleSignIn {
    if (_isWebPlatform) return true;

    switch (_targetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return false;
      default:
        return false;
    }
  }

  static String googleSignInSupportSummary() {
    if (_isWebPlatform) {
      return 'Google sign-in is supported in the web app.';
    }

    switch (_targetPlatform) {
      case TargetPlatform.windows:
        return 'Google sign-in is supported in the Windows build.';
      case TargetPlatform.macOS:
        return 'Google sign-in is not supported in the macOS build yet. Use the web app for now.';
      case TargetPlatform.linux:
        return 'Google sign-in is not configured for the Linux build.';
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'Google sign-in is supported on this device.';
      default:
        return 'Google sign-in is not supported on this platform.';
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

  static Future<UserCredential?> signInWithGoogle() async {
    final auth = _safeAuth();
    if (auth == null) {
      throw StateError('Firebase is not initialized.');
    }
    if (!supportsGoogleSignIn) {
      throw UnsupportedError(googleSignInSupportSummary());
    }
    final provider =
        (googleProviderOverride != null
            ? googleProviderOverride!()
            : GoogleAuthProvider());

    if (_isWebPlatform) {
      provider
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
    }

    if (_isWebPlatform) {
      try {
        return await auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (_shouldUseRedirectFallback(e)) {
          await auth.signInWithRedirect(provider);
          return null;
        }
        rethrow;
      }
    }
    return auth.signInWithProvider(provider);
  }

  static bool _shouldUseRedirectFallback(FirebaseAuthException error) {
    const redirectFallbackCodes = {
      'popup-blocked',
      'operation-not-supported-in-this-environment',
      'web-context-cancelled',
    };

    return redirectFallbackCodes.contains(error.code);
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
