import unittest

from kakeibo.normalize_merchant import normalize_merchant


class NormalizeMerchantTests(unittest.TestCase):
    def test_half_width_seven_eleven(self):
        self.assertEqual(normalize_merchant("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店"), "セブンイレブン渋谷店")

    def test_full_width_seven_eleven(self):
        self.assertEqual(normalize_merchant("セブン-イレブン 新宿店"), "セブンイレブン新宿店")

    def test_familymart_alias(self):
        self.assertEqual(normalize_merchant("ファミマ 船橋店"), "ファミリーマート船橋店")

    def test_donki_dot_removed(self):
        self.assertEqual(normalize_merchant("ドン・キホーテ"), "ドンキホーテ")


if __name__ == "__main__":
    unittest.main()
