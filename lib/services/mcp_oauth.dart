import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nova_assistant/utils/secure_prefs.dart';

/// Minimal OAuth 2.0 Authorization Code + PKCE helper for MCP servers.
class McpOAuthService {
  static McpOAuthService? _instance;
  static McpOAuthService get instance => _instance ??= McpOAuthService._();
  McpOAuthService._();

  static const _tokenKeyPrefix = 'mcp_oauth_token_';
  static const _refreshKeyPrefix = 'mcp_oauth_refresh_';
  static const _pkceKeyPrefix = 'mcp_oauth_pkce_';

  /// Generate a PKCE code verifier / challenge pair.
  ({String verifier, String challenge}) createPkce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final verifier = base64UrlEncode(bytes).replaceAll('=', '');
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');

    return (verifier: verifier, challenge: challenge);
  }

  Future<void> savePkceVerifier(String serverId, String verifier) async {
    await SecurePrefs().write('$_pkceKeyPrefix$serverId', verifier);
  }

  Future<String?> loadPkceVerifier(String serverId) async {
    return SecurePrefs().read('$_pkceKeyPrefix$serverId');
  }

  Future<void> saveTokens({
    required String serverId,
    required String accessToken,
    String? refreshToken,
  }) async {
    await SecurePrefs().write('$_tokenKeyPrefix$serverId', accessToken);
    if (refreshToken != null) {
      await SecurePrefs().write('$_refreshKeyPrefix$serverId', refreshToken);
    }
  }

  Future<String?> loadAccessToken(String serverId) async {
    return SecurePrefs().read('$_tokenKeyPrefix$serverId');
  }

  Future<void> clearTokens(String serverId) async {
    await SecurePrefs().delete('$_tokenKeyPrefix$serverId');
    await SecurePrefs().delete('$_refreshKeyPrefix$serverId');
    await SecurePrefs().delete('$_pkceKeyPrefix$serverId');
  }

  /// Build an authorization URL with PKCE and open it in the browser.
  Future<bool> openAuthorizationUrl({
    required String authorizationEndpoint,
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    String? scope,
    String? state,
  }) async {
    final uri = Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        // ignore: use_null_aware_elements
        if (scope != null && scope.isNotEmpty) 'scope': scope,
        // ignore: use_null_aware_elements
        if (state != null) 'state': state,
      },
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('McpOAuthService.openAuthorizationUrl error: $e');

      return false;
    }
  }

  /// Exchange an authorization code for tokens.
  Future<Map<String, dynamic>?> exchangeCode({
    required String tokenEndpoint,
    required String clientId,
    required String redirectUri,
    required String code,
    required String codeVerifier,
    String? clientSecret,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(tokenEndpoint);
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      final fields = <String, String>{
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code': code,
        'code_verifier': codeVerifier,
        // ignore: use_null_aware_elements
        if (clientSecret != null) 'client_secret': clientSecret,
      };
      request.write(
        fields.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}='
                  '${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('OAuth token exchange failed: ${response.statusCode} $body');

        return null;
      }

      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('McpOAuthService.exchangeCode error: $e');

      return null;
    } finally {
      client.close(force: true);
    }
  }
}
