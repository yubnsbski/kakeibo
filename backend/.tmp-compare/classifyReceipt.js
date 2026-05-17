"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.classifyReceipt = classifyReceipt;
var rules_1 = require("./rules");
var normalizeMerchant_1 = require("./normalizeMerchant");
var AUTO_CONFIDENCE = 0.9;
var MANUAL_REVIEW_CONFIDENCE = 0.4;
var REVIEW_CONFIDENCE = 0;
function findUserOverrideCategory(merchantNormalized, userCategoryOverrides) {
    if (!userCategoryOverrides)
        return null;
    for (var _i = 0, _a = Object.entries(userCategoryOverrides); _i < _a.length; _i++) {
        var _b = _a[_i], merchant = _b[0], category = _b[1];
        var normalizedKey = (0, normalizeMerchant_1.normalizeMerchant)(merchant);
        if (normalizedKey && merchantNormalized.includes(normalizedKey)) {
            return category;
        }
    }
    return null;
}
function matchMerchantRule(merchantNormalized) {
    for (var _i = 0, _a = Object.entries(rules_1.merchantRules); _i < _a.length; _i++) {
        var _b = _a[_i], merchant = _b[0], category = _b[1];
        if (merchantNormalized.includes(merchant)) {
            return { category: category, reason: "merchant_rule: ".concat(merchant) };
        }
    }
    return null;
}
function matchItemRule(items) {
    for (var _i = 0, items_1 = items; _i < items_1.length; _i++) {
        var item = items_1[_i];
        for (var _a = 0, _b = Object.entries(rules_1.itemKeywordRules); _a < _b.length; _a++) {
            var _c = _b[_a], keyword = _c[0], category = _c[1];
            if (item.includes(keyword)) {
                return { category: category, reason: "item_keyword: ".concat(keyword) };
            }
        }
    }
    return null;
}
function classifyReceipt(input) {
    var _a;
    var merchantNormalized = (0, normalizeMerchant_1.normalizeMerchant)(input.merchantRaw);
    var items = (_a = input.items) !== null && _a !== void 0 ? _a : [];
    var isAmbiguous = rules_1.ambiguousMerchants.some(function (merchant) { return merchantNormalized.includes(merchant); });
    var override = findUserOverrideCategory(merchantNormalized, input.userCategoryOverrides);
    if (override) {
        return {
            merchantNormalized: merchantNormalized,
            category: override,
            confidence: 1,
            needsReview: false,
            reason: "user_override: ".concat(override),
            reasons: ["user_override"],
            screeningLabel: "recordable"
        };
    }
    if (isAmbiguous && items.length === 0) {
        return {
            merchantNormalized: merchantNormalized,
            category: null,
            confidence: REVIEW_CONFIDENCE,
            needsReview: true,
            reason: "ambiguous merchant without items",
            reasons: ["ambiguous_merchant_no_items"],
            screeningLabel: "needs_review"
        };
    }
    var merchantMatch = matchMerchantRule(merchantNormalized);
    var itemMatch = merchantMatch ? null : matchItemRule(items);
    var match = merchantMatch !== null && merchantMatch !== void 0 ? merchantMatch : itemMatch;
    if (!match) {
        return {
            merchantNormalized: merchantNormalized,
            category: null,
            confidence: REVIEW_CONFIDENCE,
            needsReview: true,
            reason: "no rule matched",
            reasons: ["no_rule_matched"],
            screeningLabel: "needs_review"
        };
    }
    if (isAmbiguous) {
        return {
            merchantNormalized: merchantNormalized,
            category: null,
            confidence: MANUAL_REVIEW_CONFIDENCE,
            needsReview: true,
            reason: "ambiguous merchant requires manual category",
            reasons: [match.reason, "ambiguous_merchant_with_items"],
            screeningLabel: "needs_review"
        };
    }
    return {
        merchantNormalized: merchantNormalized,
        category: match.category,
        confidence: AUTO_CONFIDENCE,
        needsReview: false,
        reason: "rule_match: ".concat(match.category),
        reasons: [match.reason],
        screeningLabel: "recordable"
    };
}
