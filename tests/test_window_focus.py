import json
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from test_search import m

class WindowFocusTests(unittest.TestCase):
    def test_current_dispatcher(self):
        with patch.object(m.time,'sleep'),patch.object(m,'run',return_value=json.dumps([{'address':'0x123'}])),patch.object(m.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as dispatch:
            m.focus_window('0x123')
            self.assertEqual(dispatch.call_args.args[0],['hyprctl','dispatch','hl.dsp.focus({ window = "address:0x123" })'])
            self.assertEqual(dispatch.call_count,1)
    def test_missing_window_never_dispatches(self):
        with patch.object(m.time,'sleep'),patch.object(m,'run',return_value='[]'),patch.object(m.subprocess,'run') as dispatch:
            with self.assertRaises(ValueError):m.focus_window('0x123')
            dispatch.assert_not_called()
    def test_address_cannot_inject_lua(self):
        with self.assertRaises(ValueError):m.focus_window('0x123" }); os.execute("evil")')
    def test_legacy_fallback(self):
        with patch.object(m.time,'sleep'),patch.object(m,'run',return_value='[{"address":"0x123"}]'),patch.object(m.subprocess,'run',side_effect=[SimpleNamespace(returncode=1),SimpleNamespace(returncode=0)]) as dispatch:
            m.focus_window('0x123')
            self.assertEqual(dispatch.call_args.args[0],['hyprctl','dispatch','focuswindow','address:0x123'])
