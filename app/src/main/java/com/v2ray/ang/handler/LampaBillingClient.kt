package com.v2ray.ang.handler

import com.v2ray.ang.AppConfig
import com.v2ray.ang.BuildConfig
import com.v2ray.ang.dto.LampaPaymentCreateRequest
import com.v2ray.ang.dto.LampaPaymentCreateResponse
import com.v2ray.ang.dto.LampaPaymentStatusResponse
import com.v2ray.ang.dto.LampaSubscriptionResponse
import com.v2ray.ang.util.JsonUtil
import com.v2ray.ang.util.LogUtil
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

object LampaBillingClient {

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    private fun userAgent(): String = "${AppConfig.LAMPA_SUBSCRIPTION_USER_AGENT}/${BuildConfig.VERSION_NAME}"

    private fun candidateBases(): List<String> = listOf(
        "https://${AppConfig.SUBSCRIPTION_PRIMARY_HOST}",
        "https://${AppConfig.SUBSCRIPTION_FALLBACK_HOST}",
    )

    fun fetchSubscription(subId: String): LampaSubscriptionResponse? =
        getJson("/api/app/subscription/$subId", LampaSubscriptionResponse::class.java)

    fun createPayment(subId: String, planId: String, method: String, test: Boolean = false): LampaPaymentCreateResponse? {
        val body = JsonUtil.toJson(LampaPaymentCreateRequest(subId, planId, method, test))
        return postJson("/api/app/payment", body, LampaPaymentCreateResponse::class.java)
    }

    fun paymentStatus(orderId: String, subId: String): LampaPaymentStatusResponse? =
        getJson("/api/app/payment/$orderId?subId=${encode(subId)}", LampaPaymentStatusResponse::class.java)

    @Suppress("UNCHECKED_CAST")
    private fun <T> getJson(path: String, cls: Class<T>): T? {
        for (base in candidateBases()) {
            val result = runCatching { executeGet("$base$path", cls) as T? }.getOrNull()
            if (result != null) return result
        }
        return null
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> postJson(path: String, jsonBody: String, cls: Class<T>): T? {
        for (base in candidateBases()) {
            val result = runCatching { executePost("$base$path", jsonBody, cls) as T? }.getOrNull()
            if (result != null) return result
        }
        return null
    }

    private fun <T> executeGet(url: String, cls: Class<T>): T? {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent())
            .header("Accept", "application/json")
            .get()
            .build()
        client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                LogUtil.w(AppConfig.TAG, "Lampa billing GET $url -> ${response.code}: ${text.take(200)}")
                return JsonUtil.fromJsonSafe(text, cls)
            }
            return JsonUtil.fromJsonSafe(text, cls)
        }
    }

    private fun <T> executePost(url: String, jsonBody: String, cls: Class<T>): T? {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent())
            .header("Accept", "application/json")
            .post(jsonBody.toRequestBody(jsonMedia))
            .build()
        client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                LogUtil.w(AppConfig.TAG, "Lampa billing POST $url -> ${response.code}: ${text.take(200)}")
                return JsonUtil.fromJsonSafe(text, cls)
            }
            return JsonUtil.fromJsonSafe(text, cls)
        }
    }

    private fun encode(value: String): String =
        java.net.URLEncoder.encode(value, Charsets.UTF_8.name())
}
