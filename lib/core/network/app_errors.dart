import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

/// Turns any error from [InfriveApi] into text to show the user. Screens
/// should check [isSessionExpired] first and send the user back to sign in
/// before displaying this.
String describeError(Object error) =>
    error is FrappeException ? error.message : error.toString();

/// True for a 401: the session itself is gone, not just a forbidden action.
/// A 403 (a signed-in user who lacks access) is also an [AuthException] but
/// should just be reported in place, not treated as a sign-out.
bool isSessionExpired(Object error) =>
    error is AuthException && error.statusCode == 401;
