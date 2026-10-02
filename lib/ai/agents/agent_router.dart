import 'package:nova_assistant/ai/agents/agent.dart';

/// Picks the first agent claiming the request. Order matters: specific
/// agents first, [FallbackAgent] last (see [defaultAgents]).
class AgentRouter {
  AgentRouter({List<NovaAgent>? agents}) : _agents = agents ?? defaultAgents();

  final List<NovaAgent> _agents;

  List<NovaAgent> get agents => List<NovaAgent>.unmodifiable(_agents);

  NovaAgent route(AgentRequest request) {
    for (final NovaAgent agent in _agents) {
      if (agent.canHandle(request)) {
        return agent;
      }
    }

    return _agents.last;
  }

  void register(NovaAgent agent, {bool first = false}) {
    if (first) {
      _agents.insert(0, agent);
    } else {
      // Keep fallback semantics: insert before trailing FallbackAgent.
      if (_agents.isNotEmpty && _agents.last is FallbackAgent) {
        _agents.insert(_agents.length - 1, agent);
      } else {
        _agents.add(agent);
      }
    }
  }
}
