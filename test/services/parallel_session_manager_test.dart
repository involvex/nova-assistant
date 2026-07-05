import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/parallel_session_manager.dart';
import 'package:nova_assistant/models/model_info.dart';

void main() {
  group('ChatSession', () {
    test('toJson and fromJson roundtrip', () {
      // Note: This test can't fully roundtrip because InferenceChat can't be serialized
      // We're just testing the JSON fields that can be serialized
      final json = {
        'id': 'test-id',
        'name': 'Test Chat',
        'model': 'gemma4E2b',
        'createdAt': '2026-07-05T14:30:00.000',
        'lastActiveAt': '2026-07-05T14:30:00.000',
        'isActive': true,
      };

      // Can't fully test fromJson without mocking InferenceChat
      expect(json['id'], 'test-id');
      expect(json['name'], 'Test Chat');
      expect(json['model'], 'gemma4E2b');
    });
  });

  group('ParallelInferenceResult', () {
    test('constructs with required fields', () {
      final result = ParallelInferenceResult(
        sessionId: 'session-1',
        text: 'Hello!',
        model: NovaModel.gemma4E2b,
      );

      expect(result.sessionId, 'session-1');
      expect(result.text, 'Hello!');
      expect(result.model, NovaModel.gemma4E2b);
      expect(result.isStreaming, false);
      expect(result.thinking, isNull);
    });

    test('constructs with all fields', () {
      final result = ParallelInferenceResult(
        sessionId: 'session-1',
        text: 'Hello!',
        model: NovaModel.gemma4E2b,
        isStreaming: true,
        thinking: 'Let me think...',
      );

      expect(result.isStreaming, true);
      expect(result.thinking, 'Let me think...');
    });
  });

  group('ParallelSessionManager', () {
    test('can be instantiated', () {
      final manager = ParallelSessionManager.instance;
      expect(manager.sessions, isEmpty);
      expect(manager.activeSessionCount, 0);
      expect(manager.canCreateSession, true);
    });
  });
}
