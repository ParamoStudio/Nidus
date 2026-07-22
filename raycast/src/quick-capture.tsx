import {
  Action,
  ActionPanel,
  Icon,
  List,
  PopToRootType,
  Toast,
  openExtensionPreferences,
  showHUD,
  showToast,
  useNavigation,
} from "@raycast/api";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AliasEditor } from "./components/alias-editor";
import { readAliases } from "./lib/aliases";
import { appendCapture, hasTaskPrefix, parseCaptureInput } from "./lib/capture";
import { markProjectRecent, readRecentProjectKeys } from "./lib/recents";
import { projectForExactAlias, rankProjects } from "./lib/search";
import type { AliasMap, ProjectRecord } from "./lib/types";
import { loadProjectCatalog } from "./lib/vault";

type ProjectData = {
  vaultPath: string;
  projects: ProjectRecord[];
  aliases: AliasMap;
  recents: string[];
};

export default function QuickCapture() {
  const { push } = useNavigation();
  const [data, setData] = useState<ProjectData>();
  const [error, setError] = useState<string>();
  const [isLoading, setIsLoading] = useState(true);
  const [searchText, setSearchText] = useState("");
  const lastAliasTrigger = useRef("");

  const reload = useCallback(async () => {
    setIsLoading(true);
    setError(undefined);
    try {
      const catalog = await loadProjectCatalog();
      const [aliases, recents] = await Promise.all([readAliases(catalog.vaultPath), readRecentProjectKeys()]);
      setData({ ...catalog, aliases, recents });
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : String(loadError));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const projects = useMemo(
    () => rankProjects(data?.projects ?? [], searchText, data?.aliases ?? {}, data?.recents ?? []),
    [data, searchText],
  );

  function openProject(project: ProjectRecord) {
    void markProjectRecent(project.key);
    push(<CaptureProject project={project} />);
  }

  function editAliases(project: ProjectRecord) {
    if (!data) return;
    push(
      <AliasEditor vaultPath={data.vaultPath} project={project} initialAliases={data.aliases[project.key] ?? []} />,
      () => void reload(),
    );
  }

  function changeSearchText(value: string) {
    setSearchText(value);
    if (!data || !value.endsWith(" ")) {
      lastAliasTrigger.current = "";
      return;
    }

    const project = projectForExactAlias(data.projects, data.aliases, value.trim());
    if (project && lastAliasTrigger.current !== value) {
      lastAliasTrigger.current = value;
      openProject(project);
    }
  }

  return (
    <List
      isLoading={isLoading}
      filtering={false}
      navigationTitle="Nidus"
      searchBarPlaceholder="Project, discipline, or alias…"
      searchText={searchText}
      onSearchTextChange={changeSearchText}
    >
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
      ) : !isLoading && projects.length === 0 ? (
        <List.EmptyView
          icon={Icon.MagnifyingGlass}
          title={searchText.trim() ? "No matching projects" : "No projects in this vault"}
          description="Search by project, discipline, or one of your aliases."
        />
      ) : (
        projects.map((project) => {
          const aliases = data?.aliases[project.key] ?? [];
          return (
            <List.Item
              key={project.key}
              id={project.key}
              icon={Icon.Folder}
              title={project.name}
              subtitle={project.disciplineName}
              accessories={[
                ...(aliases.length ? [{ tag: aliases.join(" · "), tooltip: "Aliases" }] : []),
                ...(project.lastActivity ? [{ date: new Date(project.lastActivity), tooltip: "Last activity" }] : []),
              ]}
              actions={
                <ActionPanel>
                  <Action title="Enter Project" icon={Icon.ArrowRight} onAction={() => openProject(project)} />
                  <Action
                    title="Set Aliases"
                    icon={Icon.Tag}
                    shortcut={{ modifiers: ["cmd", "shift"], key: "a" }}
                    onAction={() => editAliases(project)}
                  />
                  <Action title="Refresh Projects" icon={Icon.RotateClockwise} onAction={() => void reload()} />
                </ActionPanel>
              }
            />
          );
        })
      )}
    </List>
  );
}

function CaptureProject({ project }: { project: ProjectRecord }) {
  const [text, setText] = useState("");
  const [defaultDestination, setDefaultDestination] = useState<"inbox" | "task">("inbox");
  const [isLoading, setIsLoading] = useState(false);
  const capture = parseCaptureInput(text, defaultDestination);
  const effectiveDestination = capture?.destination ?? (hasTaskPrefix(text) ? "task" : defaultDestination);

  function changeDestination(value: string) {
    const destination = value === "task" ? "task" : "inbox";
    setDefaultDestination(destination);
    if (destination === "inbox" && hasTaskPrefix(text)) {
      setText(text.trim().replace(/^t-\s*/i, ""));
    }
  }

  async function submit() {
    if (!capture || isLoading) return;
    setIsLoading(true);
    try {
      await appendCapture(project, capture);
      await markProjectRecent(project.key);
      const destination = capture.destination === "task" ? "Tasks" : "Inbox";
      await showHUD(`Captured in ${project.name} · ${destination}`, {
        clearRootSearch: true,
        popToRootType: PopToRootType.Immediate,
      });
    } catch (writeError) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Could not capture to Inbox",
        message: writeError instanceof Error ? writeError.message : String(writeError),
      });
      setIsLoading(false);
    }
  }

  return (
    <List
      isLoading={isLoading}
      filtering={false}
      navigationTitle={project.name}
      searchBarPlaceholder="Title -- optional note"
      searchText={text}
      onSearchTextChange={setText}
      searchBarAccessory={
        <List.Dropdown tooltip="Capture Destination" value={effectiveDestination} onChange={changeDestination}>
          <List.Dropdown.Item title="Inbox" value="inbox" icon={Icon.Tray} />
          <List.Dropdown.Item title="Task" value="task" icon={Icon.CheckCircle} />
        </List.Dropdown>
      }
    >
      <List.Section title="Capture" subtitle={project.name}>
        {capture ? (
          <List.Item
            id="capture"
            icon={capture.destination === "task" ? Icon.CheckCircle : Icon.PlusCircle}
            title={capture.title}
            subtitle={capture.body || `${capture.destination === "task" ? "Task" : "Inbox"} · no note`}
            accessories={[{ tag: capture.destination === "task" ? "Task" : "Inbox" }]}
            actions={
              <ActionPanel>
                <Action
                  title={capture.destination === "task" ? "Add Task" : "Capture in Inbox"}
                  icon={capture.destination === "task" ? Icon.CheckCircle : Icon.Tray}
                  onAction={() => void submit()}
                />
              </ActionPanel>
            }
          />
        ) : null}
      </List.Section>
      <List.Section title="Quick Syntax" subtitle="No prefix → Inbox · t- → Task · -- → Note">
        <List.Item
          id="capture-help"
          icon={Icon.Info}
          title="Title -- optional note"
          subtitle="Start with t- to create a task"
          actions={
            capture ? (
              <ActionPanel>
                <Action
                  title={capture.destination === "task" ? "Add Task" : "Capture in Inbox"}
                  icon={capture.destination === "task" ? Icon.CheckCircle : Icon.Tray}
                  onAction={() => void submit()}
                />
              </ActionPanel>
            ) : undefined
          }
        />
      </List.Section>
    </List>
  );
}
