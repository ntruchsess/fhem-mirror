var	fhem = {

	connected: false,

	con: null,

	devices: {},
	
	ondebug: null,
	
	onerror: null,
	
	onconnected: null,
	
	ondisconnected: null,
	
	onevent: null,
	
	onlist: null,
	
	connect: function(address,port) {
		var con = new WebSocket('ws://'+address+':'+port, ['json']);

		con.onopen = function() {
			fhem.connected = true;
			fhem.debug('Connection opened to fhem server!');
			if (fhem.onconnected!=null) {
				fhem.onconnected();
			}
		};

		con.onclose = function() {
			fhem.connected = false;
			fhem.debug('Connection closed to fhem server!');
			if (fhem.ondisconnected!=null) {
				fhem.ondisconnected();
			}
		};

		con.onerror = function(e) {
			fhem.error('Websocket error ' + e.data + '.');
		};

		con.onmessage = function(e) {
			fhem.debug("receiving data: "+e.data);
			var msg = JSON.parse(e.data);
			fhem.debug("receiving message: "+JSON.stringify(msg));

			switch(msg.type) {
			case 'event':
				fhem.onEvent(msg.payload);
				break;
			case 'listentry':
				fhem.onListentry(msg.payload);
				break;
			case 'commandreply':
				fhem.onCommand(msg.payload);
				break;
			default:
			}
		};

		fhem.con = con;
	},

	disconnect: function() {
		fhem.con.close();
	},

	debug: function(m) {
		if (fhem.ondebug != null) {
			fhem.ondebug(m);
		}
	},
	
	error: function(m) {
		if (fhem.onerror != null) {
			fhem.onerror(m);
		}
	},
	
	onEvent: function(event) {
		for(key in event.changed) {
			if (key == 'STATE') {
				fhem.devices[event.name].internals['STATE'] = event.changed[key];
			} else {
				fhem.devices[event.name].readings[key].value = event.changed[key];
				fhem.devices[event.name].readings[key].time  = event.time;
			}
		}
		if (fhem.onevent != null) {
			fhem.onevent();
		}
	},

	onListentry: function(entry) {
		fhem.devices[entry.name] = {
			internals:  entry.internals,
			readings:   entry.readings,
			attributes: entry.attributes,
			sets:       entry.sets,
			gets:       entry.gets,
			attrList:   entry.attrList
		};
		if ((entry.index+1 == entry.num) && (fhem.onlist != null)) {
			fhem.onlist();
		}
	},

	onCommand: function(cmd) {
		switch(cmd.command) {
		case 'not implemented yet':
			break;
		default:
		}
	},

	sendCommand: function(cmd) {
		fhem.con.send(JSON.stringify({
			type: 'command',
			payload: cmd
		}));
	},
		
	subscribeAll: function() {
		fhem.sendCommand({
			command: 'subscribe',
			arg: 'all'
		});
	}
};
