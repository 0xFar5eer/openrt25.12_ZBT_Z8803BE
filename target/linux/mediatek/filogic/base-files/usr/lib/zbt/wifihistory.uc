#!/usr/bin/env ucode

'use strict';

import { readfile, writefile, mkdir } from 'fs';

const HISTORY_DIR = '/etc/wifihistory';
const HISTORY_FILE = HISTORY_DIR + '/history.json';
const OLD_HISTORY_FILE = '/var/lib/wifihistory/history.json';

function migrate_legacy() {
	if (readfile(HISTORY_FILE) != null)
		return;

	let content = readfile(OLD_HISTORY_FILE);
	if (content != null) {
		mkdir(HISTORY_DIR);
		writefile(HISTORY_FILE, content);
	}
}

const methods = {
	getHistory: {
		call: function() {
			migrate_legacy();

			let content = readfile(HISTORY_FILE);
			if (content == null)
				return { history: {} };

			try {
				return { history: json(content) || {} };
			}
			catch (e) {
				return { history: {} };
			}
		}
	},

	clearHistory: {
		call: function() {
			mkdir(HISTORY_DIR);
			writefile(HISTORY_FILE, '{}');
			return { result: true };
		}
	}
};

return { 'luci.wifihistory': methods };
