import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../utils/session_storage.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'socket_service.dart';
import 'push_notification_service.dart';
import '../utils/app_logger.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  final PushNotificationService _pushNotificationService =
      PushNotificationService();

  bool _isAuthenticated = false;
  String? _userRole;
  String? _userPhotoUrl;
  String? _userName;
  String? _userEmail;
  String? _userCompany;
  String? _membershipNumber;
  String? _licenseNumber;
  String _membershipStatus = 'none';
  bool _goodStanding = false;
  bool _registrationFeePaid = false;
  List<String> _permissions = [];
  bool _notificationsInitialized = false;

  bool get isAuthenticated => _isAuthenticated;
  String? get userRole => _userRole;
  String? get userPhotoUrl => _userPhotoUrl;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get userCompany => _userCompany;
  String? get membershipNumber => _membershipNumber;
  String? get licenseNumber => _licenseNumber;
  String get membershipStatus => _membershipStatus;
  bool get goodStanding => _goodStanding;
  bool get isRegistrationFeePaid => _registrationFeePaid;
  List<String> get permissions => _permissions;

  // 3 Access Levels & Role Hierarchy getters
  bool get isRegisteredUser => _isAuthenticated;
  bool get isApplicant =>
      _membershipStatus.toLowerCase() == 'pending' ||
      _membershipStatus.toLowerCase() == 'pending_review' ||
      _membershipStatus.toLowerCase() == 'under_review';
  bool get isApprovedMember =>
      _userRole == 'admin' ||
      _userRole == 'sub_admin' ||
      _userRole == 'super_admin' ||
      _membershipStatus.toLowerCase() == 'active' ||
      _membershipStatus.toLowerCase() == 'approved';
  bool get isGoodStandingMember => isApprovedMember && _goodStanding;

  bool hasPermission(String key) {
    if (_userRole == 'admin' || _userRole == 'super_admin') return true;
    return _permissions.contains(key);
  }

  Future<void> updatePhoto(String url) async {
    _userPhotoUrl = url;
    await SessionStorage.instance.setString('cubag_photo', url);
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    final token = await SessionStorage.instance.getString('cubag_token');
    _userRole = await SessionStorage.instance.getString('cubag_role');
    _userPhotoUrl = await SessionStorage.instance.getString('cubag_photo');
    _userName = await SessionStorage.instance.getString('cubag_name');
    _userEmail = await SessionStorage.instance.getString('cubag_email');
    _membershipStatus = (await SessionStorage.instance.getString('cubag_member_status') ??
            await SessionStorage.instance.getString('cubag_status') ??
            'none')
        .toLowerCase()
        .trim();
    _registrationFeePaid =
        (await SessionStorage.instance.getString('cubag_registration_fee_paid')) == 'true';
    _permissions =
        await SessionStorage.instance.getStringList('cubag_permissions') ?? [];

    if (token != null) {
      _isAuthenticated = true;
      _initServices();
      if (_userRole == 'member') {
        // Refresh profile status non-blockingly so cold startup is instant
        unawaited(_refreshMemberStatusFromProfile());
      }
    }
    notifyListeners();
  }

  void _initServices() {
    _socketService.initSocket();

    _socketService.socket?.on('member_updated', (_) => _refreshMemberStatusFromProfile());
    _socketService.socket?.on('payment_approved', (_) => _refreshMemberStatusFromProfile());
    _socketService.socket?.on('fees_updated', (_) => _refreshMemberStatusFromProfile());
    _socketService.socket?.on('tasks_updated', (_) => _refreshMemberStatusFromProfile());

    // Guard against multiple initializations
    if (!_notificationsInitialized) {
      _pushNotificationService.initialize();
      _notificationsInitialized = true;
    }
  }

  void _disposeServices() {
    _socketService.dispose();
    _notificationsInitialized = false;
  }

  Future<void> refreshProfile() async {
    await _refreshMemberStatusFromProfile();
  }

  Future<void> _refreshMemberStatusFromProfile() async {
    try {
      final res = await _apiService.get('/auth/me');
      if (res.statusCode == 200 && res.data is Map) {
        final status = res.data['status']?.toString() ?? 'none';
        final isPkgPaid = res.data['package_fee_paid'] == true;
        final isGood = res.data['good_standing'] == true ||
            res.data['is_good_standing'] == true ||
            isPkgPaid;
        final regPaid = res.data['registration_fee_paid'] == true ||
            res.data['application_fee_paid'] == true;
        _membershipStatus = status;
        _goodStanding = isGood;
        _registrationFeePaid = regPaid;
        _userCompany = res.data['company']?.toString();
        _membershipNumber = res.data['membership_number']?.toString();
        _licenseNumber = res.data['license_number']?.toString();

        await SessionStorage.instance.setString('cubag_member_status', status);
        await SessionStorage.instance.setString('cubag_status', status);
        await SessionStorage.instance.setString('cubag_registration_fee_paid', regPaid.toString());
        await SessionStorage.instance.setString('cubag_package_fee_paid', isPkgPaid.toString());
        await SessionStorage.instance.setString('cubag_good_standing', isGood.toString());
        if (_membershipNumber != null) {
          await SessionStorage.instance.setString('cubag_membership_number', _membershipNumber!);
        }
        if (_licenseNumber != null) {
          await SessionStorage.instance.setString('cubag_license_number', _licenseNumber!);
        }

        final photo = res.data['profile_photo']?.toString();
        if (photo != null && photo.isNotEmpty && photo != _userPhotoUrl) {
          _userPhotoUrl = photo;
          await SessionStorage.instance.setString('cubag_photo', photo);
        }
        notifyListeners();
      }
    } catch (e, st) {
      AppLogger.error('auth_service', e, st);
    }
  }

  Future<void> _fetchPermissions() async {
    try {
      final res = await _apiService.get('/sub-admins/me/permissions');
      if (res.statusCode == 200) {
        final perms = List<String>.from(res.data['permissions'] ?? []);
        _permissions = perms;
        await SessionStorage.instance.setStringList('cubag_permissions', perms);
      }
    } catch (e, st) {
      AppLogger.error('auth_service', e, st);
    }
  }

  Future<void> setAuthSession({
    required String token,
    required Map<String, dynamic> user,
    List<String>? permissions,
  }) async {
    final role = user['role']?.toString() ?? 'member';
    final status = (user['status']?.toString() ?? 'pending').toLowerCase().trim();
    final perms = permissions ??
        List<String>.from(
          user['permissions'] ?? [],
        );
    final regPaid = user['registration_fee_paid'] == true ||
        user['application_fee_paid'] == true;
    final isPkgPaid = user['package_fee_paid'] == true;
    final isGood = user['good_standing'] == true ||
        user['is_good_standing'] == true ||
        isPkgPaid;

    _isAuthenticated = true;
    _userRole = role;
    _membershipStatus = status;
    _goodStanding = isGood;
    _registrationFeePaid = regPaid;
    _permissions = perms;
    _userPhotoUrl = ApiService.resolveImageUrl(
      user['profile_photo']?.toString(),
    );
    _userName = user['name']?.toString();
    _userEmail = user['email']?.toString();
    _userCompany = user['company']?.toString();
    _membershipNumber = user['membership_number']?.toString() ?? user['membershipNumber']?.toString();
    _licenseNumber = user['license_number']?.toString() ?? user['licenseNumber']?.toString();

    await SessionStorage.instance.setString('cubag_registration_fee_paid', regPaid.toString());
    await SessionStorage.instance.setString('cubag_package_fee_paid', isPkgPaid.toString());
    await SessionStorage.instance.setString('cubag_good_standing', isGood.toString());
    await ApiService.clearAllCaches();

    final futures = <Future>[
      SessionStorage.instance.setString('cubag_token', token),
      SessionStorage.instance.setString('cubag_role', role),
      SessionStorage.instance.setString('cubag_member_status', status),
      SessionStorage.instance.setString('cubag_status', status),
      SessionStorage.instance.setStringList('cubag_permissions', perms),
    ];
    if (_membershipNumber != null) {
      futures.add(
        SessionStorage.instance.setString('cubag_membership_number', _membershipNumber!),
      );
    }
    if (_licenseNumber != null) {
      futures.add(
        SessionStorage.instance.setString('cubag_license_number', _licenseNumber!),
      );
    }
    final exp = user['license_expiry_date'] ?? user['licenseExpiryDate'];
    if (exp != null) {
      futures.add(
        SessionStorage.instance.setString('cubag_expiry', exp.toString()),
      );
    }
    if (user['id'] != null) {
      futures.add(
        SessionStorage.instance.setString(
          'cubag_id',
          user['id'].toString(),
        ),
      );
    }
    if (user['name'] != null) {
      futures.add(
        SessionStorage.instance.setString(
          'cubag_name',
          user['name'].toString(),
        ),
      );
    }
    if (user['email'] != null) {
      futures.add(
        SessionStorage.instance.setString(
          'cubag_email',
          user['email'].toString(),
        ),
      );
    }
    if (user['profile_photo'] != null) {
      futures.add(
        SessionStorage.instance.setString(
          'cubag_photo',
          user['profile_photo'].toString(),
        ),
      );
    }
    await Future.wait(futures);

    _initServices();

    if (role == 'member') {
      await _refreshMemberStatusFromProfile();
    } else if (role == 'sub_admin') {
      if (_permissions.isEmpty) {
        await _fetchPermissions();
      }
    }

    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    try {
      final cleanIdentifier = email.trim().contains('@')
          ? email.trim().toLowerCase()
          : email.trim();
      final response = await _apiService.post(
        '/auth/login',
        data: {'identifier': cleanIdentifier, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data['token'];
        final user = data['user'] as Map<String, dynamic>? ?? {};
        final perms = List<String>.from(
          user['permissions'] ?? data['permissions'] ?? [],
        );

        await setAuthSession(
          token: token.toString(),
          user: user,
          permissions: perms,
        );
        return null;
      }

      String errorMessage = 'Unable to sign in. Please try again.';
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data['message'] != null) {
          errorMessage = data['message'].toString();
        }
      } else if (response.data is String) {
        errorMessage = response.data.toString();
      }

      if (response.statusCode == 401) {
        return 'Incorrect email or password.';
      }
      if (response.statusCode == 403) {
        return errorMessage;
      }
      if ((response.statusCode ?? 0) >= 500) {
        return 'Server error. Please try again in a few seconds.';
      }
      return errorMessage;
    } catch (e) {
      if (e is DioException) {
        if (e.response != null) {
          final statusCode = e.response!.statusCode;
          if (statusCode == 401) {
            return 'Incorrect email or password.';
          }
          if (statusCode == 403) {
            final data = e.response!.data;
            if (data is Map && data['message'] != null) {
              return data['message'].toString();
            }
            return 'Account suspended or access denied.';
          }
          if ((statusCode ?? 0) >= 500) {
            return 'Server error. Please try again in a few seconds.';
          }
        }
      }
      final err = e.toString().toLowerCase();
      if (err.contains('timeout')) {
        return 'Server request timed out. Please try again.';
      }
      if (err.contains('connect') || err.contains('socket')) {
        return 'Unable to reach the server. Please check your internet connection and try again.';
      }
      return 'Unable to sign in. Please check your credentials and try again.';
    }
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _userRole = null;
    _userPhotoUrl = null;
    _userName = null;
    _userEmail = null;
    _userCompany = null;
    _membershipNumber = null;
    _licenseNumber = null;
    _membershipStatus = 'none';
    _goodStanding = false;
    _permissions = [];
    _disposeServices();

    try {
      await SessionStorage.instance.clear();
      await Future.wait([
        ApiService.clearAllCaches(),
        CacheService().clearAll(),
      ]);
    } catch (e, st) {
      AppLogger.error('auth_service_logout', e, st);
    }

    notifyListeners();
  }
}
