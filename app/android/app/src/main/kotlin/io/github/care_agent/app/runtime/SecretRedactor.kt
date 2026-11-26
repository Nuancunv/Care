// Care secret-hygiene redactor (AGENTS.md §1.2 — Zero Secret Leakage).
package io.github.care_agent.app.runtime

object SecretRedactor {
    private const val MASK = "[REDACTED]"
    private val ANSI = Regex("""\x1B\[[0-9;?]*[ -/]*[@-~]""")
    private val API_KEY_TOKEN = Regex("""(?<![A-Za-z0-9_])(?:sk-[A-Za-z0-9_-]{12,}|Bearer\s+[A-Za-z0-9._~+/=-]{8,})""", RegexOption.IGNORE_CASE)
    private val ENV_SECRET = Regex(
        """(?i)\b([A-Za-z0-9_]*(?:API_KEY|APIKEY|SECRET|TOKEN|PASSWORD|PASSWD|AUTH)[A-Za-z0-9_]*\s*[=:]\s*)(?:(?:Bearer|Basic)\s+)?([^\s'"]+|'[^']*'|"[^"]*")""",
    )

    fun redact(raw: String): String {
        val clean = ANSI.replace(raw, "")
        val step1 = API_KEY_TOKEN.replace(clean, MASK)
        return ENV_SECRET.replace(step1) { m -> "${m.groupValues[1]}$MASK" }
    }
}
