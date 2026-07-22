import { Action, ActionPanel, Form, Icon, Toast, showToast, useNavigation } from "@raycast/api";
import { useState } from "react";
import { AliasError, parseAliases, saveProjectAliases } from "../lib/aliases";
import type { ProjectRecord } from "../lib/types";

type AliasEditorProps = {
  vaultPath: string;
  project: ProjectRecord;
  initialAliases: string[];
};

export function AliasEditor({ vaultPath, project, initialAliases }: AliasEditorProps) {
  const { pop } = useNavigation();
  const [isLoading, setIsLoading] = useState(false);

  async function submit(values: { aliases: string }) {
    setIsLoading(true);
    try {
      const aliases = parseAliases(values.aliases);
      await saveProjectAliases(vaultPath, project.key, aliases);
      await showToast({
        style: Toast.Style.Success,
        title: aliases.length ? "Aliases saved" : "Aliases removed",
        message: project.name,
      });
      pop();
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Could not save aliases",
        message: error instanceof AliasError || error instanceof Error ? error.message : String(error),
      });
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <Form
      isLoading={isLoading}
      navigationTitle={`Aliases · ${project.name}`}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Save Aliases" icon={Icon.Checkmark} onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.Description text={`Aliases enter ${project.name} instantly when followed by a space.`} />
      <Form.TextField id="aliases" title="Aliases" placeholder="bru, glaze" defaultValue={initialAliases.join(", ")} />
      <Form.Description text="Use short, unique, comma-separated tokens. Aliases are shared through the vault." />
    </Form>
  );
}
