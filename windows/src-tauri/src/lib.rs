/// FAL_KEY from the environment, mirroring the macOS app's key priority
/// (env var → saved key file, handled on the JS side).
#[tauri::command]
fn env_fal_key() -> Option<String> {
    std::env::var("FAL_KEY")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![env_fal_key])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
