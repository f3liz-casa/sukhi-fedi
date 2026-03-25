import { Undo, fetchDocumentLoader } from "@fedify/fedify";

export interface UndoPayload {
  actor: string;
  object: string; // AP ID of the activity to undo
}

export interface UndoResult {
  activity: unknown;
  recipientInboxes: string[];
}

export async function handleUndo(payload: UndoPayload): Promise<UndoResult> {
  const documentLoader = fetchDocumentLoader;
  
  // Fetch the original activity
  const objectDoc = await documentLoader(payload.object);
  const originalActivity = objectDoc.document;
  
  const undo = new Undo({
    id: new URL(`${payload.actor}/undo/${crypto.randomUUID()}`),
    actor: new URL(payload.actor),
    object: originalActivity,
  });

  const activityJson = await undo.toJsonLd({ contextLoader: documentLoader });
  
  // Extract inboxes from the original activity's targets
  let inboxes: string[] = [];
  const targetUri = originalActivity["object"];
  
  if (targetUri) {
    try {
      const targetDoc = await documentLoader(targetUri);
      const actorUri = targetDoc.document["actor"] || targetDoc.document["attributedTo"];
      
      if (actorUri) {
        const actorDoc = await documentLoader(actorUri);
        const inbox = actorDoc.document["inbox"];
        if (inbox) inboxes.push(inbox);
      }
    } catch {
      // If we can't resolve the target, try the object directly
      if (originalActivity["actor"]) {
        const actorDoc = await documentLoader(originalActivity["actor"]);
        const inbox = actorDoc.document["inbox"];
        if (inbox) inboxes.push(inbox);
      }
    }
  }

  return {
    activity: activityJson,
    recipientInboxes: inboxes,
  };
}
