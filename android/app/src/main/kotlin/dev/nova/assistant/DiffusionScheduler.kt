package dev.nova.assistant

import android.util.Log

object DiffusionScheduler {
  private const val TAG = "DiffusionScheduler"

  data class SchedulerState(
    val alphasCumprod: FloatArray,
    val timesteps: IntArray,
    val sigmas: FloatArray,
  )

  data class StepResult(
    val nextLatents: Array<FloatArray>,
    val predictedNoise: Array<FloatArray>,
  )

  fun createState(
    numTrainTimesteps: Int = 1000,
    betaStart: Float = 0.00085f,
    betaEnd: Float = 0.012f,
    scheduleType: String = "scaled_linear",
  ): SchedulerState {
    val betas = when (scheduleType) {
      "linear" -> linearSchedule(numTrainTimesteps, betaStart, betaEnd)
      "scaled_linear" -> scaledLinearSchedule(numTrainTimesteps, betaStart, betaEnd)
      else -> scaledLinearSchedule(numTrainTimesteps, betaStart, betaEnd)
    }
    val alphas = betas.map { 1f - it }.toFloatArray()
    val alphasCumprod = FloatArray(alphas.size)
    var product = 1f
    for (i in alphas.indices) {
      product *= alphas[i]
      alphasCumprod[i] = product
    }

    return SchedulerState(
      alphasCumprod = alphasCumprod,
      timesteps = IntArray(numTrainTimesteps) { numTrainTimesteps - 1 - it },
      sigmas = FloatArray(numTrainTimesteps),
    )
  }

  private fun linearSchedule(
    numSteps: Int,
    betaStart: Float,
    betaEnd: Float,
  ): FloatArray {
    return FloatArray(numSteps) { i ->
      betaStart + (betaEnd - betaStart) * i / (numSteps - 1)
    }
  }

  private fun scaledLinearSchedule(
    numSteps: Int,
    betaStart: Float,
    betaEnd: Float,
  ): FloatArray {
    return FloatArray(numSteps) { i ->
      val t = i / (numSteps - 1f)
      betaStart + 0.5f * (betaEnd - betaStart) * (1f + kotlin.math.sin(t * kotlin.math.PI / 2f)).toFloat()
    }
  }

  fun getTimestepsForInference(
    state: SchedulerState,
    numInferenceSteps: Int,
  ): IntArray {
    val stepRatio = state.timesteps.size / numInferenceSteps
    val selected = IntArray(numInferenceSteps)
    for (i in 0 until numInferenceSteps) {
      selected[i] = state.timesteps[i * stepRatio]
    }
    return selected
  }

  fun step(
    state: SchedulerState,
    timestep: Int,
    latents: Array<FloatArray>,
    predictedNoise: Array<FloatArray>,
    guidanceScale: Float = 1.0f,
    textEmbeddings: Array<FloatArray>? = null,
    uncondEmbeddings: Array<FloatArray>? = null,
  ): StepResult {
    val alphaProd = state.alphasCumprod[timestep]
    val sqrtAlphaProd = kotlin.math.sqrt(alphaProd)
    val sqrtOneMinusAlphaProd = kotlin.math.sqrt(1f - alphaProd)

    var noisePred = predictedNoise

    if (guidanceScale > 1.0f && textEmbeddings != null && uncondEmbeddings != null) {
      noisePred = applyGuidance(noisePred, textEmbeddings, uncondEmbeddings, guidanceScale)
    }

    val prevTimestep = kotlin.math.max(timestep - 1, 0)
    val prevAlphaProd = if (prevTimestep >= 0) state.alphasCumprod[prevTimestep] else 1f
    val prevSqrtAlphaProd = kotlin.math.sqrt(prevAlphaProd)
    val prevOneMinusAlphaProd = kotlin.math.sqrt(1f - prevAlphaProd)

    val nextLatents = Array(latents.size) { idx ->
      val current = latents[idx]
      val noise = noisePred[idx]
      val next = FloatArray(current.size)
      for (i in current.indices) {
        val predOriginal = (current[i] - sqrtOneMinusAlphaProd * noise[i]) / sqrtAlphaProd
        val predOriginalScaled = prevSqrtAlphaProd * predOriginal + prevOneMinusAlphaProd * noise[i]
        next[i] = predOriginalScaled
      }
      next
    }

    return StepResult(nextLatents = nextLatents, predictedNoise = noisePred)
  }

  private fun applyGuidance(
    noisePred: Array<FloatArray>,
    textEmb: Array<FloatArray>,
    uncondEmb: Array<FloatArray>,
    guidanceScale: Float,
  ): Array<FloatArray> {
    return Array(noisePred.size) { idx ->
      val noise = noisePred[idx]
      val text = textEmb[idx]
      val uncond = uncondEmb[idx]
      val result = FloatArray(noise.size)
      for (i in noise.indices) {
        result[i] = uncond[i] + guidanceScale * (text[i] - uncond[i])
      }
      result
    }
  }

  fun stepDdim(
    state: SchedulerState,
    timestep: Int,
    prevTimestep: Int,
    latents: Array<FloatArray>,
    predictedNoise: Array<FloatArray>,
    eta: Float = 0.0f,
  ): StepResult {
    val alphaProd = state.alphasCumprod[timestep]
    val prevAlphaProd = state.alphasCumprod[prevTimestep]

    val sqrtAlphaProd = kotlin.math.sqrt(alphaProd)
    val sqrtOneMinusAlphaProd = kotlin.math.sqrt(1f - alphaProd)

    val predOriginal = Array(latents.size) { idx ->
      val current = latents[idx]
      val noise = predictedNoise[idx]
      val result = FloatArray(current.size)
      for (i in current.indices) {
        result[i] = (current[i] - sqrtOneMinusAlphaProd * noise[i]) / sqrtAlphaProd
      }
      result
    }

    val dirXt = Array(latents.size) { idx ->
      val noise = predictedNoise[idx]
      val orig = predOriginal[idx]
      val result = FloatArray(noise.size)
      for (i in noise.indices) {
        result[i] = kotlin.math.sqrt(1f - prevAlphaProd) * noise[i]
      }
      result
    }

    val noise = if (eta > 0f) {
      val sigma = eta * kotlin.math.sqrt(
        (1f - prevAlphaProd) / (1f - alphaProd) * (1f - alphaProd / prevAlphaProd)
      )
      Array(latents.size) { idx ->
        val orig = predOriginal[idx]
        val result = FloatArray(orig.size)
        for (i in orig.indices) {
          result[i] = orig[i] + kotlin.math.sqrt(kotlin.math.max(0f, sigma * sigma)) * randomNormal(orig.size)
        }
        result
      }
    } else {
      predOriginal
    }

    val nextLatents = Array(latents.size) { idx ->
      val orig = noise[idx]
      val dir = dirXt[idx]
      val result = FloatArray(orig.size)
      for (i in orig.indices) {
        result[i] = kotlin.math.sqrt(prevAlphaProd) * orig[i] + dir[i]
      }
      result
    }

    return StepResult(nextLatents = nextLatents, predictedNoise = predictedNoise)
  }

  private fun randomNormal(size: Int): Float {
    val u1 = kotlin.random.Random.nextDouble().coerceAtLeast(1e-10)
    val u2 = kotlin.random.Random.nextDouble()
    val z0 = kotlin.math.sqrt(-2f * kotlin.math.ln(u1)) * kotlin.math.cos(2f * kotlin.math.PI * u2)
    return z0.toFloat()
  }
}
