import 'package:url_launcher/url_launcher.dart';

class SmsHelper {

  /// Send SMS with custom message
  static Future<void> sendSMS({
    required String phone,
    required String message,
  }) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body': message,
      },
    );

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      throw 'Could not launch SMS';
    }
  }
}
