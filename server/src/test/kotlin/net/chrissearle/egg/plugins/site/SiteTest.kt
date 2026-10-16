package net.chrissearle.egg.plugins.site

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.string.shouldContain
import kotlinx.html.html
import kotlinx.html.p
import kotlinx.html.stream.appendHTML

class SiteTest :
    StringSpec({
        "every page loads the analytics script" {
            val markup =
                buildString {
                    appendHTML().html {
                        page("Test") { p { +"body" } }
                    }
                }

            markup shouldContain "<script src=\"$ANALYTICS_SCRIPT\" defer"
        }
    })
