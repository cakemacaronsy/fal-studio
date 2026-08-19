// Port of Sources/Services/Updater.swift, Windows edition: checks GitHub
// Releases (Settings → repo "owner/name") for a release whose version is
// newer than the running app and that carries a Windows installer asset
// (NSIS "-setup.exe" / ".exe" / ".msi"). One click opens the download.

import { create } from "zustand";
import { appVersion, notify, openExternalURL } from "./platform";
import { httpFetch } from "./platform";
import { useSettings } from "./settings";
import { tr } from "./lang";

export type UpdateAvailability =
  | { state: "unknown" }
  | { state: "upToDate" }
  | { state: "remoteRelease"; tag: string; downloadURL: string };

interface UpdaterState {
  availability: UpdateAvailability;
  isChecking: boolean;
  lastError: string | null;
  currentVersion: string;
}

export const useUpdater = create<UpdaterState>(() => ({
  availability: { state: "unknown" },
  isChecking: false,
  lastError: null,
  currentVersion: "…",
}));

export async function initUpdater(): Promise<void> {
  useUpdater.setState({ currentVersion: await appVersion() });
}

export async function checkForUpdates(): Promise<void> {
  useUpdater.setState({ isChecking: true, lastError: null });
  try {
    const remote = await remoteUpdate();
    useUpdater.setState({ availability: remote ?? { state: "upToDate" } });
  } finally {
    useUpdater.setState({ isChecking: false });
  }
}

export async function checkOnLaunch(): Promise<void> {
  await initUpdater();
  await checkForUpdates();
  const availability = useUpdater.getState().availability;
  if (availability.state === "remoteRelease") {
    void notify(
      tr("FAL Studio update available", "FAL Studio 有可用更新"),
      tr(
        "Open FAL Studio and click the update button in the toolbar.",
        "打開 FAL Studio,點工具列的更新按鈕。"
      )
    );
  }
}

export function openRemoteUpdate(): void {
  const availability = useUpdater.getState().availability;
  if (availability.state === "remoteRelease") {
    void openExternalURL(availability.downloadURL);
  }
}

interface GitHubAsset {
  name: string;
  browser_download_url: string;
}

interface GitHubRelease {
  tag_name: string;
  assets: GitHubAsset[];
}

/** Latest GitHub release with a Windows installer asset, when a repo is set. */
async function remoteUpdate(): Promise<UpdateAvailability | null> {
  const repo = useSettings.getState().updateRepo.trim();
  if (!repo || !repo.includes("/")) return null;
  let release: GitHubRelease;
  try {
    const response = await httpFetch(
      `https://api.github.com/repos/${repo}/releases/latest`,
      { headers: { Accept: "application/vnd.github+json" } }
    );
    if (!response.ok) throw new Error(String(response.status));
    release = (await response.json()) as GitHubRelease;
  } catch {
    useUpdater.setState({
      lastError: tr(
        `Could not reach GitHub releases for ${repo}.`,
        `無法讀取 ${repo} 的 GitHub Releases。`
      ),
    });
    return null;
  }
  const tag = release.tag_name.startsWith("v")
    ? release.tag_name.slice(1)
    : release.tag_name;
  if (!isNewer(tag, useUpdater.getState().currentVersion)) return null;
  const installer =
    release.assets.find((a) => a.name.endsWith("-setup.exe")) ??
    release.assets.find((a) => a.name.endsWith(".exe")) ??
    release.assets.find((a) => a.name.endsWith(".msi"));
  if (!installer) return null;
  return {
    state: "remoteRelease",
    tag: release.tag_name,
    downloadURL: installer.browser_download_url,
  };
}

/** Lightweight semver-ish compare: 1.2 > 1.1.9 style, component by component. */
export function isNewer(candidate: string, current: string): boolean {
  const a = candidate.split(".").map((s) => parseInt(s, 10)).filter(Number.isFinite);
  const b = current.split(".").map((s) => parseInt(s, 10)).filter(Number.isFinite);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0;
    const y = b[i] ?? 0;
    if (x !== y) return x > y;
  }
  return false;
}
