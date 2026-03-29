// SPDX-License-Identifier: AGPL-3.0-or-later
import type { NatsConnection } from "nats";

export async function handleArticle(nc: NatsConnection, data: any) {
  const { id, type, attributedTo, name, content, summary, published, updated } = data;
  
  if (type !== "Article") {
    return { error: "not an article" };
  }
  
  // Store article in database via NATS
  await nc.publish("ap.article.store", JSON.stringify({
    ap_id: id,
    actor_uri: attributedTo,
    title: name,
    content: content,
    summary: summary,
    published_at: published,
    updated_at: updated
  }));
  
  return { status: "ok" };
}

export function buildArticle(params: {
  id: string;
  actor: string;
  title: string;
  content: string;
  summary?: string;
  published?: string;
}) {
  return {
    "@context": "https://www.w3.org/ns/activitystreams",
    type: "Article",
    id: params.id,
    attributedTo: params.actor,
    name: params.title,
    content: params.content,
    summary: params.summary,
    published: params.published || new Date().toISOString(),
    to: ["https://www.w3.org/ns/activitystreams#Public"]
  };
}
