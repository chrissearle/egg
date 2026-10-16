package net.chrissearle.egg

import io.ktor.server.application.Application
import io.ktor.server.cio.EngineMain
import net.chrissearle.egg.domain.analytics.analyticsSettings
import net.chrissearle.egg.domain.analytics.configureAnalytics
import net.chrissearle.egg.domain.monitoring.configureMonitoring
import net.chrissearle.egg.domain.scores.ScoreStore
import net.chrissearle.egg.domain.scores.configureScoresPage
import net.chrissearle.egg.domain.scores.configureScoresRouting
import net.chrissearle.egg.domain.scores.scoresService
import net.chrissearle.egg.plugins.configureGameHosting
import net.chrissearle.egg.plugins.configureRouting
import net.chrissearle.egg.plugins.serialization.configureSerialization
import net.chrissearle.egg.plugins.site.configureLandingPage
import java.io.File

fun main(args: Array<String>): Unit = EngineMain.main(args)

fun Application.confStr(path: String) = environment.config.property(path).getString()

fun Application.module() {
    val service = scoresService(ScoreStore(File(confStr("egg.store"))))

    configureSerialization()
    configureMonitoring()
    configureRouting()

    configureAnalytics(
        analyticsSettings(
            websiteId = confStr("egg.umami.websiteId"),
            domains = confStr("egg.umami.domains"),
            src = confStr("egg.umami.src")
        )
    )

    configureLandingPage(service)
    configureScoresRouting(service)
    configureScoresPage(service)

    // The game lives under /play, so this no longer has to be registered last
    // to keep a root-mounted "/" from swallowing every other route.
    configureGameHosting(File(confStr("egg.web")), File(confStr("egg.assets")))
}
