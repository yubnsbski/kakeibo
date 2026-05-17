from typing import Literal, TypedDict, Optional

Category = Literal["食費", "日用品", "交通", "医療", "通信", "娯楽", "教育", "その他"]
ScreeningLabel = Literal["recordable", "needs_review"]

class ReceiptInput(TypedDict, total=False):
    merchantRaw: str
    items: list[str]
    totalAmount: float
    purchasedAt: str
    userCategoryOverrides: dict[str, Category]

class ClassificationResult(TypedDict):
    merchantNormalized: str
    category: Optional[Category]
    confidence: float
    needsReview: bool
    reason: str
    reasons: list[str]
    screeningLabel: ScreeningLabel
