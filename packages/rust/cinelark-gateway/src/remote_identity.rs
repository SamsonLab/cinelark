use anyhow::{Context, Result};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use rcgen::{CertifiedKey, generate_simple_self_signed};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IdentityMaterial {
    pub certificate_pem: String,
    pub private_key_pem: String,
}

#[derive(Clone, Debug)]
pub struct GatewayIdentity {
    pub material: IdentityMaterial,
    pub fingerprint: String,
}

impl GatewayIdentity {
    pub fn generate() -> Result<Self> {
        let CertifiedKey { cert, signing_key } =
            generate_simple_self_signed(vec!["cinelark.local".to_owned(), "localhost".to_owned()])
                .context("generate Remote TLS identity")?;
        let fingerprint = fingerprint(cert.der().as_ref());
        Ok(Self {
            material: IdentityMaterial {
                certificate_pem: cert.pem(),
                private_key_pem: signing_key.serialize_pem(),
            },
            fingerprint,
        })
    }

    pub fn from_material(material: IdentityMaterial) -> Result<Self> {
        let certificate_der = pem_certificate_der(&material.certificate_pem)?;
        Ok(Self {
            fingerprint: fingerprint(&certificate_der),
            material,
        })
    }

    #[cfg(test)]
    pub(crate) fn certificate_der(&self) -> Result<Vec<u8>> {
        pem_certificate_der(&self.material.certificate_pem)
    }
}

fn pem_certificate_der(pem: &str) -> Result<Vec<u8>> {
    let body = pem
        .lines()
        .filter(|line| !line.starts_with("-----"))
        .collect::<String>();
    base64::engine::general_purpose::STANDARD
        .decode(body)
        .context("decode certificate PEM")
}

fn fingerprint(certificate_der: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(certificate_der))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_identity_has_a_stable_fingerprint_when_reloaded() {
        let generated = GatewayIdentity::generate().unwrap();
        let reloaded = GatewayIdentity::from_material(generated.material.clone()).unwrap();
        assert_eq!(reloaded.fingerprint, generated.fingerprint);
        assert_eq!(generated.fingerprint.len(), 43);
    }
}
