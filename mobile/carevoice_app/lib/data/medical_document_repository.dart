import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'api_client.dart';

class MedicalDocumentRepository {
  final _client = ApiClient.instance;

  Future<bool> isCloudStorageReady() async {
    try {
      final headers = await _client.authHeaders();
      final res = await _client.sendWithRefresh(() =>
          http.get(_client.uri('/api/medical-documents/storage-status'), headers: headers).timeout(const Duration(seconds: 8)));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['configured'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<List<MedicalDocumentModel>> getDocuments({String? memberId, String? medicineId}) async {
    final query = <String, String>{};
    if (memberId != null && memberId.isNotEmpty) query['memberId'] = memberId;
    if (medicineId != null && medicineId.isNotEmpty) query['medicineId'] = medicineId;

    final res = await _client.sendWithRefresh(() async {
      final headers = await _client.authHeaders();
      return http.get(_client.uri('/api/medical-documents', query), headers: headers).timeout(const Duration(seconds: 12));
    });

    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((e) => MedicalDocumentModel.fromJson(e)).toList();
    }

    throw Exception(_parseMessage(res.body, fallback: 'Unable to load medical documents right now.'));
  }

  Future<MedicalDocumentModel> uploadDocument({
    required String ownerMemberId,
    String? medicineId,
    required String title,
    required String category,
    String? notes,
    required String fileName,
    required Uint8List bytes,
  }) async {
    Future<http.Response> sendUpload() async {
      final token = await _client.getAccessToken();
      final req = http.MultipartRequest('POST', _client.uri('/api/medical-documents'));
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.fields['ownerMemberId'] = ownerMemberId;
      if (medicineId != null && medicineId.isNotEmpty) {
        req.fields['medicineId'] = medicineId;
      }
      req.fields['title'] = title;
      req.fields['category'] = category;
      if (notes != null && notes.trim().isNotEmpty) {
        req.fields['notes'] = notes.trim();
      }
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      return http.Response.fromStream(streamed);
    }

    final res = await _client.sendWithRefresh(sendUpload);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return MedicalDocumentModel.fromJson(jsonDecode(res.body));
    }

    throw Exception(_parseMessage(res.body, fallback: 'Could not upload this file. Please try again.'));
  }

  Future<Uint8List> downloadDocumentBytes(String documentId, {bool download = false}) async {
    final res = await _client.sendWithRefresh(() async {
      final headers = await _client.authHeaders(jsonContent: false);
      return http
          .get(
            _client.uri('/api/medical-documents/$documentId/file', {'download': download.toString()}),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    });

    if (res.statusCode == 200) {
      return res.bodyBytes;
    }

    throw Exception(_parseMessage(res.body, fallback: 'Could not open this document.'));
  }

  Future<void> deleteDocument(String documentId) async {
    final res = await _client.sendWithRefresh(() async {
      final headers = await _client.authHeaders();
      return http.delete(_client.uri('/api/medical-documents/$documentId'), headers: headers).timeout(const Duration(seconds: 10));
    });

    if (res.statusCode == 200 || res.statusCode == 204) {
      return;
    }

    throw Exception(_parseMessage(res.body, fallback: 'Could not delete this document.'));
  }

  String _parseMessage(String body, {required String fallback}) {
    try {
      final map = jsonDecode(body);
      if (map is Map && map['message'] != null) {
        return map['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }
}
