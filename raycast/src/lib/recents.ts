import { LocalStorage } from "@raycast/api";

const RECENTS_KEY = "nidus.recent.projects";
const MAX_RECENTS = 20;

export async function readRecentProjectKeys(): Promise<string[]> {
  const stored = await LocalStorage.getItem<string>(RECENTS_KEY);
  if (!stored) return [];
  try {
    const parsed = JSON.parse(stored);
    return Array.isArray(parsed) ? parsed.filter((value): value is string => typeof value === "string") : [];
  } catch {
    return [];
  }
}

export async function markProjectRecent(projectKey: string): Promise<void> {
  const current = await readRecentProjectKeys();
  const next = [projectKey, ...current.filter((key) => key !== projectKey)].slice(0, MAX_RECENTS);
  await LocalStorage.setItem(RECENTS_KEY, JSON.stringify(next));
}
