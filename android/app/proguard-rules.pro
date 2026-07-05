# Add project specific ProGuard rules here.
-keep class dev.nova.assistant.** { *; }

# Flutter Gemma (MediaPipe)
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# LiteRT-LM
-keep class com.google.ai.edge.litert.** { *; }
-dontwarn com.google.ai.edge.litert.**