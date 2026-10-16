package net.chrissearle.egg.domain.monitoring

import arrow.core.getOrElse
import arrow.core.raise.either
import io.ktor.http.HttpHeaders
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.metrics.micrometer.MicrometerMetrics
import io.ktor.server.plugins.callid.CallId
import io.ktor.server.plugins.callid.callIdMdc
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.calllogging.processingTimeMillis
import io.ktor.server.request.httpMethod
import io.ktor.server.request.path
import io.ktor.server.request.uri
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.micrometer.core.instrument.binder.jvm.JvmGcMetrics
import io.micrometer.core.instrument.binder.jvm.JvmMemoryMetrics
import io.micrometer.core.instrument.binder.system.ProcessorMetrics
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import io.prometheus.metrics.core.metrics.Info
import net.chrissearle.egg.plugins.BuildInfo
import org.slf4j.event.Level

private val pollingPaths = setOf("/health", "/api/metrics")

// The version label when image-tag.txt is present but can't be read
private const val UNREADABLE_VERSION = "unknown"

fun Application.configureMonitoring() {
    val appMicrometerRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)

    install(MicrometerMetrics) {
        registry = appMicrometerRegistry

        meterBinders =
            listOf(
                JvmMemoryMetrics(),
                JvmGcMetrics(),
                ProcessorMetrics()
            )
    }

    // Same series as the other apps, so the Ktor dashboard can show and
    // annotate what is deployed. A Prometheus Info metric rather than a
    // Micrometer gauge: the registry treats _info as reserved and would export
    // a gauge as app_build
    Info
        .builder()
        .name("app_build_info")
        .help("Deployed build, from the image tag; always 1")
        .labelNames("version")
        .register(appMicrometerRegistry.prometheusRegistry)
        .setLabelValues(either { BuildInfo.imageTag() }.getOrElse { UNREADABLE_VERSION })
    install(CallLogging) {
        level = Level.INFO
        filter { call -> call.request.path() !in pollingPaths }
        callIdMdc("call-id")
        format { call ->
            "${call.response.status()}: ${call.request.httpMethod.value} - ${call.request.uri} " +
                "in ${call.processingTimeMillis()}ms"
        }
    }
    install(CallId) {
        header(HttpHeaders.XRequestId)
        verify { callId: String ->
            callId.isNotEmpty()
        }
    }
    routing {
        get("/api/metrics") {
            call.respond(appMicrometerRegistry.scrape())
        }
    }
}
