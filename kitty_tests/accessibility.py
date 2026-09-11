#!/usr/bin/env python
# License: GPLv3

from types import SimpleNamespace
from unittest.mock import patch

from kitty.boss import Boss
from kitty.tabs import TabManager

from . import BaseTest


class TestAccessibility(BaseTest):

    def test_accessibility_selection_follows_active_tab(self):
        boss = object.__new__(Boss)
        manager = object.__new__(TabManager)
        manager.os_window_id = 100
        manager._active_tab_idx = 0
        screens = [self.create_screen(cols=20) for _ in range(2)]
        windows = []
        for screen, text in zip(screens, ('first tab', 'second tab')):
            screen.draw(text)
            screen.start_selection(0, 0)
            screen.update_selection(len(text) - 1, 0)
            windows.append(SimpleNamespace(
                destroyed=False,
                text_for_selection=lambda screen=screen: ''.join(screen.text_for_selection()),
                has_selection=screen.has_selection,
            ))
        manager.tabs = [SimpleNamespace(active_window=w) for w in windows]
        boss.os_window_map = {100: manager}
        with patch('kitty.boss.current_focused_os_window_id', return_value=100), patch('kitty.tabs.set_active_tab'):
            self.assertEqual(boss.get_active_selection(), 'first tab')
            manager._set_active_tab(1, store_in_history=False)
            self.assertEqual(boss.get_active_selection(), 'second tab')
            self.assertTrue(boss.has_active_selection())
            # An empty selection must not fall back to a previous tab's text.
            screens[1].clear_selection()
            self.assertEqual(boss.get_active_selection(), '')
            self.assertFalse(boss.has_active_selection())
            manager._set_active_tab(0, store_in_history=False)
            self.assertEqual(boss.get_active_selection(), 'first tab')
