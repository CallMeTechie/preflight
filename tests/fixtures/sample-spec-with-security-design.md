# Sample Spec With Security Block

A fixture. The block below is well-formed and its facts are internally consistent.

<!-- preflight:security:begin -->
<!-- facts: network_surface=http-html has_accounts=yes auth_method=own-password
     has_privilege_levels=no session_transport=cookie has_owned_data=yes
     is_multi_tenant=no persistence=sql renders_html=yes accepts_uploads=no
     handles_pii=yes -->

## Security Requirements

| ID | Maßnahme | Geltungsbereich | Status | Begründung |
|----|----------|-----------------|--------|------------|
| SEC-CSRF-01 | Anti-CSRF-Token | alle zustandsändernden Routen | required | Cookie-Session |
| SEC-MFA-01 | Zweiter Faktor | Login | not-applicable | (2026-08-26) interne Anwendung, kein Fernzugang |
<!-- preflight:security:end -->
