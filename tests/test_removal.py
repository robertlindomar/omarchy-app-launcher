from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from test_search import m

class RemovalTests(unittest.TestCase):
    def test_critical_package_and_transitive_dependency(self):
        self.assertTrue(m.removal_risks('nautilus',['nautilus']))
        self.assertTrue(m.removal_risks('ordinary',['ordinary','pipewire']))
        self.assertFalse(m.removal_risks('ordinary',['ordinary','unused-lib']))
    def test_reverse_dependencies_and_failed_simulation(self):
        self.assertTrue(m.removal_risks('ordinary',[],'dependent',False))
    def test_local_launcher_only_and_no_commands(self):
        with tempfile.TemporaryDirectory() as d:
            data=Path(d);(data/'applications').mkdir()
            (data/'applications/my-app.desktop').write_text('[Desktop Entry]\nExec=my-app\n')
            with patch.dict(m.os.environ,{'XDG_DATA_HOME':str(data)}),patch.object(m,'run') as run:
                result=m.inspect_removal('my-app')
                self.assertTrue(result['canRemove']);self.assertFalse(result['risky'])
                self.assertIn('atalho',result['summary']);run.assert_not_called()
    def test_package_analysis_is_read_only(self):
        with tempfile.TemporaryDirectory() as d:
            data=Path(d);(data/'applications').mkdir()
            (data/'applications/example.desktop').write_text('[Desktop Entry]\nExec=example\n')
            calls=[]
            def run(argv,**kw):
                calls.append(argv)
                if '-Qqo' in argv:return 'example\n'
                if '--print' in argv:return 'example\nunused-lib\n'
                return 'Required By     : None\n'
            with patch.dict(m.os.environ,{'XDG_DATA_HOME':str(data/'user'),'XDG_DATA_DIRS':str(data)}),patch.object(m,'run',side_effect=run):
                result=m.inspect_removal('example')
            self.assertFalse(result['risky']);self.assertTrue(result['canRemove'])
            for argv in calls:
                self.assertNotIn('sudo',argv)
                if '-Rs' in argv:self.assertIn('--print',argv)
    def test_unsupported_id_and_missing_app_do_not_remove(self):
        self.assertFalse(m.inspect_removal('../bad')['canRemove'])
        with tempfile.TemporaryDirectory() as d,patch.dict(m.os.environ,{'XDG_DATA_HOME':d,'XDG_DATA_DIRS':d}):
            self.assertFalse(m.inspect_removal('missing-app')['canRemove'])

class AgentRemovalTests(unittest.TestCase):
    def test_mise_wrapper_is_detected_without_execution(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d);wrapper=home/'.local/bin/opencode';wrapper.parent.mkdir(parents=True)
            wrapper.write_text('mise use -g --quiet "opencode"\nexec mise x "opencode" -- "opencode" "$@"\n')
            def run(argv,**kw):
                if argv[0]=='pacman':return ''
                if argv[:3]==['mise','ls','--json']:
                    import json
                    return json.dumps([{'installed':True,'active':True,'source':{'path':str(home/'.config/mise/config.toml')}}])
                raise AssertionError('Não deve executar outro comando: '+str(argv))
            with patch.object(m,'HOME',home),patch.object(m.shutil,'which',return_value=str(wrapper)),patch.object(m,'run',side_effect=run):
                plan=m.inspect_agent('opencode')
                self.assertTrue(plan['canRemove']);self.assertTrue(plan['risky'])
                self.assertEqual(plan['strategy'],'mise');self.assertEqual(plan['wrapper'],str(wrapper))
    def test_unknown_agent_has_explanation(self):
        with patch.object(m.shutil,'which',return_value='/tmp/unknown'),patch.object(m,'run',return_value=''):
            plan=m.inspect_agent('unknown')
            self.assertFalse(plan['canRemove']);self.assertIn('segurança',plan['summary'])
    def test_binary_is_not_a_shell_command(self):
        self.assertFalse(m.inspect_agent('opencode; touch /tmp/evil')['canRemove'])

if __name__=='__main__':unittest.main()
