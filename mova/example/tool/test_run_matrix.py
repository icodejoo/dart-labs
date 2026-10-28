"""Offline regression tests: no adb, Flutter or device access.

纯 Python 回归单测，不连接设备、不运行 Flutter。
"""
import ast
import contextlib
import copy
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import matrix_compat
import run_matrix as matrix


class MatrixTests(unittest.TestCase):
    """Test manifest, selection, verdicts and report logic / 测清单、选择、判定和汇总。"""
    def setUp(self):
        """Read only the manifest / 只读清单。"""
        self.manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))

    def test_real_manifest(self):
        """Require exactly the canonical 135 IDs / 必须覆盖规范的135编号。"""
        self.assertEqual(matrix.validate_manifest(self.manifest),[])
        self.assertEqual(len(self.manifest['ids']),135)

    def test_extended_ids_do_not_change_legacy_coverage(self):
        """§10/H extensions validate independently of the canonical 135 IDs."""
        batch = self.manifest['batches'][-1]
        batch['covers_ext'] = ['G1.1', 'G2.3', 'S16', 'P21', 'A35', 'H1', 'H78']
        self.assertEqual(matrix.validate_manifest(self.manifest), [])
        batch['covers_ext'].append('H79')
        self.assertTrue(any('未知扩展' in e for e in matrix.validate_manifest(self.manifest)))
        batch['covers_ext'] = ['G99.9']
        self.assertTrue(any('未知扩展' in e for e in matrix.validate_manifest(self.manifest)))
        batch['covers_ext'] = 'H28'
        self.assertTrue(any('covers_ext' in e for e in matrix.validate_manifest(self.manifest)))

    def test_gap_completion_distinguishes_product_and_harness(self):
        result=dict(run_id='unit',group='random',completed=True,harness=[],
                    verdicts=[dict(case='gap:G4.1.seed',status='FAIL')])
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'OK')
        result['verdicts'][0]['status']='BLOCKED'
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'OK')
        result['completed']=False
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'BLOCKED')
        result['harness']=['uncaught exception']
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',1),'HARNESS')
        self.assertEqual(matrix.gap_result_kind(result,'unit','random',2),'HARNESS')
        with self.assertRaises(ValueError):matrix.gap_result_kind(result,'old','random',0)
        result['verdicts'][0]['status']='INVALID'
        with self.assertRaises(ValueError):matrix.gap_result_kind(result,'unit','random',0)

    def test_skin_batch_wired_to_driver_group(self):
        """gap-skin covers the S-ids it runs and targets a group the driver accepts."""
        batch=next(b for b in self.manifest['batches'] if b['id']=='gap-skin')
        self.assertTrue({'S1','S7','S9','S12','S13','S14'}<=set(batch['covers_ext']))
        self.assertFalse(batch['fast'])
        self.assertTrue(batch['screen_on'] and batch['native_driver'])
        source=ast.parse((matrix.TOOL/'coverage_gap.py').read_text(encoding='utf-8'))
        choices=[a.value for n in ast.walk(source) if isinstance(n,ast.Call)
                 and isinstance(n.func,ast.Attribute) and n.func.attr=='add_argument'
                 and n.args and isinstance(n.args[0],ast.Constant) and n.args[0].value=='group'
                 for kw in n.keywords if kw.arg=='choices' for a in kw.value.elts]
        self.assertIn(batch['argv'][2],choices)
        flags={a.value for n in ast.walk(source) if isinstance(n,ast.Call)
               and isinstance(n.func,ast.Attribute) and n.func.attr=='add_argument'
               for a in n.args if isinstance(a,ast.Constant) and str(a.value).startswith('--')}
        self.assertIn('--skins',flags)

    def test_native_driver_requires_owned_metadata(self):
        batch=next(b for b in self.manifest['batches'] if b.get('native_driver'))
        del batch['result_path']
        self.assertTrue(any('native_driver' in e for e in matrix.validate_manifest(self.manifest)))

    def test_missing_coverage(self):
        """Reject uncovered and unknown IDs / 拒绝遗漏和未知编号。"""
        for b in self.manifest['batches']:
            b['covers']=[i for i in b['covers'] if i!='A1']
        self.assertTrue(any('覆盖缺失' in e for e in matrix.validate_manifest(self.manifest)))
        self.manifest['batches'][0]['covers'].append('A999')
        self.assertTrue(any('未知' in e for e in matrix.validate_manifest(self.manifest)))

    def test_duplicate_and_dependency(self):
        """Reject duplicate names and forward dependencies / 拒绝重名和前向依赖。"""
        self.manifest['batches'][1]['id']=self.manifest['batches'][0]['id']
        self.manifest['batches'][0]['dependencies'].append('missing')
        errors=matrix.validate_manifest(self.manifest)
        self.assertTrue(any('重复' in e for e in errors))
        self.assertTrue(any('依赖' in e for e in errors))

    def test_invalid_commands(self):
        """Reject missing scripts, shell strings and flags / 拒绝缺脚本、shell字符串及错参数。"""
        for command in ('python tool.py', ['{python}','{tool}/absent.py'], ['{python}','{tool}/coverage_device.py','--bad-option']):
            m=copy.deepcopy(self.manifest)
            m['batches'][0]['argv']=command
            self.assertTrue(matrix.validate_manifest(m))

    def test_select_only_dependencies(self):
        """Keep launch dependencies in manifest order / 按清单顺序补启动依赖。"""
        jobs=matrix.select_batches(self.manifest,'native-inputs')
        self.assertEqual([b['id'] for b in jobs],['api-launch','native-inputs'])

    def test_select_from_fast_and_unknown(self):
        """Check continuation, fast intersection and unknown names / 检查续跑、fast交集和未知批次。"""
        names=[b['id'] for b in matrix.select_batches(self.manifest,start='final-api',fast=True)]
        self.assertIn('api-launch',names)
        self.assertIn('final-api',names)
        self.assertNotIn('api',names)
        with self.assertRaises(ValueError):matrix.select_batches(self.manifest,'unknown')
        with self.assertRaises(ValueError):matrix.select_batches(self.manifest,start='unknown')

    def test_compare_all_transitions(self):
        """Test each comparison category / 测所有对比类别。"""
        before={'rows':[dict(id=i,status=s) for i,s in [('a','PASS'),('b','FAIL'),('c','FAIL'),('d','BLOCKED'),('e','PASS'),('f','BLOCKED')]]}
        rows=[dict(id=i,status=s) for i,s in [('a','FAIL'),('b','PASS'),('c','FAIL'),('d','BLOCKED'),('e','BLOCKED'),('f','PASS')]]
        result=matrix.compare_ledgers(rows,before)
        self.assertEqual(result,dict(zip(('新增失败','已修复','仍失败','仍阻塞','新增阻塞','已解除阻塞'),[['a'],['b'],['c'],['d'],['e'],['f']])))

    def test_no_inherited_pass(self):
        """Never inherit old PASS, or upgrade a failed harness / 不继承PASS或掩盖验证器失败。"""
        rows=matrix.make_rows(self.manifest,{}, {'A4':dict(status='PASS',evidence='old')})
        self.assertEqual(len(rows),135)
        self.assertTrue(all(r['status']=='BLOCKED' for r in rows))
        results={b['id']:dict(kind='OK',driver='fresh.driver.log') for b in self.manifest['batches']}
        explicit={'A4':dict(status='FAIL',evidence='fresh CHECK')}
        rows=matrix.make_rows(self.manifest,results,explicit)
        self.assertEqual(next(r for r in rows if r['id']=='A4')['status'],'FAIL')
        results['api']['kind']='HARNESS'
        self.assertEqual(next(r for r in matrix.make_rows(self.manifest,results,explicit) if r['id']=='A4')['status'],'BLOCKED')

    def test_markdown_summary(self):
        """Render all rows, comparison and harness diagnostics / 渲染全台账、对比与验证器错误。"""
        rows=matrix.make_rows(self.manifest,{}, {})
        text=matrix.render_summary('unit',rows,{'新增失败':[]},{'api':dict(kind='HARNESS',error='timeout',driver='api.driver.log')},'baseline.json')
        self.assertEqual(len(re.findall(r'^\| (?:[ACUFN]\d+|E\.\w+|E[12]) \| BLOCKED \|',text,re.M)),135)
        self.assertIn('timeout',text)
        self.assertIn('最小复现',text)

    def test_screen_markers(self):
        """Reject missing, locked and sleeping screen states / 拒绝缺标记、锁屏和灭屏。"""
        self.assertTrue(matrix.is_unlocked('isKeyguardShowing=false mScreenOnFully=true'))
        for text in ('','isKeyguardShowing=true mScreenOnFully=true','mScreenOnFully=true','isKeyguardShowing=false mScreenOnFully=false'):
            self.assertFalse(matrix.is_unlocked(text))

    def test_media_fixtures_are_seeded(self):
        """Isolated media dir gets truncated/vod/subtitle fixtures / 隔离媒体目录补入静态夹具。"""
        with tempfile.TemporaryDirectory() as tmp:
            seeded=matrix_compat.seed_media(tmp,'matrix-unit-')
            target=Path(tmp)/'matrix-unit-coverage_media'
            for name in seeded:
                self.assertTrue((target/name).is_file())
            self.assertEqual(matrix_compat.seed_media(tmp,'matrix-unit-'),[])  # 幂等
            if (matrix.TOOL/'coverage_media/truncated.mp4').is_file():
                self.assertIn('truncated.mp4',seeded)

    def test_gap_screen_runs_last_and_locks(self):
        """The screen-locking batch must be last / 锁屏批次必须排在最后。"""
        last=self.manifest['batches'][-1]
        self.assertEqual(last['id'],'gap-screen')
        self.assertTrue(last.get('locks_screen'))

    def test_compat_paths_are_isolated(self):
        """Transform path constants without changing logic / 只改路径而不改判定。"""
        out=matrix.TOOL/'coverage_evidence/matrix-unit'
        source="O=ROOT/'example/tool/coverage_evidence'\nD=ROOT/'doc/plans/old.md'\npass_value=False\n"
        tree=matrix_compat.transform(source,str(matrix.TOOL/'legacy.py'),out,'matrix-unit-')
        values=[n.value for n in ast.walk(tree) if isinstance(n,ast.Constant)]
        self.assertIn(str(out),values)
        self.assertIn(str(out/'matrix-unit-checkpoints.md'),values)
        self.assertIn(False,values)

    def test_existing_full_id_checks(self):
        """Require both engines and trim accumulated records / 要求两实现并切除累计旧记录。"""
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            out=Path(folder)
            records=[dict(kind='CHECK',id='A4',**{'pass':False}),dict(kind='BEGIN'),dict(kind='CHECK',id='A4',**{'pass':True})]
            for suffix in ('rerun-batch15-basic.json','rerun-batch15-basic-cutover.json'):
                (out/('matrix-unit-'+suffix)).write_text(json.dumps(dict(records=records)),encoding='utf-8')
            verdicts=matrix.existing_verdicts(out,'matrix-unit-')
            self.assertEqual(verdicts['A4']['status'],'PASS')
            self.assertNotIn('A22',verdicts)
            (out/'matrix-unit-rerun-batch15-basic.json').unlink()
            self.assertEqual(matrix.existing_verdicts(out,'matrix-unit-'),{})

    def test_offline_modes_have_no_side_effects(self):
        """Fail tests on any attempted subprocess/socket/write / 任何进程、端口或写入即失败。"""
        for args in (['--check'],['--list'],['--dry-run','--fast','--run-id','unit']):
            with self.subTest(args=args), patch.object(matrix,'Driver',side_effect=AssertionError('device')), \
                 patch.object(matrix.subprocess,'Popen',side_effect=AssertionError('process')), \
                 patch.object(matrix.socket,'socket',side_effect=AssertionError('socket')), \
                 patch.object(Path,'write_text',side_effect=AssertionError('write')), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(matrix.main(args),0)

    def test_compat_python_children_and_record(self):
        """Exercise real pure-Python children, namespacing and existing update.

        仅执行合成 Python 子进程，检查隔离路径和已有 update 判定写入。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            work=Path(folder)
            out=work/'evidence'
            out.mkdir()
            checkpoint=out/'matrix-unit-checkpoints.md'
            checkpoint.write_text('# unit\n\n| A4 | BLOCKED | pending |\n',encoding='utf-8')
            child=work/'child.py'
            child.write_text("from pathlib import Path\nfrom coverage_record import update\nO=Path(__file__).parent/'coverage_evidence'\n(O/'child.json').write_text('{}')\nupdate('unit',[('A4','PASS','current')],[])\n",encoding='utf-8')
            parent=work/'parent.py'
            parent.write_text("import subprocess,sys\nfrom pathlib import Path\nsubprocess.run([sys.executable,str(Path(__file__).with_name('child.py'))],check=True)\n",encoding='utf-8')
            result=subprocess.run([sys.executable,'-B',str(matrix.TOOL/'matrix_compat.py'),str(out),'matrix-unit-','unit',str(parent)],capture_output=True,text=True,
                                  env=dict(os.environ,MOVA_MATRIX_SERIAL='offline-unit'),timeout=20)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertTrue((out/'matrix-unit-child.json').exists())
            self.assertIn('| A4 | PASS | current |',checkpoint.read_text(encoding='utf-8'))
            commandlog=(out/'matrix-unit-unit.commands.driver.log').read_text(encoding='utf-8')
            self.assertIn('CALL',commandlog)
            self.assertIn('"exit": 0',commandlog)

    def test_compat_missing_child_completion_is_harness(self):
        """Catch historical child drivers that exit zero without completion.

        识别旧子脚本退出0但无完成证据的验证器错误。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            work=Path(folder);out=work/'evidence';out.mkdir()
            child=work/'coverage_suite_device.py'
            child.write_text("print('fake offline verifier')\n",encoding='utf-8')
            parent=work/'parent.py'
            parent.write_text("import subprocess,sys\nfrom pathlib import Path\nsubprocess.run([sys.executable,str(Path(__file__).with_name('coverage_suite_device.py')),'--name','probe'],check=True)\n",encoding='utf-8')
            result=subprocess.run([sys.executable,'-B',str(matrix.TOOL/'matrix_compat.py'),str(out),'matrix-unit-','unit',str(parent)],capture_output=True,text=True,
                                  env=dict(os.environ,MOVA_MATRIX_SERIAL='offline-unit'),timeout=20)
            self.assertEqual(result.returncode,0,result.stderr)
            errors=(out/'matrix-unit-unit.harness-errors.jsonl').read_text(encoding='utf-8')
            self.assertIn('completion metadata missing',errors)

    def test_cleanup_continues_and_verifies_restoration(self):
        """Verify finally restoration order with a fake adb function only.

        使用假 adb 函数验证失败后的完整恢复，不启动任何命令。
        """
        with tempfile.TemporaryDirectory(dir=matrix.TOOL) as folder:
            driver=object.__new__(matrix.Driver)
            driver.out=Path(folder);driver.prefix='matrix-unit-';driver.log=driver.out/'driver.log'
            driver.results={};driver.saved=dict(power='7',volume='6');driver.children=[]
            driver.mappings=[('reverse',18082)]
            driver.original_mappings={'reverse':{'tcp:18082':'tcp:19000'},'forward':{}}
            calls=[]
            def fake_adb(*argv):
                """Record fake command arguments / 记录模拟命令参数。"""
                calls.append(argv)
                if argv==('shell','am','force-stop',matrix.PACKAGE):raise RuntimeError('fake force-stop failure')
                if '--get' in argv:return 'volume is 6 in range [0..20]'
                if 'get' in argv:return '7'
                return ''
            driver.adb=fake_adb
            driver.cleanup()
            self.assertIn(('shell','media','volume','--stream','3','--set','6'),calls)
            self.assertIn(('shell','settings','put','global','stay_on_while_plugged_in','7'),calls)
            self.assertIn(('reverse','tcp:18082','tcp:19000'),calls)
            self.assertEqual(driver.results['cleanup']['kind'],'HARNESS')


if __name__=='__main__':
    unittest.main()
