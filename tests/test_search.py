import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

path=Path(__file__).parents[1]/'bin/launcher-search'
loader=importlib.machinery.SourceFileLoader('launcher_search',str(path))
spec=importlib.util.spec_from_loader(loader.name,loader)
m=importlib.util.module_from_spec(spec);loader.exec_module(m)

class SearchTests(unittest.TestCase):
    def test_window_prefix_and_multiple_words(self):
        data=[{'address':'0x123','title':'Contrato Robert','class':'editor','workspace':{'name':'2'}}]
        with patch.object(m,'run',return_value=json.dumps(data)):
            self.assertEqual(m.search('w: contrato editor')['rows'][0]['address'],'0x123')
            self.assertEqual(m.search('w: ausente')['rows'],[])
    def test_file_arguments_do_not_execute_input(self):
        calls=[]
        with patch.object(m,'run',side_effect=lambda argv,**kw: calls.append(argv) or ''):
            m.files('$(touch /tmp/evil) contrato.pdf')
        self.assertIn('--and',calls[0])
        self.assertIn(r'contrato\.pdf',calls[0])
        self.assertEqual(calls[0][0],'fd')
    def test_clipboard_results_do_not_contain_full_text(self):
        secret='documento '*100
        with patch.object(m,'history',return_value=[secret,secret]):
            rows=m.search('cb: documento')['rows']
            self.assertEqual(len(rows),1)
            self.assertNotIn(secret,json.dumps(rows))
            self.assertEqual(rows[0]['hash'],m.digest(secret))
    def test_clipboard_reidentifies_after_reordering(self):
        with patch.object(m,'history',return_value=['novo','anterior']),patch.object(m,'copy_text') as copy:
            m.action(['clipboard',m.digest('anterior')]);copy.assert_called_once_with('anterior')
    def test_missing_clipboard_item_never_copies_another(self):
        with patch.object(m,'history',return_value=['novo']),patch.object(m,'copy_text') as copy:
            with self.assertRaises(ValueError):m.action(['clipboard',m.digest('removido')])
            copy.assert_not_called()
    def test_accents_and_case(self):
        self.assertTrue(m.matches('Área de Trabalho','area trabalho'))
    def test_history_refuses_symlinks(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d);directory=home/'.local/state/omarchy';directory.mkdir(parents=True)
            target=home/'other.json';target.write_text('[{"type":"text","text":"private"}]')
            (directory/'clipboard-history.json').symlink_to(target)
            with patch.object(m,'HOME',home):self.assertEqual(m.history(),[])

    def test_ssh_includes_globs_cycles_and_aliases(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d);ssh=home/'.ssh';ssh.mkdir();(ssh/'hosts').mkdir()
            (ssh/'config').write_text('Include hosts/*.conf\nHost prod producao * !excluded -bad\n  HostName example.com\nMatch exec "must-not-run"\nInclude hosts/*.conf\n')
            (ssh/'hosts/extra.conf').write_text('Host dev prod\nInclude config\nHost="quoted-host"\n')
            with patch.object(m,'HOME',home),patch.object(m,'run') as run:
                rows=m.search('ssh:')['rows']
                self.assertEqual({r['name'] for r in rows},{'prod','producao','dev','quoted-host'})
                self.assertEqual(len(m.search('ssh: PRODu')['rows']),1)
                self.assertEqual(next(r for r in rows if r['name']=='prod')['sshArgs'],['ssh','--','prod'])
                run.assert_not_called()
    def test_ssh_known_hosts_port_hashed_and_duplicates(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d);ssh=home/'.ssh';ssh.mkdir()
            (ssh/'config').write_text('Host example.com\n')
            (ssh/'known_hosts').write_text('example.com,other.example ssh-ed25519 AAAA\n[server.example]:2222 ssh-ed25519 AAAA\n|1|abc|def ssh-ed25519 AAAA\n*.wild,!excluded ssh-ed25519 AAAA\n')
            with patch.object(m,'HOME',home):
                rows=m.search('ssh:')['rows']
                self.assertEqual(len(rows),3)
                selected=m.search('ssh: server')['rows'][0]
                self.assertEqual(selected['sshArgs'],['ssh','-p','2222','--','server.example'])
                self.assertEqual(selected['copyText'],'ssh -p 2222 -- server.example')
    def test_ssh_missing_config(self):
        with tempfile.TemporaryDirectory() as d,patch.object(m,'HOME',Path(d)):
            result=m.search('ssh:')
            self.assertEqual(result['rows'],[])
            self.assertIn('Nenhum host',result['message'])

if __name__=='__main__':unittest.main()
