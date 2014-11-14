function fhem() {

	var con = null;
	var fhem = this;
	var msgtypes = {};

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
			if (fhem.onevent != null) {
				fhem.onevent(event.name,key,event.changed[key],event.time);
			}
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
		
		con = new WebSocket('ws://'+address+':'+port, ['json']);

		con.onopen = function() {
			fhem.connected = true;
			debug('Connection opened to fhem server!');
			if (fhem.onconnected!=null) {
				fhem.onconnected();
			}
		};

		con.onclose = function() {
			fhem.connected = false;
			debug('Connection closed to fhem server!');
			if (fhem.ondisconnected!=null) {
				fhem.ondisconnected();
			}
		};

		con.onerror = function(e) {
			fhem.error('Websocket error ' + e.data + '.');
		};

		con.onmessage = function(e) {
			debug("receiving data: "+e.data);
			var msg = JSON.parse(e.data);
			debug("receiving message: "+JSON.stringify(msg));

			for(id in msgtypes[msg.type]) {
				msgtypes[msg.type][id](msg.payload);
			}
		};
	},

	fhem.disconnect = function() {
		con.close();
	};

	fhem.sendCommand = function(cmd) {
		con.send(JSON.stringify({
			type: 'command',
			payload: cmd
		}));
	};
	
	fhem.subscribeEvent = function(id,type,name,changed) {
		fhem.sendCommand({
			command: 'subscribe',
			arg:     id,
			type:    type,
			name:    name,
			changed: changed
		});
	};
	
	fhem.unsubscribeEvent = function(id) {
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
			command:  'get',
			device:   device,
			property: property
		});
	};

	fhem.subscribeMsgType = function(type,fn,id) {
		if (!msgtypes[type]) {
			msgtypes[type] = {
				id: fn
			};
		} else {
			msgtypes[type][id] = fn;
		}
	};
	
	fhem.unsubscribeMsgType = function(type,id) {
		delete msgtypes[type][id];
	};

	fhem.subscribeMsgType('event',onEvent,'fhem');
	fhem.subscribeMsgType('listentry',onListentry,'fhem');
	fhem.subscribeMsgType('getreply',onGetreply,'fhem');
	fhem.subscribeMsgType('commandreply',onCommand,'fhem');
};
