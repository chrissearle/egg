package net.chrissearle.egg.plugins.api

import arrow.core.Either
import io.github.oshai.kotlinlogging.KotlinLogging
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.response.respondRedirect
import io.ktor.server.response.respondText
import io.ktor.server.routing.RoutingContext
import net.chrissearle.egg.domain.monitoring.logApiError

private val logger = KotlinLogging.logger {}

context(context: RoutingContext)
suspend inline fun <reified A : Any> Either<ApiError, A>.respond(status: HttpStatusCode = HttpStatusCode.OK) {
    onLeft { context.respond(it) }
    onRight { context.call.respond(status, it) }
}

context(context: RoutingContext)
suspend fun Either<ApiError, String>.redirect() {
    onLeft { context.respond(it) }
    onRight { context.call.respondRedirect(it) }
}

suspend fun RoutingContext.respond(error: ApiError) =
    call.respond(error.status(), error.messageMap()).also { logger.logApiError(error) }

context(context: RoutingContext)
suspend fun Either<ApiError, String>.respondPlainText(status: HttpStatusCode = HttpStatusCode.OK) {
    onLeft { context.respond(it) }
    onRight { context.call.respondText(status = status, text = it) }
}
