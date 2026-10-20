
import 'package:shared_preferences/shared_preferences.dart';

Future<Map<String, String>> buildApiHeaders({
  bool jsonBody = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('sipas_token');

  final Map<String, String> headers = {
    'Accept': 'application/json',
  };

  if (jsonBody) {
    headers['Content-Type'] = 'application/json';
  }

  if (token != null && token.trim().isNotEmpty) {
    headers['Authorization'] = 'Bearer ${token.trim()}';
  }

  return headers;
}