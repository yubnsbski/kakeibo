export function normalizeMerchant(raw: string): string {
  const text = raw
    .trim()
    .replace(/\s+/g, "")
    .replace(/ｾﾌﾞﾝ[-ー]?ｲﾚﾌﾞﾝ/g, "セブンイレブン")
    .replace(/セブン[-ー]?イレブン/g, "セブンイレブン")
    .replace(/ファミマ/g, "ファミリーマート")
    .replace(/ﾏﾂｷﾖ/g, "マツモトキヨシ")
    .replace(/ドン・キホーテ/g, "ドンキホーテ");

  return text;
}
