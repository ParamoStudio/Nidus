import { Action, ActionPanel, Icon, List, openExtensionPreferences, useNavigation } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { AliasEditor } from "./components/alias-editor";
import { readAliases } from "./lib/aliases";
import type { AliasMap, ProjectRecord } from "./lib/types";
import { loadProjectCatalog } from "./lib/vault";

export default function ManageAliases() {
  const { push } = useNavigation();
  const [vaultPath, setVaultPath] = useState("");
  const [projects, setProjects] = useState<ProjectRecord[]>([]);
  const [aliases, setAliases] = useState<AliasMap>({});
  const [error, setError] = useState<string>();
  const [isLoading, setIsLoading] = useState(true);

  const reload = useCallback(async () => {
    setIsLoading(true);
    setError(undefined);
    try {
      const catalog = await loadProjectCatalog();
      setVaultPath(catalog.vaultPath);
      setProjects(catalog.projects);
      setAliases(await readAliases(catalog.vaultPath));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : String(loadError));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  return (
    <List isLoading={isLoading} navigationTitle="Project Aliases" searchBarPlaceholder="Find a project…">
      {error ? (
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="Nidus vault unavailable"
          description={error}
          actions={
            <ActionPanel>
              <Action title="Try Again" icon={Icon.RotateClockwise} onAction={() => void reload()} />
              <Action title="Open Extension Preferences" icon={Icon.Gear} onAction={openExtensionPreferences} />
            </ActionPanel>
          }
        />
      ) : (
        projects.map((project) => (
          <List.Item
            key={project.key}
            icon={Icon.Tag}
            title={project.name}
            subtitle={project.disciplineName}
            accessories={aliases[project.key]?.length ? [{ tag: aliases[project.key].join(" · ") }] : []}
            actions={
              <ActionPanel>
                <Action
                  title="Edit Aliases"
                  icon={Icon.Pencil}
                  onAction={() =>
                    push(
                      <AliasEditor
                        vaultPath={vaultPath}
                        project={project}
                        initialAliases={aliases[project.key] ?? []}
                      />,
                      () => void reload(),
                    )
                  }
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
