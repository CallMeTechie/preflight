# Security Matrix (derivation rules)

Eleven facts, twenty-four rules. The profiler derives facts from the spec, asks
only for what it cannot derive, then applies every rule row mechanically.

## Facts

| Fakt | Werte |
| - | - |
| network_surface | none / http-api / http-html / both |
| has_accounts | yes / no |
| auth_method | own-password / delegated / api-key / none |
| has_privilege_levels | yes / no |
| session_transport | cookie / bearer-header / none |
| has_owned_data | yes / no |
| is_multi_tenant | yes / no |
| persistence | sql / nosql / files / none |
| renders_html | yes / no |
| accepts_uploads | yes / no |
| handles_pii | yes / no |

## Consistency conditions

Checked before the rules are applied; a violation aborts. Both columns use the
trigger grammar below, so the same parser checks them.

| Wenn | dann muss gelten |
| - | - |
| renders_html = yes | network_surface = http-html OR network_surface = both |
| network_surface = none | session_transport = none AND renders_html = no AND accepts_uploads = no |
| has_accounts = no | auth_method = api-key OR auth_method = none |
| is_multi_tenant = yes | has_owned_data = yes |

## Trigger grammar

A trigger is either the literal `immer` or a boolean expression over the terms
`<fact> = <value>` and `<fact> != <value>`, joined by `AND` / `OR`, with at most
one level of parentheses. No other operators, no negation of whole expressions.
`tests/test_security_matrix_wellformed.sh` enforces exactly this.

## Rules

| ID | Maßnahme | Auslöser | Status |
| - | - | - | - |
| SEC-INPUT-01 | Input-Validierung per Whitelist | network_surface != none | required |
| SEC-ERR-01 | Fehlermeldungen ohne Stack-Traces und DB-Details | network_surface != none | required |
| SEC-SECRET-01 | Secrets außerhalb von Code und Repo | immer | required |
| SEC-DEP-01 | Abhängigkeiten auf bekannte Schwachstellen prüfen | immer | required |
| SEC-INJECT-01 | Fremde Eingaben nicht in Befehle oder Pfade bauen: Argumentlisten statt Shell-Zeilen, Pfade gegen ein Wurzelverzeichnis prüfen, keine ungeprüfte Wortzerlegung | immer | required |
| SEC-RATE-01 | Rate Limiting auf zustandsändernden Endpunkten | network_surface != none | required |
| SEC-RATE-02 | Brute-Force-Bremse am Login (Drosselung und Sperre) | has_accounts = yes | required |
| SEC-SQLI-01 | Prepared Statements, keine String-Konkatenation | persistence = sql | required |
| SEC-XSS-01 | Kontextsensitives Output-Encoding | renders_html = yes | required |
| SEC-CSP-01 | Content Security Policy | renders_html = yes | required |
| SEC-UPLOAD-01 | Upload-Prüfung: Typ, Größe, Ablage außerhalb des Webroot | accepts_uploads = yes | required |
| SEC-IDOR-01 | Objektbezogene Autorisierung bei jedem Zugriff über eine ID | has_owned_data = yes | required |
| SEC-TENANT-01 | Mandanten-Scoping in jeder Abfrage | is_multi_tenant = yes | required |
| SEC-RBAC-01 | Rollen- oder Rechtemodell | has_privilege_levels = yes | required |
| SEC-PWH-01 | Passwort-Hashing mit Argon2id oder bcrypt, mit Salt | auth_method = own-password | required |
| SEC-PWPOL-01 | Mindestanforderungen, Abgleich gegen bekannte Leaks | auth_method = own-password | recommended |
| SEC-MFA-01 | Zweiter Faktor | auth_method = own-password AND (has_privilege_levels = yes OR handles_pii = yes) | recommended |
| SEC-OIDC-01 | Vollständige Token-Validierung: Signatur, Issuer, Audience, Ablauf | auth_method = delegated | required |
| SEC-APIKEY-01 | API-Keys hoch entropisch erzeugt, gehasht abgelegt, widerrufbar, zeitkonstant verglichen | auth_method = api-key | required |
| SEC-SESS-01 | Cookie-Flags HttpOnly, Secure, SameSite | session_transport = cookie | required |
| SEC-SESS-02 | Ablauf, Rotation bei Login und Rechtewechsel, serverseitiger Widerruf | session_transport != none | required |
| SEC-CSRF-01 | Anti-CSRF-Token für zustandsändernde Requests | session_transport = cookie | required |
| SEC-TOKEN-01 | Token-Validierung (Signatur, Algorithmus, Issuer, Audience, Ablauf), Lebensdauer, sichere Ablage im Client, Widerruf | session_transport = bearer-header | required |
| SEC-PII-01 | Datensparsamkeit, Zugriffsprotokoll, Löschkonzept | handles_pii = yes | required |

`required` blocks the plan review's verdict when the plan does not cover it;
`recommended` produces an Important finding without touching the verdict. A
project that rules a measure out sets it to `not-applicable` **in its own spec
block**, with a dated reason — never here.
