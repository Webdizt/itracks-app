import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../../shared/widgets/main_scaffold.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _checkingSession = true;
  bool _obscurePassword = true;
  bool _rememberUsername = true;

  static const Color _brandBlue = Color(0xFF0E5FD8);
  static const Color _brandBlueSoft = Color(0xFFEAF3FF);
  static const Color _brandInk = Color(0xFF17324D);

  @override
  void initState() {
    super.initState();
    _bootstrapSession();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapSession() async {
    final preferences = await SharedPreferences.getInstance();
    final rememberedUsername =
        preferences.getString(AppConstants.rememberedUsernameKey)?.trim() ?? '';
    if (rememberedUsername.isNotEmpty) {
      _usernameController.text = rememberedUsername;
    }

    final hasSession = await AppAuthSession.hasActiveSession();
    if (!mounted) {
      return;
    }

    if (hasSession) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
      );
      return;
    }

    setState(() {
      _checkingSession = false;
    });
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    if (_rememberUsername) {
      await preferences.setString(
        AppConstants.rememberedUsernameKey,
        _usernameController.text.trim(),
      );
    } else {
      await preferences.remove(AppConstants.rememberedUsernameKey);
    }

    setState(() {
      _loading = true;
    });

    try {
      _logLogin('Starting login request for ${_usernameController.text.trim()}');
      _logLogin('Base URL: ${AppConstants.baseUrl}');
      _logLogin('Login endpoint: ${AppConstants.login}');
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          // Fail the first cold/unavailable connection quickly. A transient
          // failure is retried below, so users do not have to tap Login twice.
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 25),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (AppConstants.apiStaticToken.trim().isNotEmpty)
              'Authorization': 'Bearer ${AppConstants.apiStaticToken.trim()}',
          },
        ),
      );

      final response = await _postLoginWithRetry(dio);

      _logLogin('HTTP ${response.statusCode} received from ${AppConstants.login}');

      final body = _parseResponseBody(response.data);
      _logLogin('Response body keys: ${body.keys.toList()}');
      if (body['message'] != null) {
        _logLogin('Response message: ${body['message']}');
      }

      if (response.statusCode == 200 &&
          (body['status'] == true || body['data'] is Map)) {
        final user = _extractUser(body);
        final role = _extractRole(body, user);
        final token = _extractToken(body);
        final sessionId = _extractSessionId(body);
        final webSessionCookie = _extractWebSessionCookie(response);
        _logLogin(
          'Login success. user=${user['username'] ?? user['name'] ?? '-'}, '
          'role=$role, tokenSaved=${(token ?? '').isNotEmpty}, '
          'sessionSaved=${(sessionId ?? '').isNotEmpty}, '
          'cookieSaved=${(webSessionCookie ?? '').isNotEmpty}',
        );
        _logLogin('Resolved login token=${token ?? '-'} sessionId=${sessionId ?? '-'}');

        await AppAuthSession.clear();
        await AppAuthSession.storeLoginData(
          user: user,
          token: token,
          role: role,
          sessionId: sessionId,
          webSessionCookie: webSessionCookie,
        );

        if (!mounted) {
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScaffold()),
        );
        return;
      }

      final backendMessage = _resolveBackendFailureMessage(
        response.statusCode,
        body,
      );
      _logLogin('Login failed with backend message: $backendMessage');
      throw backendMessage;
    } on DioException catch (e) {
      _logLogin(
        'DioException type=${e.type} status=${e.response?.statusCode} '
        'message=${e.message}',
      );
      if (e.error != null) {
        _logLogin(
          'DioException innerErrorType=${e.error.runtimeType} '
          'innerError=${e.error}',
        );
      }
      if (e.response?.data != null) {
        _logLogin('DioException response: ${e.response?.data}');
      }
      _showError(_extractDioMessage(e));
    } catch (e) {
      _logLogin('Unexpected login error: $e');
      final message = e.toString().replaceFirst('Exception: ', '');
      _showError(message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<Response<dynamic>> _postLoginWithRetry(Dio dio) async {
    DioException? lastNetworkError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await dio.post(
          AppConstants.login,
          data: {
            'identity': _usernameController.text.trim(),
            'password': _passwordController.text,
          },
        );
      } on DioException catch (error) {
        lastNetworkError = error;
        final shouldRetry = attempt == 1 && _isTransientNetworkError(error);
        if (!shouldRetry) rethrow;
        _logLogin('Transient network failure on attempt $attempt. Retrying once.');
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    throw lastNetworkError!;
  }

  bool _isTransientNetworkError(DioException error) =>
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError;

  Map<String, dynamic> _extractUser(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      if (data['user'] is Map) {
        return Map<String, dynamic>.from(data['user'] as Map);
      }
      if (data['profile'] is Map) {
        return Map<String, dynamic>.from(data['profile'] as Map);
      }
      if (data.containsKey('username') || data.containsKey('name')) {
        return Map<String, dynamic>.from(data);
      }
    }

    return {
      'id': 0,
      'uuid': '',
      'username': _usernameController.text.trim(),
      'name': _usernameController.text.trim(),
      'role': 'user',
    };
  }

  String _extractRole(Map<String, dynamic> body, Map<String, dynamic> user) {
    final data = body['data'];
    if (user['role'] != null && '${user['role']}'.trim().isNotEmpty) {
      return '${user['role']}';
    }
    if (data is Map && data['role'] != null && '${data['role']}'.trim().isNotEmpty) {
      return '${data['role']}';
    }
    return 'user';
  }

  String? _extractToken(Map<String, dynamic> body) {
    final data = body['data'];
    if (body['token'] != null && '${body['token']}'.trim().isNotEmpty) {
      return '${body['token']}';
    }
    if (data is Map) {
      for (final key in ['token', 'api_token', 'access_token']) {
        final value = data[key];
        if (value != null && '$value'.trim().isNotEmpty) {
          return '$value';
        }
      }
    }

    final staticToken = AppConstants.apiStaticToken.trim();
    if (staticToken.isNotEmpty) {
      return staticToken;
    }
    return null;
  }

  String? _extractSessionId(Map<String, dynamic> body) {
    final data = body['data'];
    if (body['sess_id'] != null && '${body['sess_id']}'.trim().isNotEmpty) {
      return '${body['sess_id']}';
    }
    if (data is Map) {
      for (final key in ['sess_id', 'session_id', 'session', 'token']) {
        final value = data[key];
        if (value != null && '$value'.trim().isNotEmpty) {
          return '$value';
        }
      }
    }
    return null;
  }

  String? _extractWebSessionCookie(Response response) {
    final cookies = response.headers.map['set-cookie'];
    if (cookies == null || cookies.isEmpty) {
      return null;
    }

    final pairs = <String>[];
    for (final rawCookie in cookies) {
      final pair = rawCookie.split(';').first.trim();
      if (pair.isNotEmpty && pair.contains('=')) {
        pairs.add(pair);
      }
    }

    if (pairs.isEmpty) {
      return null;
    }

    return pairs.join('; ');
  }

  Map<String, dynamic> _parseResponseBody(dynamic rawData) {
    if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }

    if (rawData is String) {
      final cleaned = rawData.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
      _logLogin(
        'Raw response snippet: '
        '${cleaned.length > 300 ? cleaned.substring(0, 300) : cleaned}',
      );
      if (cleaned.isEmpty) {
        return <String, dynamic>{};
      }

      final decoded = jsonDecode(cleaned);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    return <String, dynamic>{};
  }

  String _resolveMessage(Map<String, dynamic> body, {required String fallback}) {
    final message = body['message'];
    if (message != null && '$message'.trim().isNotEmpty) {
      return '$message';
    }
    return fallback;
  }

  String _resolveBackendFailureMessage(
    int? statusCode,
    Map<String, dynamic> body,
  ) {
    final message = _resolveMessage(body, fallback: '');
    if (message.isNotEmpty) {
      switch (message.toLowerCase()) {
        case 'wrong':
          return 'Incorrect username or password.';
        case 'empty':
          return 'Username and password are required.';
        case 'invalid':
          return 'Invalid API token.';
        case 'no-access':
          return 'This user does not have access to the application.';
        case 'login-user-not-found':
          return 'The login user was not found in the system.';
      }
      return message;
    }

    if (statusCode != null) {
      return 'Login failed (HTTP $statusCode).';
    }

    return 'Login failed. Check your username and password.';
  }

  String _extractDioMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final mapped = Map<String, dynamic>.from(data);
      final message = mapped['message'];
      if (message != null && '$message'.trim().isNotEmpty) {
        return '$message';
      }
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server. Please try again shortly.';
    }

    final innerError = error.error;
    if (innerError is HandshakeException) {
      return 'HTTPS connection failed. There may be an SSL/TLS certificate issue.';
    }
    if (innerError is SocketException) {
      return 'Unable to reach the server. Check your network connection or server host.';
    }
    if (innerError is FormatException) {
      return 'The server response could not be read.';
    }

    if (error.response?.statusCode == 401) {
      return 'API authentication was rejected. Check the bearer token or login session.';
    }

    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return 'Login failed (HTTP $statusCode).';
    }

    return error.message ?? 'An unexpected login error occurred.';
  }

  void _logLogin(String message) {
    debugPrint('[LOGIN] $message');
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Login unsuccessful'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 12.h),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 92.w,
                      height: 92.w,
                      decoration: BoxDecoration(
                        color: _brandBlueSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.waves_rounded,
                            size: 42.r,
                            color: _brandBlue,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      'iTrack',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w700,
                        color: _brandBlue,
                      ),
                    ),
                    Text(
                      'Inventory & Delivery Note',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(22.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: const Color(0xFFDCEBFF)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x140E5FD8),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Username / Email'),
                      SizedBox(height: 8.h),
                      _buildTextField(
                        controller: _usernameController,
                        hintText: 'Enter username or email',
                        prefixIcon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username or email is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 18.h),
                      _buildFieldLabel('Password'),
                      SizedBox(height: 8.h),
                      _buildTextField(
                        controller: _passwordController,
                        hintText: 'Enter password',
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                        suffix: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      CheckboxListTile(
                        value: _rememberUsername,
                        onChanged: (value) {
                          setState(() {
                            _rememberUsername = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _brandBlue,
                        title: Text(
                          'Remember username',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: _brandInk,
                          ),
                        ),
                      ),
                      SizedBox(height: 14.h),
                      SizedBox(
                        width: double.infinity,
                        height: 54.h,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18.r),
                            ),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 22.w,
                                  height: 22.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        color: _brandInk,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(
        fontSize: 15.sp,
        color: _brandInk,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 14.sp,
          color: AppColors.textTertiary,
        ),
        prefixIcon: Icon(prefixIcon, color: _brandBlue),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(color: Color(0xFFDCEBFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(color: Color(0xFFDCEBFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(color: _brandBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}
