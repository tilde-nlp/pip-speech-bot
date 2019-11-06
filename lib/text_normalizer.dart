import 'package:logging/logging.dart';
import 'package:dio/dio.dart';

final Logger _log = Logger("TextNormalizer");

class TextNormalizer {
  final String endpoint;
  final Dio _dio = Dio();

  TextNormalizer(this.endpoint) {
    if (endpoint == null) {
      _log.warning("Normalizer initialized with null endpoint.");
    }
  }

  Future<String> normalize(String text) async {
    if (endpoint == null) {
      return text;
    }
    try {
      Response response = await _dio.get(
        endpoint,
        queryParameters: {
          "text": text,
        },
        options: Options(
          connectTimeout: 2000,
          receiveTimeout: 5000,
        )
      );
      return response.data.toString();
    } catch (e) {
      _log.severe("Normalizer call failed due to: $e");
    }

    return text;
  }
}
