class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;

  factory AuthTokens.fromJson(
    Map<String, dynamic> json, {
    String? fallbackRefreshToken,
  }) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw const FormatException('Auth response is missing an access token');
    }

    final refreshToken =
        (json['refresh_token'] as String?) ?? fallbackRefreshToken;
    if (refreshToken == null) {
      throw const FormatException('Auth response is missing a refresh token');
    }

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }
}
