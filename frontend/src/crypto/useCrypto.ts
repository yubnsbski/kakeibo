/**
 * 暗号鍵の状態を React コンポーネントから扱うための hook。
 *
 * keyStore (crypto/keyStore.ts) はモジュールスコープのシングルトンだが、
 * React の再レンダリングと連動させるためにこの hook で購読する。
 */
import { useEffect, useState } from "react";
import { isUnlocked, subscribeLockState } from "./index";

/**
 * アンロック状態 (鍵がメモリにあるか) を購読する。
 *
 * @returns unlocked - true ならアンロック済み
 */
export function useUnlocked(): boolean {
  const [unlocked, setUnlocked] = useState<boolean>(isUnlocked());

  useEffect(() => {
    // 購読開始時に最新状態へ同期 (購読前に状態が変わっていた場合の保険)。
    setUnlocked(isUnlocked());
    const unsubscribe = subscribeLockState(setUnlocked);
    return unsubscribe;
  }, []);

  return unlocked;
}
