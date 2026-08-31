use reqwest::Method;
use serde_json::{json, Value};
use tauri::State;
use url::Url;

use crate::{app_state::AppState, relay};

const MAX_LOCAL_COMMUNITY_NAME_LENGTH: usize = 63;

fn normalized_community_name(name: &str) -> Result<String, String> {
    let normalized_name = name.trim().to_ascii_lowercase();
    if normalized_name.is_empty()
        || normalized_name.len() > MAX_LOCAL_COMMUNITY_NAME_LENGTH
        || !normalized_name.chars().all(|character| {
            character.is_ascii_lowercase() || character.is_ascii_digit() || character == '-'
        })
        || normalized_name.starts_with('-')
        || normalized_name.ends_with('-')
        || normalized_name.contains("--")
    {
        return Err(
            "Use lowercase letters, numbers, and hyphens for the community name.".to_owned(),
        );
    }
    Ok(normalized_name)
}

fn relay_origin(active_relay_url: &str) -> Result<Url, String> {
    let mut parsed =
        Url::parse(active_relay_url).map_err(|_| "The active relay URL is invalid.".to_owned())?;
    if !matches!(parsed.scheme(), "ws" | "wss" | "http" | "https") {
        return Err("The active relay URL must use ws:// or wss://.".to_owned());
    }
    if parsed.host_str().is_none() {
        return Err("The active relay URL has no host.".to_owned());
    }
    parsed.set_path("");
    parsed.set_query(None);
    parsed.set_fragment(None);
    Ok(parsed)
}

pub(crate) fn community_relay_url(active_relay_url: &str, name: &str) -> Result<String, String> {
    let normalized_name = normalized_community_name(name)?;
    let mut parsed = relay_origin(active_relay_url)?;
    let scheme = match parsed.scheme() {
        "ws" | "http" => "ws",
        "wss" | "https" => "wss",
        _ => unreachable!("relay_origin validates the URL scheme"),
    };
    parsed
        .set_scheme(scheme)
        .map_err(|_| "The active relay URL scheme is invalid.".to_owned())?;
    parsed.set_path(&format!("/c/{normalized_name}"));
    Ok(parsed.to_string().trim_end_matches('/').to_owned())
}

fn community_host(active_relay_url: &str, name: &str) -> Result<String, String> {
    let normalized_name = normalized_community_name(name)?;
    let parsed = relay_origin(active_relay_url)?;
    let host = parsed
        .host_str()
        .ok_or_else(|| "The active relay URL has no host.".to_owned())?;
    let port = parsed
        .port()
        .map(|port| format!(":{port}"))
        .unwrap_or_default();
    Ok(format!("{normalized_name}.{host}{port}"))
}

fn local_http_url(active_relay_url: &str, path: &str) -> Result<String, String> {
    let parsed = relay_origin(active_relay_url)?;
    let scheme = match parsed.scheme() {
        "ws" | "http" => "http",
        "wss" | "https" => "https",
        _ => return Err("The active relay URL must use ws:// or wss://.".to_owned()),
    };
    let host = parsed
        .host_str()
        .ok_or_else(|| "The active relay URL has no host.".to_owned())?;
    let host = if host.contains(':') {
        format!("[{host}]")
    } else {
        host.to_owned()
    };
    let authority = match parsed.port() {
        Some(port) => format!("{host}:{port}"),
        None => host,
    };
    Ok(format!("{scheme}://{authority}{path}"))
}

fn provisioning_relay_url(state: &AppState, relay_url: Option<&str>) -> String {
    relay_url
        .map(str::trim)
        .filter(|url| !url.is_empty())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| relay::relay_ws_url_with_override(state))
}

#[tauri::command]
pub(crate) async fn check_local_community_name(
    name: String,
    relay_url: Option<String>,
    state: State<'_, AppState>,
) -> Result<Value, String> {
    let active_relay_url = provisioning_relay_url(&state, relay_url.as_deref());
    let host = community_host(&active_relay_url, &name)?;
    let encoded_host: String = url::form_urlencoded::byte_serialize(host.as_bytes()).collect();
    let url = local_http_url(
        &active_relay_url,
        &format!("/local/communities/availability?host={encoded_host}"),
    )?;
    let auth = relay::build_nip98_auth_header(&Method::GET, &url, &[], &state)?;
    let response = state
        .http_client
        .get(&url)
        .header("Authorization", auth)
        .send()
        .await
        .map_err(|error| relay::classify_request_error(&error))?;
    if !response.status().is_success() {
        return Err(relay::relay_error_message(response).await);
    }
    relay::parse_json_response(response).await
}

#[tauri::command]
pub(crate) async fn create_local_community(
    name: String,
    relay_url: Option<String>,
    state: State<'_, AppState>,
) -> Result<Value, String> {
    let active_relay_url = provisioning_relay_url(&state, relay_url.as_deref());
    let host = community_host(&active_relay_url, &name)?;
    let url = local_http_url(&active_relay_url, "/local/communities")?;
    let body = serde_json::to_vec(&json!({ "host": host }))
        .map_err(|error| format!("local community request serialization failed: {error}"))?;
    let auth = relay::build_nip98_auth_header(&Method::POST, &url, &body, &state)?;
    let response = state
        .http_client
        .post(&url)
        .header("Authorization", auth)
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .map_err(|error| relay::classify_request_error(&error))?;
    if !response.status().is_success() {
        return Err(relay::relay_error_message(response).await);
    }
    let mut payload = relay::parse_json_response(response).await?;
    if let Value::Object(ref mut object) = payload {
        object.insert(
            "relay_url".to_owned(),
            Value::String(community_relay_url(&active_relay_url, &name)?),
        );
    }
    Ok(payload)
}

#[cfg(test)]
mod tests {
    use super::{community_host, community_relay_url};

    #[test]
    fn derives_a_path_scoped_zion_relay_url_from_the_active_relay() {
        assert_eq!(
            community_relay_url("wss://zion-coms.tail1bd36d.ts.net", "north-star")
                .expect("community relay URL"),
            "wss://zion-coms.tail1bd36d.ts.net/c/north-star"
        );
    }

    #[test]
    fn preserves_a_local_relay_without_using_a_localhost_subdomain() {
        assert_eq!(
            community_relay_url("ws://localhost:3000", "north-star").expect("community relay URL"),
            "ws://localhost:3000/c/north-star"
        );
    }

    #[test]
    fn derives_the_host_key_used_by_the_relay_database() {
        assert_eq!(
            community_host("wss://zion-coms.tail1bd36d.ts.net", "north-star")
                .expect("community host"),
            "north-star.zion-coms.tail1bd36d.ts.net"
        );
    }

    #[test]
    fn rejects_invalid_names_before_the_relay_request() {
        let error = community_relay_url("wss://zion-coms.tail1bd36d.ts.net", "North Star")
            .expect_err("invalid name must be rejected");
        assert!(error.contains("lowercase letters, numbers, and hyphens"));
    }
}
