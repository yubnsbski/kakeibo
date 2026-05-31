const API_BASE = "/api";

export type EncryptedTxRow = {
  id: number;
  encrypted_payload: string;
  payload_version: number;
  created_at: string;
  updated_at: string;
};

export async function fetchEncryptedTx(): Promise<EncryptedTxRow[]> {
  const res = await fetch(`${API_BASE}/encrypted-tx`);
  if (!res.ok) {
    throw new Error(`encrypted tx 取得失敗: HTTP ${res.status}`);
  }
  return res.json();
}

export async function createEncryptedTx(
  encryptedPayload: string,
  payloadVersion = 1,
): Promise<EncryptedTxRow> {
  const res = await fetch(`${API_BASE}/encrypted-tx`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      encrypted_payload: encryptedPayload,
      payload_version: payloadVersion,
    }),
  });

  if (!res.ok) {
    throw new Error(`encrypted tx 保存失敗: HTTP ${res.status}`);
  }

  return res.json();
}

export async function updateEncryptedTx(
  id: number,
  encryptedPayload: string,
  payloadVersion = 1,
): Promise<EncryptedTxRow> {
  const res = await fetch(`${API_BASE}/encrypted-tx/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      encrypted_payload: encryptedPayload,
      payload_version: payloadVersion,
    }),
  });

  if (!res.ok) {
    throw new Error(`encrypted tx 更新失敗: HTTP ${res.status}`);
  }

  return res.json();
}

export async function deleteEncryptedTx(id: number): Promise<void> {
  const res = await fetch(`${API_BASE}/encrypted-tx/${id}`, {
    method: "DELETE",
  });

  if (!res.ok) {
    throw new Error(`encrypted tx 削除失敗: HTTP ${res.status}`);
  }
}
