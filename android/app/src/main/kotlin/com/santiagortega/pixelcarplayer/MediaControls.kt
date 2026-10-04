package com.santiagortega.pixelcarplayer

/**
 * "Me gusta" detectado entre las acciones personalizadas de la sesión.
 * [likeAction] = agrega (no está en favoritos); [unlikeAction] = quita (ya está en favoritos).
 */
data class LikeInfo(val likeAction: String?, val unlikeAction: String?) {
    val canLike: Boolean get() = likeAction != null || unlikeAction != null

    /** true si se ofrece "quitar" (ya está), false si solo "agregar", null si no hay acción. */
    val liked: Boolean?
        get() = when {
            unlikeAction != null -> true
            likeAction != null -> false
            else -> null
        }

    /** Acción a enviar para alternar. */
    fun actionToSend(): String? = if (unlikeAction != null) unlikeAction else likeAction
}

/** Lógica pura de controles v3 (shuffle/repeat/like); sin Android para poder probarla en JVM. */
object MediaControls {
    // Valores de PlaybackStateCompat (constantes copiadas para no depender de Android en tests).
    const val SHUFFLE_NONE = 0
    const val SHUFFLE_ALL = 1
    const val SHUFFLE_GROUP = 2
    const val REPEAT_NONE = 0
    const val REPEAT_ONE = 1
    const val REPEAT_ALL = 2
    const val REPEAT_GROUP = 3

    /** -1 (desconocido / sesión no compat) → null. */
    fun shuffleOf(mode: Int): Boolean? = when (mode) {
        SHUFFLE_NONE -> false
        SHUFFLE_ALL, SHUFFLE_GROUP -> true
        else -> null
    }

    fun repeatOf(mode: Int): String? = when (mode) {
        REPEAT_NONE -> "off"
        REPEAT_ONE -> "one"
        REPEAT_ALL, REPEAT_GROUP -> "all"
        else -> null
    }

    fun nextShuffle(mode: Int): Int = if (mode == SHUFFLE_NONE || mode < 0) SHUFFLE_ALL else SHUFFLE_NONE

    /** off → all → one → off (desconocido → all). */
    fun nextRepeat(mode: Int): Int = when (mode) {
        REPEAT_NONE -> REPEAT_ALL
        REPEAT_ALL, REPEAT_GROUP -> REPEAT_ONE
        REPEAT_ONE -> REPEAT_NONE
        else -> REPEAT_ALL
    }

    private val nonAlnum = Regex("[^a-z0-9]+")

    fun norm(s: String): String = s.lowercase().replace(nonAlnum, "_").trim('_')

    /** Palabras de "me gusta" (id o nombre de la acción, normalizados). */
    private val likeWords = listOf(
        "like", "heart", "favo", "collection", "add_to", "thumb_up", "thumbs_up", "love",
        "me_gusta", "save", "library", "guardar", "biblioteca",
    )

    /** Acciones parecidas que NO son "me gusta". */
    private val excludeWords = listOf(
        "dislike", "thumb_down", "thumbs_down", "playlist", "queue", "shuffle", "repeat", "radio",
        "download", "seek", "skip", "speed", "rewind", "forward", "lista",
    )

    /** Indicadores de "quitar" (el ítem ya está en favoritos). */
    private val removeRegex = Regex(
        "(^|_)(remove|removed|unlike|un_like|unheart|unfavou?rite|unsave|unlove|delete|quitar|eliminar|borrar)(_|$)|remove_from|un_?like"
    )

    /**
     * Busca entre [actions] (`action` → `name`) la de agregar a favoritos y la de quitar.
     * Spotify usa acciones estilo colección ("ADD_TO…"/"REMOVE_FROM…"), YouTube Music "thumbs up",
     * otras "like"/"heart"/"favorite". Las de "dislike"/listas/cola se ignoran.
     */
    fun detectLike(actions: List<Pair<String, String>>): LikeInfo {
        var like: String? = null
        var unlike: String? = null
        for ((action, name) in actions) {
            if (action.isBlank()) continue
            val text = key(action, name)
            if (excludeWords.any { text.contains(it) }) continue
            val isRemove = removeRegex.containsMatchIn(text)
            val isLike = likeWords.any { text.contains(it) }
            if (!isLike && !(isRemove && text.contains("from"))) continue
            if (isRemove) {
                if (unlike == null) unlike = action
            } else if (like == null) {
                like = action
            }
        }
        return LikeInfo(like, unlike)
    }

    /** Primera acción personalizada cuyo id o nombre contiene [word] (p. ej. `shuffle`). */
    fun findAction(actions: List<Pair<String, String>>, word: String): String? =
        actions.firstOrNull { (a, n) -> a.isNotBlank() && key(a, n).contains(word) }?.first

    /** Último segmento del id (sin prefijo de paquete) + nombre, normalizados. */
    private fun key(action: String, name: String): String =
        norm(action.substringAfterLast('.')) + "_" + norm(name)
}
