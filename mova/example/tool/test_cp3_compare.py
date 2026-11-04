import unittest
from cp3_compare import compare, read_rows

def ledger(**rows):
    return {'rows': [dict(id=k, status=v) for k, v in rows.items()]}

class CompareTests(unittest.TestCase):
    def test_regressions(self):
        r = compare(ledger(a='PASS', b='BLOCKED', c='FAIL'), ledger(a='FAIL', b='BLOCKED', c='FAIL', d='BLOCKED'))
        self.assertEqual(r['newFail'], ['a'])
        self.assertEqual(r['newBlocked'], ['d'])
        self.assertEqual(r['retainedBlocked'], ['b'])
        self.assertFalse(r['passed'])
    def test_missing_is_not_success(self):
        r = compare(ledger(a='PASS', b='BLOCKED'), ledger(a='PASS'))
        self.assertEqual(r['missing'], ['b'])
        self.assertFalse(r['passed'])
    def test_improvements_and_legacy_rows(self):
        self.assertTrue(compare([['a','FAIL'], ['b','BLOCKED']], ledger(a='PASS',b='PASS'))['passed'])
    def test_invalid(self):
        for data in ([], {}, ledger(a='MEASURED'), [['a','PASS'],['a','FAIL']]):
            with self.assertRaises(ValueError): read_rows(data)

if __name__ == '__main__': unittest.main()
