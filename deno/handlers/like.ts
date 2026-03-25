import { Like, fetchDocumentLoader } from "@fedify/fedify";

export interface LikePayload {
  actor: string;
  object: string;
}

export interface LikeResult {
  activity: unknown;
  recipientInboxes: string[];
}

export async function handleLike(payload: LikePayload): Promise<LikeResult> {
  const documentLoader = fetchDocumentLoader;
  
  const like = new Like({
    id: new URL(`${payload.actor}/likes/${crypto.randomUUID()}`),
    actor: new URL(payload.actor),
    object: new URL(payload.object),
  });

  const activityJson = await like.toJsonLd({ contextLoader: documentLoader });
  
  // Extract inbox from the object's actor
  const objectDoc = await documentLoader(payload.object);
  const actorUri = objectDoc.document["actor"] || objectDoc.document["attributedTo"];
  
  let inboxes: string[] = [];
  if (actorUri) {
    const actorDoc = await documentLoader(actorUri);
    const inbox = actorDoc.document["inbox"];
    if (inbox) inboxes.push(inbox);
  }

  return {
    activity: activityJson,
    recipientInboxes: inboxes,
  };
}
