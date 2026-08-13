package net.chrissearle.egg.domain.monitoring

import io.github.oshai.kotlinlogging.KLogger
import io.ktor.http.HttpStatusCode
import net.chrissearle.egg.plugins.api.ApiError
import net.chrissearle.egg.plugins.api.status

/**
 * A rejected submission is the client's problem, not ours, so a 4xx is logged
 * at info — otherwise a bot posting junk would fill the log with errors.
 */
fun KLogger.logApiError(error: ApiError) {
    val message = {
        "${error.response.status}: ${error.response.message} ${error.response.fieldValue.orEmpty()}".trim()
    }

    if (error.status().value < HttpStatusCode.InternalServerError.value) {
        info(message)
    } else {
        error(message)
    }
}
