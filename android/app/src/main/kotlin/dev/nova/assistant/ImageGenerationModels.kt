package dev.nova.assistant

object ImageGenerationModels {
  const val MODEL_Z_IMAGE_TURBO = "Z-Image-Turbo-LiteRT"
  const val MODEL_FLUX_2_KLEIN = "FLUX.2-klein-4B-LiteRT"

  val SUPPORTED_MODELS = listOf(MODEL_Z_IMAGE_TURBO, MODEL_FLUX_2_KLEIN)

  fun isSupportedModel(fileName: String?): Boolean {
    if (fileName == null) return false
    return SUPPORTED_MODELS.any { fileName.contains(it, ignoreCase = true) }
  }
}
