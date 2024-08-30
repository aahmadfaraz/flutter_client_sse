library flutter_client_sse;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:http/http.dart' as http;
part 'sse_event_model.dart';

/// A client for subscribing to Server-Sent Events (SSE).
class SSEClient {
  static http.Client _client = http.Client(); // Initialize the client once

  /// Subscribe to Server-Sent Events.
  ///
  /// [method] is the request method (GET or POST).
  /// [url] is the URL of the SSE endpoint.
  /// [header] is a map of request headers.
  /// [body] is an optional request body for POST requests.
  ///
  /// Returns a [Stream] of [SSEModel] representing the SSE events.
  static Stream<SSEModel> subscribeToSSE({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
    StreamController<SSEModel>? oldStreamController,
    Map<String, dynamic>? body,
  }) {
    // Create or reuse a StreamController
    final StreamController<SSEModel> streamController =
        oldStreamController ?? StreamController<SSEModel>.broadcast();

    var lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
    var currentSSEModel = SSEModel(data: '', id: '', event: '');

    print("--SUBSCRIBING TO SSE---");

    _client = http.Client(); // Ensure we have a fresh client for each connection
    var request = http.Request(
      method == SSERequestType.GET ? "GET" : "POST",
      Uri.parse(url),
    );

    // Add headers to the request
    request.headers.addAll(header);

    // Add body to the request if exists
    if (body != null) {
      request.body = jsonEncode(body);
    }

    try {
      Future<http.StreamedResponse> response = _client.send(request);

      response.asStream().listen((data) {
        data.stream
            .transform(Utf8Decoder())
            .transform(LineSplitter())
            .listen(
          (dataLine) {
            if (dataLine.isEmpty) {
              // Event set complete, add to stream
              streamController.add(currentSSEModel);
              currentSSEModel = SSEModel(data: '', id: '', event: '');
              return;
            }

            Match match = lineRegex.firstMatch(dataLine)!;
            var field = match.group(1);
            if (field!.isEmpty) return;

            var value = (field == 'data')
                ? dataLine.substring(5)
                : match.group(2) ?? '';

            switch (field) {
              case 'event':
                currentSSEModel.event = value;
                break;
              case 'data':
                currentSSEModel.data =
                    (currentSSEModel.data ?? '') + value + '\n';
                break;
              case 'id':
                currentSSEModel.id = value;
                break;
              case 'retry':
                // Handle retry logic if needed
                break;
              default:
                print('---UNHANDLED FIELD---');
                print(dataLine);
            }
          },
          onError: (e) {
            print('---STREAM ERROR---');
            print(e);
            _retryConnection(
              method: method,
              url: url,
              header: header,
              streamController: streamController,
              body: body,
            );
          },
          onDone: () {
            print('---STREAM CLOSED---');
            _retryConnection(
              method: method,
              url: url,
              header: header,
              streamController: streamController,
              body: body,
            );
          },
        );
      }, onError: (e) {
        print('---RESPONSE ERROR---');
        print(e);
        _retryConnection(
          method: method,
          url: url,
          header: header,
          streamController: streamController,
          body: body,
        );
      });
    } catch (e) {
      print('---REQUEST ERROR---');
      print(e);
      _retryConnection(
        method: method,
        url: url,
        header: header,
        streamController: streamController,
        body: body,
      );
    }

    return streamController.stream;
  }

  /// Retry the SSE connection after a delay.
  ///
  /// [method] is the request method (GET or POST).
  /// [url] is the URL of the SSE endpoint.
  /// [header] is a map of request headers.
  /// [body] is an optional request body for POST requests.
  /// [streamController] is required to persist the stream from the old connection
  static void _retryConnection({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
    required StreamController<SSEModel> streamController,
    Map<String, dynamic>? body,
  }) {
    print('---RETRYING CONNECTION---');
    Future.delayed(Duration(seconds: 5), () {
      subscribeToSSE(
        method: method,
        url: url,
        header: header,
        oldStreamController: streamController,
        body: body,
      );
    });
  }

  /// Unsubscribe from the SSE.
  static void unsubscribeFromSSE() {
    _client.close(); // Properly close the HTTP client
    print('---SSE UNSUBSCRIBED AND CLIENT CLOSED---');
  }
}
