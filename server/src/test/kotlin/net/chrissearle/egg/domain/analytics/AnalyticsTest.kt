package net.chrissearle.egg.domain.analytics

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import net.chrissearle.egg.plugins.serialization.configureSerialization

private val configured =
    AnalyticsSettings(
        websiteId = "site-id",
        domains = listOf("egg.example"),
        src = "https://stats.example/script.js"
    )

class AnalyticsTest :
    StringSpec({
        "settings need every part" {
            analyticsSettings("site-id", "egg.example", "https://stats.example/script.js") shouldBe configured
            analyticsSettings("", "egg.example", "https://stats.example/script.js") shouldBe null
            analyticsSettings("site-id", " , ", "https://stats.example/script.js") shouldBe null
            analyticsSettings("site-id", "egg.example", null) shouldBe null
        }

        "domains are a trimmed comma-separated list" {
            analyticsSettings("site-id", " a.example, b.example ,", "s")?.domains shouldBe
                listOf("a.example", "b.example")
        }

        "the route hands the settings to the page" {
            testApplication {
                application {
                    configureSerialization()
                    configureAnalytics(configured)
                }

                val response = client.get("/api/analytics")

                response.status shouldBe HttpStatusCode.OK
                response.bodyAsText() shouldContain "\"websiteId\": \"site-id\""
            }
        }

        "the route answers with no content when nothing is configured" {
            testApplication {
                application {
                    configureSerialization()
                    configureAnalytics(null)
                }

                client.get("/api/analytics").status shouldBe HttpStatusCode.NoContent
            }
        }
    })
