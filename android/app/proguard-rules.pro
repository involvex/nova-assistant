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

-dontwarn androidx.window.extensions.WindowExtensions
-dontwarn androidx.window.extensions.WindowExtensionsProvider
-dontwarn androidx.window.extensions.area.ExtensionWindowAreaPresentation
-dontwarn androidx.window.extensions.layout.DisplayFeature
-dontwarn androidx.window.extensions.layout.FoldingFeature
-dontwarn androidx.window.extensions.layout.WindowLayoutComponent
-dontwarn androidx.window.extensions.layout.WindowLayoutInfo
-dontwarn androidx.window.sidecar.SidecarDeviceState
-dontwarn androidx.window.sidecar.SidecarDisplayFeature
-dontwarn androidx.window.sidecar.SidecarInterface$SidecarCallback
-dontwarn androidx.window.sidecar.SidecarInterface
-dontwarn androidx.window.sidecar.SidecarProvider
-dontwarn androidx.window.sidecar.SidecarWindowLayoutInfo
