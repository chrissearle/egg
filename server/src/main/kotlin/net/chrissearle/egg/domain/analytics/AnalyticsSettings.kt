package net.chrissearle.egg.domain.analytics

import arrow.core.raise.nullable
import kotlinx.serialization.Serializable

/**
 * Where the site's Umami tracker lives and which website it reports to.
 *
 * Deployment settings, not code: they come from the environment (see
 * `egg.umami` in application.conf), so the same image can run anywhere, and
 * one run without them — locally, or anywhere but production — reports
 * nothing at all.
 */
@Serializable
data class AnalyticsSettings(
    val websiteId: String,
    val domains: List<String>,
    val src: String
)

/**
 * The settings, or null unless every part is present. `domains` is a
 * comma-separated list of the hosts allowed to report.
 */
fun analyticsSettings(
    websiteId: String?,
    domains: String?,
    src: String?
): AnalyticsSettings? =
    nullable {
        AnalyticsSettings(
            websiteId = websiteId?.trim()?.takeIf { it.isNotEmpty() }.bind(),
            domains =
                domains
                    ?.split(",")
                    ?.map { it.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?.takeIf { it.isNotEmpty() }
                    .bind(),
            src = src?.trim()?.takeIf { it.isNotEmpty() }.bind()
        )
    }
