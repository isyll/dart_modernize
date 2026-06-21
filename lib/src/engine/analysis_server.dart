import 'dart:async';

import 'package:analysis_server_client/handler/connection_handler.dart';
import 'package:analysis_server_client/handler/notification_handler.dart';
import 'package:analysis_server_client/protocol.dart';
import 'package:analysis_server_client/server.dart';

import 'source_edit.dart' as engine;

/// Thin wrapper around the Dart analysis server process.
///
/// Starts the server once per pipeline run, sends [organizeDirectives] and
/// [sortMembers] requests for individual files, then shuts the server down
/// cleanly. Start with [AnalysisServerWrapper.start]; call [stop] when done.
///
/// Fails loudly (throws [StateError]) if the server cannot start or a request
/// returns an unexpected error : files with parse errors are silently skipped
/// (organizeDirectives/sortMembers are best-effort on broken code).
final class AnalysisServerWrapper {
  final Server _server;

  AnalysisServerWrapper._(this._server);

  /// Returns the edits needed to organize directives in [filePath].
  ///
  /// Returns an empty list if the file is already organized or if the server
  /// reports a parse error (the file is left unchanged in that case).
  Future<List<engine.SourceEdit>> organizeDirectives(String filePath) async {
    Map<String, Object?>? result;
    try {
      result = await _server.send(
        EDIT_REQUEST_ORGANIZE_DIRECTIVES,
        EditOrganizeDirectivesParams(filePath).toJson(),
      );
    } on RequestError catch (e) {
      if (e.code == .ORGANIZE_DIRECTIVES_ERROR) {
        return const [];
      }
      throw StateError(
        'dart_modernize: organizeDirectives failed for $filePath: $e',
      );
    }
    if (result == null) return const [];
    final parsed = EditOrganizeDirectivesResult.fromJson(
      ResponseDecoder(null),
      'result',
      result,
    );
    return _toEngineEdits(parsed.edit.edits);
  }

  /// Returns the edits needed to sort members in [filePath].
  ///
  /// Returns an empty list if the file is already sorted or has parse errors.
  Future<List<engine.SourceEdit>> sortMembers(String filePath) async {
    final Map<String, Object?>? result;
    try {
      result = await _server.send(
        EDIT_REQUEST_SORT_MEMBERS,
        EditSortMembersParams(filePath).toJson(),
      );
    } on RequestError catch (e) {
      if (e.code == .SORT_MEMBERS_INVALID_FILE ||
          e.code == .SORT_MEMBERS_PARSE_ERRORS) {
        return const [];
      }
      throw StateError('dart_modernize: sortMembers failed for $filePath: $e');
    }
    if (result == null) return const [];
    final parsed = EditSortMembersResult.fromJson(
      ResponseDecoder(null),
      'result',
      result,
    );
    return _toEngineEdits(parsed.edit.edits);
  }

  /// Shuts the server down gracefully.
  Future<void> stop() => _server.stop();

  List<engine.SourceEdit> _toEngineEdits(List<SourceEdit> serverEdits) => [
    for (final e in serverEdits)
      .new(offset: e.offset, length: e.length, replacement: e.replacement),
  ];

  /// Starts the analysis server, sets [projectPath] as its analysis root, and
  /// waits for the initial analysis pass to complete before returning.
  static Future<AnalysisServerWrapper> start(String projectPath) async {
    final server = Server();
    final handler = _AnalysisHandler(server);

    // start() must precede listenToOutput(): Server.listenToOutput() accesses
    // _process which is set by start().
    await server.start(
      clientId: 'dart_modernize',
      clientVersion: '0.1.0',
      suppressAnalytics: true,
    );
    server.listenToOutput(notificationProcessor: handler.handleEvent);

    final connected = await handler.serverConnected(
      timeLimit: const .new(seconds: 30),
    );
    if (!connected) {
      throw StateError(
        'dart_modernize: failed to connect to the analysis server within 30 s.',
      );
    }

    // Subscribe to STATUS notifications so the server sends server.status
    // events when analysis state changes.  Without this, notifications may
    // not be delivered in all SDK versions.
    await server.send(
      SERVER_REQUEST_SET_SUBSCRIPTIONS,
      ServerSetSubscriptionsParams([.STATUS]).toJson(),
    );

    await server.send(
      ANALYSIS_REQUEST_SET_ANALYSIS_ROOTS,
      AnalysisSetAnalysisRootsParams([projectPath], <String>[]).toJson(),
    );

    await handler.analysisComplete.future.timeout(
      const .new(seconds: 60),
      onTimeout: () => throw StateError(
        'dart_modernize: analysis server timed out (>60 s) on $projectPath.',
      ),
    );

    return AnalysisServerWrapper._(server);
  }
}

class _AnalysisHandler with NotificationHandler, ConnectionHandler {
  @override
  final Server server;

  final analysisComplete = Completer<void>();

  _AnalysisHandler(this.server);

  @override
  void onServerStatus(ServerStatusParams params) {
    final analysis = params.analysis;
    if (analysis == null || analysis.isAnalyzing) return;
    if (!analysisComplete.isCompleted) analysisComplete.complete();
  }
}
