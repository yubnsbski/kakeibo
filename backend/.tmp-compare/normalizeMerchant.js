"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeMerchant = normalizeMerchant;
function normalizeMerchant(raw) {
    var text = raw
        .trim()
        .replace(/\s+/g, "")
        .replace(/ｾﾌﾞﾝ[-ー]?ｲﾚﾌﾞﾝ/g, "セブンイレブン")
        .replace(/セブン[-ー]?イレブン/g, "セブンイレブン")
        .replace(/ファミマ/g, "ファミリーマート")
        .replace(/ﾏﾂｷﾖ/g, "マツモトキヨシ")
        .replace(/ドン・キホーテ/g, "ドンキホーテ");
    return text;
}
