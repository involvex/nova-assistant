enum ToolProgressStage { starting, executing, processing, done, error }

class ToolProgress {
  final String toolName;
  final ToolProgressStage stage;
  final double? percent;
  final String? message;
  final Map<String, dynamic>? data;

  const ToolProgress({
    required this.toolName,
    required this.stage,
    this.percent,
    this.message,
    this.data,
  });

  factory ToolProgress.fromMap(Map<String, dynamic> map) {
    return ToolProgress(
      toolName: map['toolName'] as String? ?? '',
      stage: ToolProgressStage.values.firstWhere(
        (s) => s.name == map['stage'],
        orElse: () => ToolProgressStage.executing,
      ),
      percent: (map['percent'] as num?)?.toDouble(),
      message: map['message'] as String?,
      data: map['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'toolName': toolName,
      'stage': stage.name,
      if (percent != null) 'percent': percent,
      if (message != null) 'message': message,
      if (data != null) 'data': data,
    };
  }
}
