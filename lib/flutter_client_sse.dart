library flutter_client_sse;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:http/http.dart' as http;
part 'sse_event_model.dart';

class SSEClient {
  static http.Client _client = http.Client(); // Initialize the client once

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

    // Add body to the request if it exists
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
                // Ignore retry logic if not needed
                break;
              default:
                print('---UNHANDLED FIELD---');
                print(dataLine);
            }
          },
          onError: (e) {
            print('---STREAM ERROR---');
            print(e);
            // Propagate error through stream and close
            streamController.addError(e);
            streamController.close();
          },
          onDone: () {
            print('---STREAM CLOSED---');
            // Close the stream when done
            streamController.close();
          },
        );
      }, onError: (e) {
        print('---RESPONSE ERROR---');
        print(e);
        // Propagate error through stream and close
        streamController.addError(e);
        streamController.close();
      });
    } catch (e) {
      print('---REQUEST ERROR---');
      print(e);
      // Propagate error through stream and close
      streamController.addError(e);
      streamController.close();
    }

    return streamController.stream;
  }

  static void unsubscribeFromSSE() {
    _client.close(); // Properly close the HTTP client
    print('---SSE UNSUBSCRIBED AND CLIENT CLOSED---');
  }
}
