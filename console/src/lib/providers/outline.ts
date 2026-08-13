import { getDocument, listCollectionDocuments } from "../outline/client";
import { parseMachineDoc } from "../outline/parseMachineDoc";
import type { Machine, MachineProvider } from "./types";

export class OutlineProvider implements MachineProvider {
  async listMachines(): Promise<Machine[]> {
    const collectionId = process.env.OUTLINE_COLLECTION_ID;
    if (!collectionId) throw new Error("OUTLINE_COLLECTION_ID is not set");

    const summaries = await listCollectionDocuments(collectionId);

    // Fetched in parallel — fine at homelab fleet sizes; revisit with
    // batching/pagination if this collection ever grows into the hundreds.
    return Promise.all(
      summaries.map(async (doc) => {
        const full = await getDocument(doc.id);
        return parseMachineDoc(doc.id, doc.url, full.text);
      })
    );
  }
}
