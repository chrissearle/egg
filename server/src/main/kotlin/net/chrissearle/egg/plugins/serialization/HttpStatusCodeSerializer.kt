package net.chrissearle.egg.plugins.serialization

import io.ktor.http.HttpStatusCode
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure

object HttpStatusCodeSerializer : KSerializer<HttpStatusCode> {
    override val descriptor =
        buildClassSerialDescriptor("HttpStatusCode") {
            element<Int>("value")
            element<String>("description")
        }

    override fun deserialize(decoder: Decoder): HttpStatusCode =
        decoder.decodeStructure(descriptor) {
            val code = decodeIntElement(descriptor, 0)
            HttpStatusCode.fromValue(code)
        }

    override fun serialize(
        encoder: Encoder,
        value: HttpStatusCode
    ) = encoder.encodeStructure(descriptor) {
        encodeIntElement(descriptor, 0, value.value)
        encodeStringElement(descriptor, 1, value.description)
    }
}
