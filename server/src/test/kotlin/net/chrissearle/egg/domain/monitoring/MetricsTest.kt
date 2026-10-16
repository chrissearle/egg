package net.chrissearle.egg.domain.monitoring

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication

class MetricsTest :
    StringSpec({
        "metrics report the JVM and the build version" {
            testApplication {
                application { configureMonitoring() }

                val response = client.get("/api/metrics")

                response.status shouldBe HttpStatusCode.OK
                val body = response.bodyAsText()
                body shouldContain "jvm_memory_used_bytes"
                body shouldContain "app_build_info{version=\"development\"} 1"
            }
        }
    })
