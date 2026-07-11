-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class dev.flutterberlin.flutter_gemma_mediapipe.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

-dontwarn dev.fluttercommunity.plus.packageinfo.**
-dontwarn com.mr.flutter.plugin.filepicker.**
-dontwarn dev.flutterberlin.flutter_gemma_mediapipe.**
-dontwarn com.csdcorp.speech_to_text.**

-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
