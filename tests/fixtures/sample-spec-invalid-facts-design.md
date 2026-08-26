# Sample Spec With An Invalid Facts Comment

A fixture. Markers are intact; the value `sqlite` is not in the allowed set for
`persistence`. Silently accepting it would drop SEC-SQLI-01 without a trace.

<!-- preflight:security:begin -->
<!-- facts: network_surface=http-html has_accounts=yes auth_method=own-password
     has_privilege_levels=no session_transport=cookie has_owned_data=yes
     is_multi_tenant=no persistence=sqlite renders_html=yes accepts_uploads=no
     handles_pii=yes -->

## Security Requirements

| ID | Maßnahme | Geltungsbereich | Status | Begründung |
|----|----------|-----------------|--------|------------|
| SEC-CSRF-01 | Anti-CSRF-Token | alle zustandsändernden Routen | required | Cookie-Session |
<!-- preflight:security:end -->
