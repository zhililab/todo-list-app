# App Store JWS test PKI

Deterministic, checked-in test data only. These certificates are not issued by Apple and must never become production trust anchors.

- The tests inject `root-cert.pem` explicitly; a separate assertion proves the production default rejects it.
- Production modules never import this directory.
- Only the two leaf signing keys needed to build test JWS values are retained. Root/intermediate private keys and CSRs are intentionally absent.
- The fixed test clock is `2027-01-01T00:00:00Z`. The leaf is valid 2026-08-11 through 2036-08-08; the expired-certificate case uses `signedDate`/clock `2037-01-01T00:00:00Z`.
- The default valid leaf has critical Basic Constraints/Key Usage and the test Apple leaf OID, but no critical EKU.
- The otherwise-valid attack certificates cover critical EKU/unknown OIDs, Apple purpose OIDs on the wrong leaf/intermediate/root role, and a leaf carrying `digitalSignature` plus `keyAgreement`. Their generation profiles are retained beside them.

The fixture private keys are public test material. Never reuse them outside these tests.
