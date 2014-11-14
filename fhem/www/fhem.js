function fhem() {

	var con = null;
	var fhem = this;

	fhem.connected = false;
	fhem.devices = {};
	fhem.ondebug = null;
	fhem.onerror = null;
	fhem.onconnected = null;
	fhem.ondisconnected = null;
	fhem.onevent = null;
	fhem.onlist = null;
	fhem.ongetreply = null;
	fhem.oncommandreply = null;

	function debug(m) {
		if (fhem.ondebug != null) {
			fhem.ondebug(m);
		}
	};
	
	function error(m) {
		if (fhem.onerror != null) {
			fhem.onerror(m);
		}
	};
	
	function onEvent(event) {
		if (!fhem.devices[event.name]) {
			fhem.devices[event.name] = {
				internals:  {},
				readings:   {},
				attributes: {},
				sets:       {},
				gets:       {},
				attrList:   {}
			};
		}
		for(key in event.changed) {
			if (key == 'STATE') {
				fhem.devices[event.name].internals['STATE'] = event.changed[key];
			} else {
				fhem.devices[event.name].readings[key] = {
					value: event.changed[key],
					time:  event.time
				};
			}
		}
		if (fhem.onevent != null) {
			fhem.onevent();
		}
	};

	function onListentry(entry) {
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
	};

	function onGetreply(reply) {
		if (fhem.ongetreply != null) {
			fhem.ongetreply(reply.device,reply.property,reply.value);
		};
	};

	function onCommand(cmd) {
		switch(cmd.command) {
		case 'not implemented yet':
			break;
		default:
			if (fhem.oncommandreply != null) {
				fhem.oncommandreply(cmd.command,cmd.reply);
			};
		}
	};
	
	fhem.connect = function(address,port) {

		if (fhem.connected) {
			fhem.disconnect();
		}
		
		fhem.con = new WebSocket('ws://'+address+':'+port, ['json']);

		fhem.con.onopen = function() {
			fhem.connected = true;
			debug('Connection opened to fhem server!');
			if (fhem.onconnected!=null) {
				fhem.onconnected();
			}
		};

		fhem.con.onclose = function() {
			fhem.connected = false;
			debug('Connection closed to fhem server!');
			if (fhem.ondisconnected!=null) {
				fhem.ondisconnected();
			}
		};

		fhem.con.onerror = function(e) {
			fhem.error('Websocket error ' + e.data + '.');
		};

		fhem.con.onmessage = function(e) {
			debug("receiving data: "+e.data);
			var msg = JSON.parse(e.data);
			debug("receiving message: "+JSON.stringify(msg));

			switch(msg.type) {
			case 'event':
				onEvent(msg.payload);
				break;
			case 'listentry':
				onListentry(msg.payload);
				break;
			case 'getreply':
				onGetreply(msg.payload);
				break;
			case 'commandreply':
				onCommand(msg.payload);
				break;
			default:
			}
		};
	},

	fhem.disconnect = function() {
		fhem.con.close();
	};

	fhem.sendCommand = function(cmd) {
		fhem.con.send(JSON.stringify({
			type: 'command',
			payload: cmd
		}));
	};
	
	fhem.subscribe = function(id,type,name,changed) {
		fhem.sendCommand({
			command: 'subscribe',
			arg:     id,
			type:    type,
			name:    name,
			changed: changed
		});
	};
	
	fhem.unsubscribe = function(id) {
		fhem.sendCommand({
			command: 'unsubscribe',
			arg:     id
		});
	};
	
	fhem.list = function(devspec) {
		fhem.sendCommand({
			command: 'list',
			arg:     devspec
		});
	};
	
	fhem.set = function(device,property,value) {
		fhem.sendCommand({
			command: 'set '+device+' '+property+' '+value
		});
	};
	
	fhem.get = function(device,property) {
		fhem.sendCommand({
			command: 'get '+device+' '+property
		});
	};
	
};
