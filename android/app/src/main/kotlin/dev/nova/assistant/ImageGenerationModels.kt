package dev.nova.assistant

object ImageGenerationModels {
  const val MODEL_Z_IMAGE_TURBO = "Z-Image-Turbo-LiteRT"
  const val MODEL_FLUX_2_KLEIN = "FLUX.2-klein-4B-LiteRT"

  val SUPPORTED_MODELS = listOf(MODEL_Z_IMAGE_TURBO, MODEL_FLUX_2_KLEIN)

  fun isSupportedModel(fileName: String?): Boolean {
    if (fileName == null) return false
    return SUPPORTED_MODELS.any { fileName.contains(it, ignoreCase = true) }
  }

  data class ModelGraphSpec(
    val textEncoder: List<String>,
    val unetMain: List<String>,
    val unetFinal: List<String>,
    val vae: List<String>,
    val defaultSteps: Int,
    val defaultGuidanceScale: Float,
    val latentChannels: Int,
    val latentHeightFactor: Int,
    val latentWidthFactor: Int,
  )

  val MODEL_SPECS = mapOf(
    // Hub I/O (256 px): qwen_enc expects inputs_embeds[1,64,2560] (host BPE +
    // embed_tokens), DiT uses embx/refx + embc/refc then zc_main*, latent is
    // [1,16,32,32] — not SD-style 4ch/8×. See DIFFUSION_MODEL_SPEC.md.
    MODEL_Z_IMAGE_TURBO to ModelGraphSpec(
      textEncoder = listOf("qwen_enc.tflite"),
      unetMain = listOf(
        "z_embx.tflite",
        "z_refx.tflite",
        "z_embc.tflite",
        "z_refc.tflite",
        "zc_main0.tflite",
        "zc_main1.tflite",
        "zc_main2.tflite",
        "zc_main3.tflite",
        "zc_main4.tflite",
        "zc_main5.tflite",
      ),
      unetFinal = listOf("zc_final.tflite"),
      vae = listOf("zvae.tflite"),
      defaultSteps = 4,
      defaultGuidanceScale = 1.0f,
      latentChannels = 16,
      latentHeightFactor = 8,
      latentWidthFactor = 8,
    ),
    // Hub filenames (text-to-image graphs). Editing kce_* / kv_vae_enc not required.
    MODEL_FLUX_2_KLEIN to ModelGraphSpec(
      textEncoder = listOf(
        "ke_enc0.tflite",
        "ke_enc1.tflite",
        "ke_enc2.tflite",
      ),
      unetMain = listOf(
        "kc_prep.tflite",
        "kc_double0.tflite",
        "kc_double1.tflite",
        "kc_single0.tflite",
        "kc_single1.tflite",
        "kc_single2.tflite",
        "kc_single3.tflite",
      ),
      unetFinal = listOf("kc_final.tflite"),
      vae = listOf("kv_vae.tflite"),
      defaultSteps = 4,
      defaultGuidanceScale = 1.0f,
      latentChannels = 4,
      latentHeightFactor = 8,
      latentWidthFactor = 8,
    ),
  )
}
