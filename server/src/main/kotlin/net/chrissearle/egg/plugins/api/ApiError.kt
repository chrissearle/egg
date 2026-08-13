package net.chrissearle.egg.plugins.api

import io.ktor.http.HttpStatusCode
import kotlinx.serialization.Serializable
import net.chrissearle.egg.domain.scores.MAX_LEVEL
import net.chrissearle.egg.domain.scores.MAX_NAME_LENGTH
import net.chrissearle.egg.domain.scores.MAX_SCORE
import net.chrissearle.egg.plugins.serialization.HttpStatusCodeSerializer

@Serializable
data class ErrorResponse(
    @Serializable(with = HttpStatusCodeSerializer::class)
    val status: HttpStatusCode,
    val message: String,
    val fieldValue: String? = null
)

sealed interface ApiError {
    val response: ErrorResponse
}

fun ApiError.status() = response.status

fun ApiError.messageMap(): Map<String, ErrorResponse> =
    when (this) {
        is UpstreamError -> mapOf("upstream" to upstream, "error" to response)
        else -> mapOf("error" to response)
    }

@Suppress("AbstractClassCanBeConcreteClass")
abstract class UpstreamError(
    open val upstream: ErrorResponse,
    val systemName: String
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.InternalServerError,
            message = "call to $systemName failed"
        )
}

@Suppress("AbstractClassCanBeConcreteClass")
abstract class RequiredField(
    val fieldName: String
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "$fieldName required"
        )
}

/**
 * Submitted scores are rejected rather than sanitised, so nothing malformed
 * ever reaches the store — it is meant to stay readable and hand-editable.
 */
data object ScoreNameRequired : RequiredField(fieldName = "name")

data class ScoreNameTooLong(
    val name: String
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "name must be at most $MAX_NAME_LENGTH characters",
            fieldValue = name
        )
}

/**
 * The game's font covers 0x20-0x7e and nothing else, so a name outside that
 * range could not be drawn on the page in the game's own lettering.
 */
data class ScoreNameNotPrintable(
    val name: String
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "name must be printable ASCII",
            fieldValue = name
        )
}

data class ScoreOutOfRange(
    val score: Int
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "score must be between 0 and $MAX_SCORE",
            fieldValue = "$score"
        )
}

/**
 * Every award in the game is a multiple of ten — eggs are hundreds, grain is
 * fifty, and a bonus tick is ten — so anything else was not earned by playing.
 */
data class ScoreNotAMultipleOfTen(
    val score: Int
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "score must be a multiple of 10",
            fieldValue = "$score"
        )
}

data class ScoreLevelOutOfRange(
    val level: Int
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.BadRequest,
            message = "level must be between 1 and $MAX_LEVEL",
            fieldValue = "$level"
        )
}

data class ScoreStoreUnwritable(
    val e: Throwable
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.InternalServerError,
            message = "could not record score",
            fieldValue = e.message
        )
}

data class VersionNotReadable(
    val e: Throwable
) : ApiError {
    override val response =
        ErrorResponse(
            status = HttpStatusCode.InternalServerError,
            message = "${e.message}"
        )
}
