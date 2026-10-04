package com.santiagortega.pixelcarplayer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CarLogicTest {

    // ------------------------------------------------------------------ app en primer plano

    @Test
    fun latestForegroundUsesLastResumed() {
        val ev = listOf(
            UsageEv(300, ForegroundEvents.RESUMED, "com.bt.music"),
            UsageEv(100, ForegroundEvents.RESUMED, "com.santiagortega.pixelcarplayer"),
            UsageEv(299, ForegroundEvents.PAUSED, "com.santiagortega.pixelcarplayer"),
        )
        assertEquals("com.bt.music", ForegroundEvents.latestForeground(ev, null))
    }

    @Test
    fun latestForegroundKeepsPreviousWithoutResume() {
        val ev = listOf(UsageEv(10, ForegroundEvents.PAUSED, "com.bt.music"))
        assertEquals("com.bt.music", ForegroundEvents.latestForeground(ev, "com.bt.music"))
        assertEquals("x", ForegroundEvents.latestForeground(emptyList(), "x"))
        assertNull(ForegroundEvents.latestForeground(emptyList(), null))
    }

    // ------------------------------------------------------------------ mantener al frente

    private val own = "com.santiagortega.pixelcarplayer"
    private val launchers = setOf("com.android.launcher3")

    private fun policy(anyApp: Boolean = false, delay: Long = 1000, pkgs: Set<String> = setOf("com.bt.music")) =
        KeepFrontPolicy(KeepFrontPolicy.Config(enabled = true, packages = pkgs, anyApp = anyApp, delayMs = delay))

    @Test
    fun listedPackageTriggersAfterDelay() {
        val p = policy()
        assertFalse(p.tick(0, "com.bt.music", own, false, false, launchers))
        assertFalse(p.tick(500, "com.bt.music", own, false, false, launchers))
        assertEquals(500L, p.msUntilDue(500))
        assertTrue(p.tick(1000, "com.bt.music", own, false, false, launchers))
    }

    @Test
    fun delayRestartsWhenAppChanges() {
        val p = policy(anyApp = true)
        assertFalse(p.tick(0, "com.bt.music", own, false, false, launchers))
        assertFalse(p.tick(900, "com.other", own, false, false, launchers))
        assertFalse(p.tick(1500, "com.other", own, false, false, launchers))
        assertTrue(p.tick(1900, "com.other", own, false, false, launchers))
    }

    @Test
    fun unlistedAndIgnoredDoNotTrigger() {
        val p = policy()
        assertFalse(p.triggers("com.other", own, false, false, launchers))
        assertFalse(p.triggers(own, own, false, false, launchers))
        assertFalse(p.triggers("com.bt.music", own, true, false, launchers)) // ya estamos al frente
        assertFalse(p.triggers("com.bt.music", own, false, true, launchers)) // pausado por nosotros
        val any = policy(anyApp = true)
        assertTrue(any.triggers("com.other", own, false, false, launchers))
        assertFalse(any.triggers("com.android.settings", own, false, false, launchers))
        assertFalse(any.triggers("com.android.settings.intelligence", own, false, false, launchers))
        assertFalse(any.triggers("com.google.android.packageinstaller", own, false, false, launchers))
        assertFalse(any.triggers("com.android.launcher3", own, false, false, launchers)) // Home = el usuario quiere salir
        assertTrue(any.triggers(KeepFrontPolicy.UNKNOWN, own, false, false, launchers))
        assertFalse(p.triggers(KeepFrontPolicy.UNKNOWN, own, false, false, launchers))
    }

    @Test
    fun launcherTriggersWhenListedOrIncluded() {
        val listed = policy(pkgs = setOf("com.android.launcher3"))
        assertTrue(listed.triggers("com.android.launcher3", own, false, false, launchers))
        val incl = KeepFrontPolicy(KeepFrontPolicy.Config(enabled = true, anyApp = true, includeLauncher = true))
        assertTrue(incl.triggers("com.android.launcher3", own, false, false, launchers))
    }

    @Test
    fun disabledNeverTriggers() {
        val p = KeepFrontPolicy(KeepFrontPolicy.Config(enabled = false, packages = setOf("a"), anyApp = true))
        assertFalse(p.tick(0, "a", own, false, false, launchers))
        assertFalse(p.tick(10_000, "a", own, false, false, launchers))
    }

    @Test
    fun backsOffWhenUserKeepsReopening() {
        val p = policy(delay = 0)
        var t = 0L
        repeat(KeepFrontPolicy.FIGHT_MAX_PULLS) {
            assertTrue(p.tick(t, "com.bt.music", own, false, false, launchers))
            t += 1000
            p.tick(t, own, own, true, false, launchers) // volvimos al frente
            t += 1000
        }
        // El usuario la abre otra vez a propósito: no se pelea.
        assertFalse(p.tick(t, "com.bt.music", own, false, false, launchers))
        assertFalse(p.tick(t + 60_000, "com.bt.music", own, false, false, launchers))
        assertTrue(p.tick(t + KeepFrontPolicy.BACKOFF_MS + 1, "com.bt.music", own, false, false, launchers))
    }

    // ------------------------------------------------------------------ actualizaciones

    @Test
    fun parsesAssetNames() {
        val a = UpdateLogic.parseAsset("pixel-car-player-1.2.0-beta.1-42-arm64-v8a.apk", "u", 10)!!
        assertEquals("1.2.0-beta.1", a.versionName)
        assertEquals(42L, a.versionCode)
        assertEquals("arm64-v8a", a.abi)
        val legacy = UpdateLogic.parseAsset("pixel-car-player-beta-20261004-120000-abc1234.apk", "u", 10)!!
        assertNull(legacy.versionCode)
        assertEquals("universal", legacy.abi)
        assertNull(UpdateLogic.parseAsset("release-notes.md", "u", 1))
    }

    @Test
    fun picksAssetByAbi() {
        val assets = listOf(
            UpdateLogic.parseAsset("pixel-car-player-1.0.0-5-universal.apk", "uni", 30)!!,
            UpdateLogic.parseAsset("pixel-car-player-1.0.0-5-armeabi-v7a.apk", "v7", 10)!!,
            UpdateLogic.parseAsset("pixel-car-player-1.0.0-5-arm64-v8a.apk", "v8", 12)!!,
        )
        assertEquals("v8", UpdateLogic.pickAsset(assets, listOf("arm64-v8a", "armeabi-v7a", "armeabi"))!!.url)
        assertEquals("v7", UpdateLogic.pickAsset(assets, listOf("armeabi-v7a", "armeabi"))!!.url)
        assertEquals("uni", UpdateLogic.pickAsset(assets, listOf("x86_64"))!!.url)
        assertNull(UpdateLogic.pickAsset(assets.filter { it.abi == "arm64-v8a" }, listOf("armeabi-v7a")))
    }

    @Test
    fun comparesVersions() {
        assertTrue(UpdateLogic.compareVersions("1.10.0", 1, "1.9.9", 50) > 0)
        assertTrue(UpdateLogic.compareVersions("1.0.0", 6, "1.0.0", 5) > 0)
        // APK split-per-abi instalado (2005) frente al asset con la base (5): misma versión.
        assertEquals(0, UpdateLogic.compareVersions("1.0.0", 5, "1.0.0", 2005))
        assertTrue(UpdateLogic.compareVersions("1.0.0", 6, "1.0.0", 2005) > 0)
        assertEquals(0, UpdateLogic.compareNames("v1.2", "1.2.0"))
        assertNull(UpdateLogic.compareNames("beta-2026", "1.0.0"))
    }

    private fun release(tag: String, published: String, vararg assets: Pair<String, Long>, draft: Boolean = false) = """
        {"tag_name":"$tag","draft":$draft,"prerelease":true,"published_at":"$published",
         "html_url":"https://github.com/x/$tag","body":"notas $tag",
         "assets":[${assets.joinToString(",") { (n, s) -> """{"name":"$n","size":$s,"browser_download_url":"https://dl/$n"}""" }}]}
    """.trimIndent()

    @Test
    fun choosesNewestByVersionCodeForDeviceAbi() {
        val json = "[" + listOf(
            release("v1.1.0", "2026-10-01T10:00:00Z",
                "pixel-car-player-1.1.0-7-arm64-v8a.apk" to 100, "pixel-car-player-1.1.0-7-universal.apk" to 300),
            release("v1.2.0", "2026-09-30T10:00:00Z", // publicada antes pero versión mayor
                "pixel-car-player-1.2.0-8-arm64-v8a.apk" to 110, "pixel-car-player-1.2.0-8-armeabi-v7a.apk" to 90),
            release("v9.9.9", "2026-10-03T10:00:00Z", "pixel-car-player-9.9.9-99-arm64-v8a.apk" to 1, draft = true),
            release("beta-old", "2026-08-01T10:00:00Z", "pixel-car-player-beta-20260801-100000-abc.apk" to 200),
        ).joinToString(",") + "]"
        val cur = UpdateLogic.Current("1.1.0", 2007, 0)
        val r = UpdateLogic.choose(json, listOf("arm64-v8a", "armeabi-v7a"), cur)
        assertEquals(true, r["available"])
        assertEquals("1.2.0", r["versionName"])
        assertEquals(8L, r["versionCode"])
        assertEquals("https://dl/pixel-car-player-1.2.0-8-arm64-v8a.apk", r["apkUrl"])
        assertEquals(110L, r["apkSize"])
        assertEquals("notas v1.2.0", r["notes"])

        val upToDate = UpdateLogic.choose(json, listOf("arm64-v8a"), UpdateLogic.Current("1.2.0", 2008, 0))
        assertEquals(false, upToDate["available"])

        // Equipo x86_64: solo la universal de 1.1.0 le sirve.
        val x86 = UpdateLogic.choose(json, listOf("x86_64"), UpdateLogic.Current("1.0.0", 1, 0))
        assertEquals("https://dl/pixel-car-player-1.1.0-7-universal.apk", x86["apkUrl"])
        assertEquals(true, x86["available"])
    }

    @Test
    fun legacyReleasesCompareByDate() {
        val json = "[" + listOf(
            release("beta-2", "2026-10-02T10:00:00Z", "pixel-car-player-beta-2.apk" to 200),
            release("beta-1", "2026-10-01T10:00:00Z", "pixel-car-player-beta-1.apk" to 200),
        ).joinToString(",") + "]"
        val published2 = UpdateLogic.parseTime("2026-10-02T10:00:00Z")!!
        val older = UpdateLogic.choose(json, listOf("arm64-v8a"), UpdateLogic.Current("1.0.0", 1, published2 - 86_400_000))
        assertEquals(true, older["available"])
        assertEquals("https://dl/pixel-car-player-beta-2.apk", older["apkUrl"])
        val installedAfter = UpdateLogic.choose(json, listOf("arm64-v8a"), UpdateLogic.Current("1.0.0", 1, published2 + 3_600_000))
        assertEquals(false, installedAfter["available"])
    }

    @Test
    fun reportsErrors() {
        assertEquals("parse", UpdateLogic.choose("{oops", emptyList(), UpdateLogic.Current("1", 1, 0))["error"])
        assertEquals("noReleases", UpdateLogic.choose("[]", emptyList(), UpdateLogic.Current("1", 1, 0))["error"])
        val onlyNotes = "[" + release("v1", "2026-10-02T10:00:00Z", "notes.txt" to 1) + "]"
        assertEquals("noAsset", UpdateLogic.choose(onlyNotes, listOf("arm64-v8a"), UpdateLogic.Current("1", 1, 0))["error"])
    }

    @Test
    fun sanitizesBackupNames() {
        assertEquals("a_b.json", BackupNames.sanitize("a/b"))
        assertEquals("config.json", BackupNames.sanitize("config.json"))
        assertEquals(BackupNames.DEFAULT_NAME, BackupNames.sanitize("  "))
    }
}
