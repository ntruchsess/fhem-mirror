(function() {
  if (typeof(jQuery) === 'undefined') {
    var scriptPath = "fhem/pgm2/jquery.min.js";
    var xhrObj = new XMLHttpRequest(); 
    xhrObj.open('GET', scriptPath, false);
    xhrObj.send('');
    var newscript = document.createElement('script');
    newscript.type = 'text/javascript';
    newscript.async = true;
    newscript.text = xhrObj.responseText;
    xhrObj.abort();
    (document.getElementsByTagName('head')[0]||document.getElementsByTagName('body')[0]).appendChild(newscript);
  }
})();

function sveReadGADList(device) {
  console.log('read list');
  var url = $(location).attr('pathname');
  var transfer = {};
  transfer.cmd = 'gadList';
  var dataString = 'dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
  $.ajax({
    type: "POST",
    url: url,
    data: dataString,
    cache: false,
    success: function (gadList) {
      sveRefreshGADList(device, gadList);
    }
  });
}

function sveRefreshGADList(device, gadList) {
  console.log('refresh list');
  var gad = $.parseJSON(gadList);
  var insert = [];
  insert.push('<table id="gadlisttable">');
  $.each(gad, function(i, item) {
    insert.push('<tr id=' + i + ' style="cursor:pointer"><td><a>' + i + '</a></td><td>nnn</td></tr>');
  });
  insert.push('</table>');
  $('#gadlist').html(insert.join(''));
  $('#gadlisttable tr').click(function () {
    sveLoadGADitem(device, $(this).attr('id'));
  });
}

function sveLoadGADitem(device, gadName) {
  console.log('load item');
  var url = $(location).attr('pathname');
  var transfer = {};
  transfer.cmd = 'gadItem';
  transfer.item = gadName;
  var dataString ='dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
  $.ajax({
      type: "POST",
      url: url,
      data: dataString,
      cache: false,
      success: function (gadItem) {
        sveShowGADEditor(device, gadName, gadItem);
      }
    });
}

function sveShowGADEditor(device, gadName, gadItem) {
  console.log('show editor');
  var gad = $.parseJSON(gadItem);
  var mode = gad.type + ':' + gad.mode;
  console.log(gad);
  console.log(mode);
  switch (mode) {
    case 'item:simple':
      sveGADEditorSimple(device, gadName, gad);
      break;
    default:
      sveGADEditorTypeSelect(device, gadName, gad);
      break;
  }
  return;
}

function sveGADEditorSimple(device, gadName, gad) {
  console.log('edtor simple');
  console.log(gadName);
  $('#gadeditor').replaceWith($('<table/>', {id: 'gadeditor'}));
  $('#gadeditor').append('<tr><td>' + 'GAD' + '</td><td>' + gadName +'</td></tr>');

  sveGADEdtorAddTypeSelect(device, gadName, gad);
  $('#gadEditTypeSelect').change(function() {
    var transfer = {
      cmd: 'gadModeSelect',
      item: gadName,
      editor: $(this).val()
    };
    sveGADEditorSave(device, gadName, transfer, function() {sveLoadGADitem(device, gadName)});
  });
  
  $('#gadeditor').append('<tr><td>' + 'device' + '</td><td><input id="gadEditDevice" width="100%" type="text" value="' + gad.device +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'reading' + '</td><td><input id="gadEditReading" type="text" value="' + gad.reading +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'converter' + '</td><td><input id="gadEditConverter" type="text" value="' + gad.simple.converter +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'cmd set' + '</td><td><input id="gadEditSet" type="text" value="' + gad.simple.set +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>&nbsp;</td><td>&nbsp;</td></tr>');
  $('#gadeditor').append('<tr><td>permission for </td><td>' + device + '</td></tr>');
  sveGADEdtorAddPermissionSelect(device, gadName, gad);

  $('#gadeditor').append('<tr><td>&nbsp;</td><td>&nbsp;</td></tr>');
  $('#gadeditor').append('<button id="gadEditCancel" type="button">cancel</button>');
  $('#gadeditor').append('<button id="gadEditSave" type="button">save</button>');

  $('#gadEditSave').click(function() {
    var transfer = {
      cmd: 'gadItemSave',
      item: gadName,
      editor: $('#gadEditTypeSelect').val(),
      config: {
        type: 'item',
        device: $('#gadEditDevice').val(),
        reading: $('#gadEditReading').val(),
        converter: $('#gadEditConverter').val(),
        set: $('#gadEditSet').val()
      },
      access: $('#gadEditPermissionSelect').val()
    }
    sveGADEditorSave(device, gadName, transfer, function(){
      $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: 'save setting: ' + gadName + ' ...', style: 'color: green'}));
      $('#gadeditcontainer').delay(1500).fadeOut();
    });
  });

  $('#gadeditcontainer').show();
}

function sveGADEditorTypeSelect(device, gadName, gad) {
  console.log('type select');
  console.log(gadName);
  $('#gadeditor').replaceWith($('<table/>', {id: 'gadeditor'}));
  $('#gadeditor').append('<tr><td>' + 'GAD' + '</td><td>' + gadName +'</td></tr>');

  sveGADEdtorAddTypeSelect(device, gadName, gad);
  $('#gadEditTypeSelect').change(function() {
    var transfer = {
      cmd: 'gadModeSelect',
      item: gadName,
      editor: $(this).val()
    };
    sveGADEditorSave(device, gadName, transfer, function() {sveLoadGADitem(device, gadName);});
  });

  $('#gadeditcontainer').show();
}

function sveGADEdtorAddTypeSelect(device, gadName, gad) {
  console.log('add type select');
  console.log(gad);
  $('#gadeditor').append('<tr><td>' + 'mode' + '</td><td><select id="gadEditTypeSelect"/></td></tr>');
  $('<option/>').val('unknown:unknown').text('unknown').appendTo('#gadEditTypeSelect');
  $('<option/>').val('item:simple').text('item').appendTo('#gadEditTypeSelect');
  $('<option/>').val('item:expert').text('item expert').appendTo('#gadEditTypeSelect');
  $('#gadEditTypeSelect').val(gad.editor);
}

function sveGADEditorSave(device, gadName, transfer, success, error) {
  console.log('gad save');
  console.log(success);
  var url = $(location).attr('pathname');
  var dataString ='dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
  $.ajax({
    type: "POST",
    url: url,
    data: dataString,
    cache: false,
    success: success
  });
}

function sveGADEdtorAddPermissionSelect() {
  console.log('add permission');
  $('#gadeditor').append('<tr><td>' + 'access' + '</td><td><select id="gadEditPermissionSelect"/></td></tr>');
  $('<option/>').val('none').text('none').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('r').text('read').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('w').text('write').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('rw').text('read/write').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('pin').text('pin (special)').appendTo('#gadEditPermissionSelect');
  $('#gadEditPermissionSelect').val('pin');
}

